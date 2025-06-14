// module 宣言
// io宣言
module veryl_Core (
    // クロック・リセット
    input logic i_clk,
    input logic i_rst,

    // UART
    output logic [1-1:0] o_tx,
    input  logic [1-1:0] i_rx,

    // SPI
    output logic [1-1:0] o_sclk,
    output logic [1-1:0] o_mosi,
    input  logic [1-1:0] i_miso,

    // GPIO
    output logic [8-1:0] o_gpout,

    // HDMI
    input  logic          i_clk_dvi,
    input  logic          i_rst_dvi,
    output logic [1-1:0]  o_vsync  ,
    output logic [1-1:0]  o_hsync  ,
    output logic [1-1:0]  o_de     ,
    output logic [24-1:0] o_data   
);
    // ワイヤ・インタフェース宣言
    // IOBus
    logic [32-1:0] i_dev_id;

    veryl_Decoupled #(.Width (32)) if_io_bus_din  ();
    veryl_Decoupled #(.Width (32)) if_io_bus_dout ();

    // ALU
    logic [8-1:0]  w_command;
    logic [32-1:0] w_a      ;
    logic [32-1:0] w_b      ;
    logic [1-1:0]  w_zero   ;
    logic [32-1:0] w_out    ;

    // IOBus
    veryl_IOBus #(
        .ClockFrequency (12_000_000),
        .UartBaudRate   (115200    )
    ) io_bus (
        .i_clk     (i_clk         ),
        .i_rst     (i_rst         ),
        .i_dev_id  (i_dev_id      ),
        .if_din    (if_io_bus_dout),
        .if_dout   (if_io_bus_din ),
        .o_tx      (o_tx          ),
        .i_rx      (i_rx          ),
        .o_sclk    (o_sclk        ),
        .o_mosi    (o_mosi        ),
        .i_miso    (i_miso        ),
        .o_gpout   (o_gpout       ),
        .i_clk_dvi (i_clk_dvi     ),
        .i_rst_dvi (i_rst_dvi     ),
        .o_vsync   (o_vsync       ),
        .o_hsync   (o_hsync       ),
        .o_de      (o_de          ),
        .o_data    (o_data        )
    );

    // メモリ
    logic [32-1:0] m_regfile [0:32-1];

    logic [32-1:0] w_pc_fetching;
    logic [32-1:0] r_pc_fetched ;
    logic [48-1:0] w_instr_raw  ;

    logic [4-1:0]  w_wen      ;
    logic [1-1:0]  w_ren      ;
    logic [32-1:0] w_dmem_read;

    veryl_IMemSync m_inst_mod (
        .i_clk  (i_clk        ),
        .i_rst  (i_rst        ),
        .i_clr  (1'h0         ),
        .i_mea  (1'h0         ),
        .i_wea  (6'h0         ),
        .i_adra (32'h0        ),
        .i_da   (48'h0        ),
        .i_meb  (1'b1         ),
        .i_adrb (w_pc_fetching),
        .o_qb   (w_instr_raw  )
    );

    veryl_DMemSync #(
        .WORD_SIZE (4096)
    ) m_data_mod (
        .i_clk  (i_clk                   ),
        .i_rst  (i_rst                   ),
        .i_clr  (1'h0                    ),
        .i_mea  (|w_wen                  ),
        .i_wea  (w_wen                   ),
        .i_adra (w_out                   ),
        .i_da   (m_regfile[w_instr.rs2_s]),
        .i_meb  (w_ren                   ),
        .i_adrb (w_out                   ),
        .o_qb   (w_dmem_read             )
    );

    // 命令フェッチ
    logic [1-1:0] r_load_ready  ;
    logic [1-1:0] w_branch_taken;

    // プログラムカウンタ
    always_comb begin
        w_pc_fetching = ((({w_instr.opcode_sub, w_instr.opcode}) ==? (BEQ)) ? (
            ((w_branch_taken) ? ( r_pc_fetched + w_instr.imm_b_sext ) : ( r_pc_fetched + 32'h6 ))
        ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (BNE)) ? (
            ((w_branch_taken) ? ( r_pc_fetched + w_instr.imm_b_sext ) : ( r_pc_fetched + 32'h6 ))
        ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (BLT)) ? (
            ((w_branch_taken) ? ( r_pc_fetched + w_instr.imm_b_sext ) : ( r_pc_fetched + 32'h6 ))
        ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (BLE)) ? (
            ((w_branch_taken) ? ( r_pc_fetched + w_instr.imm_b_sext ) : ( r_pc_fetched + 32'h6 ))
        ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (JAL)) ? (
            w_out
        ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (LW)) ? (
            ((!r_load_ready) ? ( r_pc_fetched ) : ( r_pc_fetched + 32'h6 ))
        ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (LH)) ? (
            ((!r_load_ready) ? ( r_pc_fetched ) : ( r_pc_fetched + 32'h6 ))
        ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (LB)) ? (
            ((!r_load_ready) ? ( r_pc_fetched ) : ( r_pc_fetched + 32'h6 ))
        ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (LHU)) ? (
            ((!r_load_ready) ? ( r_pc_fetched ) : ( r_pc_fetched + 32'h6 ))
        ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (LBU)) ? (
            ((!r_load_ready) ? ( r_pc_fetched ) : ( r_pc_fetched + 32'h6 ))
        ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (IN)) ? (
            ((!if_io_bus_din.valid) ? ( r_pc_fetched ) : ( r_pc_fetched + 32'h6 ))
        ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (OUT)) ? (
            ((!if_io_bus_dout.ready) ? ( r_pc_fetched ) : ( r_pc_fetched + 32'h6 ))
        ) : (
            r_pc_fetched + 32'h6
        ));
    end

    always_ff @ (posedge i_clk) begin
        if (i_rst) begin
            r_pc_fetched <= 32'h0;
        end else begin
            r_pc_fetched <= w_pc_fetching;
        end
    end

    // 命令デコード
    typedef struct packed {
        logic [5-1:0]  opcode    ;
        logic [3-1:0]  opcode_sub;
        logic [5-1:0]  rd        ;
        logic [5-1:0]  rs1       ;
        logic [5-1:0]  rs1_i     ;
        logic [5-1:0]  rs1_s     ;
        logic [5-1:0]  rs2       ;
        logic [5-1:0]  rs2_s     ;
        logic [32-1:0] imm       ;
        logic [25-1:0] imm_b     ;
        logic [32-1:0] imm_b_sext;
    } Instructure;

    Instructure w_instr;

    always_comb w_instr.opcode     = w_instr_raw[4:0];
    always_comb w_instr.opcode_sub = w_instr_raw[7:5];
    always_comb w_instr.rd         = w_instr_raw[12:8];
    always_comb w_instr.rs1        = w_instr_raw[17:13];
    always_comb w_instr.rs1_i      = {2'b0, w_instr_raw[15:13]};
    always_comb w_instr.rs1_s      = {2'b0, w_instr_raw[15:13]};
    always_comb w_instr.rs2        = w_instr_raw[22:18];
    always_comb w_instr.rs2_s      = w_instr_raw[12:8];
    always_comb w_instr.imm        = w_instr_raw[47:16];
    always_comb w_instr.imm_b      = w_instr_raw[47:23];
    always_comb w_instr.imm_b_sext = {{7{w_instr_raw[47]}}, w_instr_raw[47:23]};

    // 命令実行
    localparam logic [8-1:0] NOP  = (8'h0 << 5) | 8'h0;
    localparam logic [8-1:0] ADD  = (8'h1 << 5) | 8'h1;
    localparam logic [8-1:0] SUB  = (8'h2 << 5) | 8'h1;
    localparam logic [8-1:0] ADDI = (8'h1 << 5) | 8'h2;
    localparam logic [8-1:0] SUBI = (8'h2 << 5) | 8'h2;
    localparam logic [8-1:0] BEQ  = (8'h0 << 5) | 8'h3;
    localparam logic [8-1:0] BNE  = (8'h1 << 5) | 8'h3;
    localparam logic [8-1:0] BLT  = (8'h2 << 5) | 8'h3;
    localparam logic [8-1:0] BLE  = (8'h3 << 5) | 8'h3;
    localparam logic [8-1:0] JAL  = (8'h4 << 5) | 8'h3;
    localparam logic [8-1:0] LW   = (8'h0 << 5) | 8'h4;
    localparam logic [8-1:0] LH   = (8'h1 << 5) | 8'h4;
    localparam logic [8-1:0] LB   = (8'h2 << 5) | 8'h4;
    localparam logic [8-1:0] LHU  = (8'h3 << 5) | 8'h4;
    localparam logic [8-1:0] LBU  = (8'h4 << 5) | 8'h4;
    localparam logic [8-1:0] SW   = (8'h0 << 5) | 8'h5;
    localparam logic [8-1:0] SH   = (8'h1 << 5) | 8'h5;
    localparam logic [8-1:0] SB   = (8'h2 << 5) | 8'h5;
    localparam logic [8-1:0] IN   = (8'h0 << 5) | 8'h6;
    localparam logic [8-1:0] OUT  = (8'h1 << 5) | 8'h6;
    localparam logic [8-1:0] AND  = (8'h0 << 5) | 8'h7;
    localparam logic [8-1:0] OR   = (8'h1 << 5) | 8'h7;
    localparam logic [8-1:0] XOR  = (8'h2 << 5) | 8'h7;
    localparam logic [8-1:0] SRL  = (8'h3 << 5) | 8'h7;
    localparam logic [8-1:0] SRA  = (8'h4 << 5) | 8'h7;
    localparam logic [8-1:0] SLL  = (8'h5 << 5) | 8'h7;
    localparam logic [8-1:0] ANDI = (8'h0 << 5) | 8'h8;
    localparam logic [8-1:0] ORI  = (8'h1 << 5) | 8'h8;
    localparam logic [8-1:0] XORI = (8'h2 << 5) | 8'h8;
    localparam logic [8-1:0] SRLI = (8'h3 << 5) | 8'h8;
    localparam logic [8-1:0] SRAI = (8'h4 << 5) | 8'h8;
    localparam logic [8-1:0] SLLI = (8'h5 << 5) | 8'h8;

    typedef enum logic [3-1:0] {
        InstKind_R = 3'h0,
        InstKind_I = 3'h1,
        InstKind_B = 3'h2,
        InstKind_S = 3'h3,
        InstKind_Nop = 3'h7
    } InstKind;

    InstKind inst_kind; always_comb inst_kind = (((w_instr.opcode) ==? (1)) ? (
        InstKind_R
    ) : ((w_instr.opcode) ==? (2)) ? (
        InstKind_I
    ) : ((w_instr.opcode) ==? (3)) ? (
        (((w_instr.opcode_sub) ==? (0)) ? (
            InstKind_B
        ) : ((w_instr.opcode_sub) ==? (1)) ? (
            InstKind_B
        ) : ((w_instr.opcode_sub) ==? (2)) ? (
            InstKind_B
        ) : ((w_instr.opcode_sub) ==? (3)) ? (
            InstKind_B
        ) : ((w_instr.opcode_sub) ==? (4)) ? (
            InstKind_I
        ) // Jump 系
         : (            InstKind_Nop
        ))
    ) : ((w_instr.opcode) ==? (4)) ? (
        InstKind_I
    ) : ((w_instr.opcode) ==? (5)) ? (
        InstKind_S
    ) : ((w_instr.opcode) ==? (6)) ? (
        (((w_instr.opcode_sub) ==? (0)) ? (
            InstKind_I
        ) : ((w_instr.opcode_sub) ==? (1)) ? (
            InstKind_S
        ) // out
         : (            InstKind_Nop
        ))
    ) : ((w_instr.opcode) ==? (7)) ? (
        InstKind_R
    ) : ((w_instr.opcode) ==? (8)) ? (
        InstKind_I
    ) : (
        InstKind_Nop
    ));

    always_comb w_command = ((({w_instr.opcode_sub, w_instr.opcode}) ==? (ADD)) ? (
        8'h1
    ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (SUB)) ? (
        8'h2
    ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (ADDI)) ? (
        8'h1
    ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (SUBI)) ? (
        8'h2
    ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (BEQ)) ? (
        8'h2
    ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (BNE)) ? (
        8'h2
    ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (BLT)) ? (
        8'h2
    ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (BLE)) ? (
        8'h2
    ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (JAL)) ? (
        8'h1
    ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (LW)) ? (
        8'h1
    ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (LH)) ? (
        8'h1
    ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (LB)) ? (
        8'h1
    ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (LHU)) ? (
        8'h1
    ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (LBU)) ? (
        8'h1
    ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (SW)) ? (
        8'h1
    ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (SH)) ? (
        8'h1
    ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (SB)) ? (
        8'h1
    ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (IN)) ? (
        8'h1
    ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (OUT)) ? (
        8'h1
    ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (AND)) ? (
        8'h3
    ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (OR)) ? (
        8'h4
    ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (XOR)) ? (
        8'h5
    ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (SRL)) ? (
        8'h6
    ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (SRA)) ? (
        8'h7
    ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (SLL)) ? (
        8'h8
    ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (ANDI)) ? (
        8'h3
    ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (ORI)) ? (
        8'h4
    ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (XORI)) ? (
        8'h5
    ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (SRLI)) ? (
        8'h6
    ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (SRAI)) ? (
        8'h7
    ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (SLLI)) ? (
        8'h8
    ) : (
        8'h0
    ));
    always_comb w_a = (((inst_kind) ==? (InstKind_R)) ? (
        m_regfile[w_instr.rs1]
    ) : ((inst_kind) ==? (InstKind_I)) ? (
        m_regfile[w_instr.rs1_i]
    ) : ((inst_kind) ==? (InstKind_B)) ? (
        m_regfile[w_instr.rs1]
    ) : ((inst_kind) ==? (InstKind_S)) ? (
        m_regfile[w_instr.rs1_s]
    ) : (
        0
    ));
    always_comb w_b = (((inst_kind) ==? (InstKind_R)) ? (
        m_regfile[w_instr.rs2]
    ) : ((inst_kind) ==? (InstKind_I)) ? (
        w_instr.imm
    ) : ((inst_kind) ==? (InstKind_B)) ? (
        m_regfile[w_instr.rs2]
    ) : ((inst_kind) ==? (InstKind_S)) ? (
        w_instr.imm
    ) : (
        0
    ));

    veryl_Alu alu (
        .i_command (w_command),
        .i_a       (w_a      ),
        .i_b       (w_b      ),
        .o_zero    (w_zero   ),
        .o_out     (w_out    )
    );

    always_comb begin
        // メモリに書き込むデータを選択
        case (1'b1)
            ({w_instr.opcode_sub, w_instr.opcode}) ==? (SW): w_wen = 4'b1111;
            ({w_instr.opcode_sub, w_instr.opcode}) ==? (SH): w_wen = 4'b0011;
            ({w_instr.opcode_sub, w_instr.opcode}) ==? (SB): w_wen = 4'b0001;
            default                                        : w_wen = 4'b0000;
        endcase

        // ロード命令のとき，read_enable = 1
        case (1'b1)
            ({w_instr.opcode_sub, w_instr.opcode}) ==? (LW), ({w_instr.opcode_sub, w_instr.opcode}) ==? (LH), ({w_instr.opcode_sub, w_instr.opcode}) ==? (LB), ({w_instr.opcode_sub, w_instr.opcode}) ==? (LHU), ({w_instr.opcode_sub, w_instr.opcode}) ==? (LBU): w_ren = 1'b1;
            default                                                                                                                                                                                                                                              : w_ren = 1'b0;
        endcase
    end

    // 同期読み出しの完了を示すフラグ
    always_ff @ (posedge i_clk) begin
        if (i_rst) begin
            r_load_ready <= 0;
        end else begin
            // 初期状態: r_load_ready = 0
            case (1'b1)
                ({w_instr.opcode_sub, w_instr.opcode}) ==? (LW), ({w_instr.opcode_sub, w_instr.opcode}) ==? (LH), ({w_instr.opcode_sub, w_instr.opcode}) ==? (LB), ({w_instr.opcode_sub, w_instr.opcode}) ==? (LHU), ({w_instr.opcode_sub, w_instr.opcode}) ==? (LBU): begin
                                                                                                                                                                                                                                                                           // 1. ロード命令 && r_load_ready = 0
                                                                                                                                                                                                                                                                           if (!r_load_ready) begin
                                                                                                                                                                                                                                                                               r_load_ready <= 1;
                                                                                                                                                                                                                                                                               // 2. ロード命令 && r_load_ready = 1 -> 読み出し完了，初期状態に戻す
                                                                                                                                                                                                                                                                           end else begin
                                                                                                                                                                                                                                                                               r_load_ready <= 0;
                                                                                                                                                                                                                                                                           end
                                                                                                                                                                                                                                                                       end
                default: r_load_ready <= 0;
            endcase
        end
    end

    // デバイス読み書き
    always_comb begin
        i_dev_id = w_out;

        if_io_bus_din.ready = {w_instr.opcode_sub, w_instr.opcode} == IN;

        if_io_bus_dout.valid = {w_instr.opcode_sub, w_instr.opcode} == OUT;
        if_io_bus_dout.bits  = m_regfile[w_instr.rs2_s];
    end

    // 分岐判定
    always_comb begin
        w_branch_taken = ((({w_instr.opcode_sub, w_instr.opcode}) ==? (BEQ)) ? (
            w_zero
        ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (BNE)) ? (
            !w_zero
        ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (BLT)) ? (
            w_out[31]
        ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (BLE)) ? (
            w_out[31] || w_zero
        ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (JAL)) ? (
            1'h1
        ) : (
            1'h0
        ));
    end

    // レジスタアクセス
    always_ff @ (posedge i_clk) begin
        if (i_rst) begin
            for (int unsigned i = 0; i < 32; i++) begin
                m_regfile[i] <= 32'h0;
            end
        end else if (w_instr.rd != 0) begin
            m_regfile[w_instr.rd] <= ((({w_instr.opcode_sub, w_instr.opcode}) ==? (BEQ)) ? (
                r_pc_fetched + 32'h6
            ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (BNE)) ? (
                r_pc_fetched + 32'h6
            ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (BLT)) ? (
                r_pc_fetched + 32'h6
            ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (BLE)) ? (
                r_pc_fetched + 32'h6
            ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (JAL)) ? (
                r_pc_fetched + 32'h6
            ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (LW)) ? (
                w_dmem_read
            ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (LH)) ? (
                {{16{w_dmem_read[15]}}, w_dmem_read[0+:16]}
            ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (LHU)) ? (
                {16'b0, w_dmem_read[0+:16]}
            ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (LB)) ? (
                {{24{w_dmem_read[7]}}, w_dmem_read[0+:8]}
            ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (LBU)) ? (
                {24'b0, w_dmem_read[0+:8]}
            ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (SW)) ? (
                m_regfile[w_instr.rd]
            ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (SH)) ? (
                m_regfile[w_instr.rd]
            ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (SB)) ? (
                m_regfile[w_instr.rd]
            ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (IN)) ? (
                ((if_io_bus_din.valid) ? ( if_io_bus_din.bits ) : ( m_regfile[w_instr.rd] ))
            ) : (({w_instr.opcode_sub, w_instr.opcode}) ==? (OUT)) ? (
                m_regfile[w_instr.rd]
            ) : (
                w_out
            ));
        end
    end
endmodule
//# sourceMappingURL=Core.sv.map
