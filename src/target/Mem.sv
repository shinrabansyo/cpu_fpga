//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//   http://www.apache.org/licenses/LICENSE-2.0
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
// either express or implied. See the License for the specific
// language governing permissions and limitations under the License.
//
// MIT License
// Permission is hereby granted, free of charge, to any person obtaining
// a copy of this software and associated documentation files...

// Copyright:
// This file is originally based on:
// https://github.com/veryl-lang/veryl/blob/6d3c23ce2d176a192ad67dcd99c97914cf5d46cb/crates/std/veryl/src/ram/ram.veryl

module veryl_Div6 (
    input  logic [32-1:0] x        ,
    output logic [32-1:0] quotient ,
    output logic [32-1:0] remainder
);

    // 6 の除算用マジックナンバー:
    // 2^34/6 = 2863311530.6666... の切り上げ値 = 2863311531 = 32'hAAAAAAAB
    logic [32-1:0] MAGIC; always_comb MAGIC = 32'hAAAAAAAB;

    // 64ビットの積を用いて計算
    logic [64-1:0] prod; always_comb prod = x * MAGIC;

    // 商は上位 64-34=30 ビット (32ビットに収まる)
    logic [64-1:0] shift   ; always_comb shift    = prod >> 34;
    always_comb quotient = shift[31:0];

    // 余りは、 x から商に6をかけた値を引く
    always_comb remainder = x - quotient * 6;
endmodule

module veryl_IMemSync #(
    parameter int unsigned WORD_SIZE     = 1024                  , // 1024個の命令を保持
    parameter int unsigned ADDRESS_WIDTH = 32                    , // アドレスは常に32bit
    parameter int unsigned ADDRESS_MAX   = 6 * $clog2(WORD_SIZE) , // アドレスの最大値 = 命令サイズ*WORD_SIZE
    parameter int unsigned DATA_WIDTH    = 48                    , // 命令長 48bit
    parameter type         DATA_TYPE     = logic [DATA_WIDTH-1:0],
    parameter bit          BUFFER_OUT    = 1                     , // 同期読み出し
    parameter DATA_TYPE    INITIAL_VALUE = DATA_TYPE'(0         )
) (
    input  logic                          i_clk , // クロック
    input  logic                          i_rst , // リセット
    input  logic                          i_clr , // リセット2
    input  logic                          i_mea , // セレクト (w)
    input  logic     [DATA_WIDTH / 8-1:0] i_wea , // バイト単位の書き込み許可 (w)
    input  logic     [ADDRESS_WIDTH-1:0]  i_adra, // アドレス (w)
    input  DATA_TYPE                      i_da  , // データ (w)
    input  logic                          i_meb , // セレクト (r)
    input  logic     [ADDRESS_WIDTH-1:0]  i_adrb, // アドレス (r)
    output DATA_TYPE                      o_qb   // データ (r)
);
    localparam int unsigned BANK_NUM = DATA_WIDTH / 8;

    logic [32-1:0] adra_mod ;
    logic [32-1:0] adrb_mod ;
    logic [32-1:0] adra_quot;
    logic [32-1:0] adrb_quot;

    veryl_Div6 div6_a (
        .x         (i_adra   ),
        .quotient  (adra_quot),
        .remainder (adra_mod )
    );
    veryl_Div6 div6_b (
        .x         (i_adrb   ),
        .quotient  (adrb_quot),
        .remainder (adrb_mod )
    );
    // let adra_mod: logic<32> = i_adra % BANK_NUM;
    // let adrb_mod: logic<32> = i_adrb % BANK_NUM;

    logic [32-1:0] adra_mod_buf;
    logic [32-1:0] adrb_mod_buf;

    always_ff @ (posedge i_clk) begin
        if (i_rst) begin
            adra_mod_buf <= 0;
            adrb_mod_buf <= 0;
        end else begin
            adra_mod_buf <= adra_mod;
            adrb_mod_buf <= adrb_mod;
        end
    end

    logic [DATA_WIDTH * 2-1:0] data_table;
    logic [DATA_WIDTH * 2-1:0] q_buf     ;
    always_comb o_qb       = q_buf[8 * adrb_mod_buf+:DATA_WIDTH];
    for (genvar bank_id = 0; bank_id < BANK_NUM; bank_id++) begin :g_bank
        localparam int unsigned                                   BANK_ADDRESS_WIDTH                 = $clog2(WORD_SIZE);
        logic        [BANK_ADDRESS_WIDTH-1:0]          bank_adra                         ;
        logic        [BANK_ADDRESS_WIDTH-1:0]          bank_adrb                         ;
        logic        [$bits(DATA_TYPE) / BANK_NUM-1:0] ram_data           [0:WORD_SIZE-1];
        logic        [$bits(DATA_TYPE) / BANK_NUM-1:0] q                                 ;

        // バンクアドレス計算用の一時変数
        logic [32-1:0] tmpa;
        logic [32-1:0] tmpb;

        always_comb begin
            // ワードサイズが 2^n じゃないと，バンク振り分けで除算が必要
            // バンク数 N のとき，読みたいアドレスが...
            // 整列されてる場合： 各バンク内のメモリアドレス = 入力アドレス / N
            // 非整列の場合： どれくらいズレているかによって振り分け方が変わる
            //   入力アドレス % N == 1 の時：
            //     バンク0内のメモリアドレス = 入力アドレス / N + 1
            //     バンク1～(N-1)内のメモリアドレス = 入力アドレス / N
            //   入力アドレス % N == 2 の時：
            //     バンク0～1内のメモリアドレス = 入力アドレス / N + 1
            //     バンク2～(N-1)内のメモリアドレス = 入力アドレス / N
            //  ...
            //   入力アドレス % N == x の時：
            //     バンク0～(x-1)内のメモリアドレス = 入力アドレス / N + 1
            //     バンク(x)～(N-1)内のメモリアドレス = 入力アドレス / N
            if (bank_id < adra_mod) begin
                // tmpa = i_adra / BANK_NUM + 1;
                tmpa = adra_quot + 1;
            end else begin
                // tmpa = i_adra / BANK_NUM;
                tmpa = adra_quot;
            end
            bank_adra = tmpa[BANK_ADDRESS_WIDTH - 1:0];

            if (bank_id < adrb_mod) begin
                // tmpb = i_adrb / BANK_NUM + 1;
                tmpb = adrb_quot + 1;
            end else begin
                // tmpb = i_adrb / BANK_NUM;
                tmpb = adrb_quot;
            end
            bank_adrb = tmpb[BANK_ADDRESS_WIDTH - 1:0];
        end

        initial begin
            // SystemVerilogでは $readmemh() の引数が文字列リテラルに限られており，変数は使用不可
            if (bank_id == 0) begin
                $readmemh("./test/tmp_inst_bank0.hex", ram_data);
            end else if (bank_id == 1) begin
                $readmemh("./test/tmp_inst_bank1.hex", ram_data);
            end else if (bank_id == 2) begin
                $readmemh("./test/tmp_inst_bank2.hex", ram_data);
            end else if (bank_id == 3) begin
                $readmemh("./test/tmp_inst_bank3.hex", ram_data);
            end else if (bank_id == 4) begin
                $readmemh("./test/tmp_inst_bank4.hex", ram_data);
            end else if (bank_id == 5) begin
                $readmemh("./test/tmp_inst_bank5.hex", ram_data);
            end
        end

        //     00 01 02 03
        // ---------------
        // 00: ef be ad de <- when adra_mod == 0
        // 04: 00 00 00 00    {bank0, bank1, bank2, bank3} <= {da0, da1, da2, da3}
        // ---------------
        // 00: 00 ef be ad <- when adra_mod == 1
        // 04: de 00 00 00    {bank0, bank1, bank2, bank3} <= {da3, da0, da1, da2}
        // ---------------
        // 00: 00 00 ef be <- when adra_mod == 2
        // 04: ad de 00 00    {bank0, bank1, bank2, bank3} <= {da2, da3, da0, da1}
        // ---------------
        // 00: 00 00 00 ef <- when adra_mod == 3
        // 04: be ad de 00    {bank0, bank1, bank2, bank3} <= {da1, da2, da3, da0}
        // ---------------
        always_ff @ (posedge i_clk) begin
            if (i_mea && i_wea[BANK_NUM - adra_mod + bank_id]) begin
                // ram_data[bank_adra] = i_da[((adra_mod + bank_id) % BANK_NUM)*8+:8]; と同じ
                ram_data[bank_adra] <= data_table[(BANK_NUM - adra_mod + bank_id) * 8+:8];
            end
        end

        always_comb begin
            q_buf[bank_id * 8+:8]                   = q;
            q_buf[bank_id * 8 + DATA_WIDTH+:8]      = q;
            data_table[bank_id * 8+:8]              = i_da[bank_id * 8+:8];
            data_table[bank_id * 8 + DATA_WIDTH+:8] = i_da[bank_id * 8+:8];
        end

        if (!BUFFER_OUT) begin :g_out
            always_comb begin
                // Write throughモード: 同じアドレスに書き込みがある場合は書き込みデータを返す
                if (i_mea && i_wea[BANK_NUM - adra_mod + bank_id] && bank_adra == bank_adrb) begin
                    q = data_table[(BANK_NUM - adra_mod + bank_id) * 8+:8];
                end else begin
                    q = ram_data[bank_adrb];
                end
            end
        end else begin :g_out
            always_ff @ (posedge i_clk) begin
                if (i_meb) begin
                    // Write throughモード: 同じアドレスに書き込みがある場合は書き込みデータを返す
                    if (i_mea && i_wea[BANK_NUM - adra_mod + bank_id] && bank_adra == bank_adrb) begin
                        q <= data_table[(BANK_NUM - adra_mod + bank_id) * 8+:8];
                    end else begin
                        q <= ram_data[bank_adrb];
                    end
                end
            end
        end
    end
endmodule

module veryl_DMemSync #(
    parameter int unsigned WORD_SIZE     = 1024                  , // 1024個の命令を保持
    parameter int unsigned ADDRESS_WIDTH = 32                    , // アドレスは常に32bit
    parameter int unsigned ADDRESS_MAX   = 4 * $clog2(WORD_SIZE) , // アドレスの最大値 = 命令サイズ*WORD_SIZE
    parameter int unsigned DATA_WIDTH    = 32                    , // 命令長 48bit
    parameter type         DATA_TYPE     = logic [DATA_WIDTH-1:0],
    parameter bit          BUFFER_OUT    = 1                     , // 同期読み出し
    parameter DATA_TYPE    INITIAL_VALUE = DATA_TYPE'(0         )
) (
    input  logic                          i_clk , // クロック
    input  logic                          i_rst , // リセット
    input  logic                          i_clr , // リセット2
    input  logic                          i_mea , // セレクト (w)
    input  logic     [DATA_WIDTH / 8-1:0] i_wea , // バイト単位の書き込み許可 (w)
    input  logic     [ADDRESS_WIDTH-1:0]  i_adra, // アドレス (w)
    input  DATA_TYPE                      i_da  , // データ (w)
    input  logic                          i_meb , // セレクト (r)
    input  logic     [ADDRESS_WIDTH-1:0]  i_adrb, // アドレス (r)
    output DATA_TYPE                      o_qb   // データ (r)
);
    localparam int unsigned BANK_NUM = DATA_WIDTH / 8;

    logic [32-1:0] adra_mod; always_comb adra_mod = i_adra % BANK_NUM;
    logic [32-1:0] adrb_mod; always_comb adrb_mod = i_adrb % BANK_NUM;

    logic [32-1:0] adra_mod_buf;
    logic [32-1:0] adrb_mod_buf;

    always_ff @ (posedge i_clk) begin
        if (i_rst) begin
            adra_mod_buf <= 0;
            adrb_mod_buf <= 0;
        end else begin
            adra_mod_buf <= adra_mod;
            adrb_mod_buf <= adrb_mod;
        end
    end

    logic [DATA_WIDTH * 2-1:0] data_table;
    logic [DATA_WIDTH * 2-1:0] q_buf     ;
    always_comb o_qb       = q_buf[8 * adrb_mod_buf+:DATA_WIDTH];
    for (genvar bank_id = 0; bank_id < BANK_NUM; bank_id++) begin :g_bank
        localparam int unsigned                                   BANK_ADDRESS_WIDTH                 = $clog2(WORD_SIZE);
        logic        [BANK_ADDRESS_WIDTH-1:0]          bank_adra                         ;
        logic        [BANK_ADDRESS_WIDTH-1:0]          bank_adrb                         ;
        logic        [$bits(DATA_TYPE) / BANK_NUM-1:0] ram_data           [0:WORD_SIZE-1];
        logic        [$bits(DATA_TYPE) / BANK_NUM-1:0] q                                 ;

        // バンクアドレス計算用の一時変数
        logic [32-1:0] tmpa;
        logic [32-1:0] tmpb;

        always_comb begin
            // ワードサイズが 2^n じゃないと，バンク振り分けで除算が必要
            // バンク数 N のとき，読みたいアドレスが...
            // 整列されてる場合： 各バンク内のメモリアドレス = 入力アドレス / N
            // 非整列の場合： どれくらいズレているかによって振り分け方が変わる
            //   入力アドレス % N == 1 の時：
            //     バンク0内のメモリアドレス = 入力アドレス / N + 1
            //     バンク1～(N-1)内のメモリアドレス = 入力アドレス / N
            //   入力アドレス % N == 2 の時：
            //     バンク0～1内のメモリアドレス = 入力アドレス / N + 1
            //     バンク2～(N-1)内のメモリアドレス = 入力アドレス / N
            //  ...
            //   入力アドレス % N == x の時：
            //     バンク0～(x-1)内のメモリアドレス = 入力アドレス / N + 1
            //     バンク(x)～(N-1)内のメモリアドレス = 入力アドレス / N
            if (bank_id < adra_mod) begin
                tmpa = i_adra / BANK_NUM + 1;
            end else begin
                tmpa = i_adra / BANK_NUM;
            end
            bank_adra = tmpa[BANK_ADDRESS_WIDTH - 1:0];

            if (bank_id < adrb_mod) begin
                tmpb = i_adrb / BANK_NUM + 1;
            end else begin
                tmpb = i_adrb / BANK_NUM;
            end
            bank_adrb = tmpb[BANK_ADDRESS_WIDTH - 1:0];
        end

        initial begin
            // SystemVerilogでは $readmemh() の引数が文字列リテラルに限られており，変数は使用不可
            if (bank_id == 0) begin
                $readmemh("./test/tmp_data_bank0.hex", ram_data);
            end else if (bank_id == 1) begin
                $readmemh("./test/tmp_data_bank1.hex", ram_data);
            end else if (bank_id == 2) begin
                $readmemh("./test/tmp_data_bank2.hex", ram_data);
            end else if (bank_id == 3) begin
                $readmemh("./test/tmp_data_bank3.hex", ram_data);
            end
        end

        //     00 01 02 03
        // ---------------
        // 00: ef be ad de <- when adra_mod == 0
        // 04: 00 00 00 00    {bank0, bank1, bank2, bank3} <= {da0, da1, da2, da3}
        // ---------------
        // 00: 00 ef be ad <- when adra_mod == 1
        // 04: de 00 00 00    {bank0, bank1, bank2, bank3} <= {da3, da0, da1, da2}
        // ---------------
        // 00: 00 00 ef be <- when adra_mod == 2
        // 04: ad de 00 00    {bank0, bank1, bank2, bank3} <= {da2, da3, da0, da1}
        // ---------------
        // 00: 00 00 00 ef <- when adra_mod == 3
        // 04: be ad de 00    {bank0, bank1, bank2, bank3} <= {da1, da2, da3, da0}
        // ---------------
        always_ff @ (posedge i_clk) begin
            if (i_mea && i_wea[BANK_NUM - adra_mod + bank_id]) begin
                // ram_data[bank_adra] = i_da[((adra_mod + bank_id) % BANK_NUM)*8+:8]; と同じ
                ram_data[bank_adra] <= data_table[(BANK_NUM - adra_mod + bank_id) * 8+:8];
            end
        end

        always_comb begin
            q_buf[bank_id * 8+:8]                   = q;
            q_buf[bank_id * 8 + DATA_WIDTH+:8]      = q;
            data_table[bank_id * 8+:8]              = i_da[bank_id * 8+:8];
            data_table[bank_id * 8 + DATA_WIDTH+:8] = i_da[bank_id * 8+:8];
        end

        if (!BUFFER_OUT) begin :g_out
            always_comb begin
                // Write throughモード: 同じアドレスに書き込みがある場合は書き込みデータを返す
                if (i_mea && i_wea[BANK_NUM - adra_mod + bank_id] && bank_adra == bank_adrb) begin
                    q = data_table[(BANK_NUM - adra_mod + bank_id) * 8+:8];
                end else begin
                    q = ram_data[bank_adrb];
                end
            end
        end else begin :g_out
            always_ff @ (posedge i_clk) begin
                if (i_meb) begin
                    // Write throughモード: 同じアドレスに書き込みがある場合は書き込みデータを返す
                    if (i_mea && i_wea[BANK_NUM - adra_mod + bank_id] && bank_adra == bank_adrb) begin
                        q <= data_table[(BANK_NUM - adra_mod + bank_id) * 8+:8];
                    end else begin
                        q <= ram_data[bank_adrb];
                    end
                end
            end
        end
    end
endmodule
//# sourceMappingURL=Mem.sv.map
