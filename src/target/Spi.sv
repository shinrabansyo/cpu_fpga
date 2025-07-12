module veryl_Spi #(
    parameter int unsigned ClockFrequency = 15_000_000
) (
    input var logic i_clk,
    input var logic i_rst,

    output var logic o_mosi,
    input  var logic i_miso,
    output var logic o_sclk,

    veryl_Decoupled.receiver if_din , // 任意のデータを送るとき
    veryl_Decoupled.sender   if_dout, // データを読み取るとき

    veryl_Decoupled.receiver         if_clkshamt, // シフト量(shift amout) + 1
    output var logic                [3-1:0] o_clkshamt ,

    veryl_Decoupled.receiver         if_spi_mode, // SPIモード
    output var logic                [2-1:0] o_spi_mode 
    // SCLK クロックの速度 = ClockFrequency >> (clkshamt + 1)
);
    // クロックの分周用信号
    logic         r_sclk        ;
    logic [9-1:0] r_sclk_counter;
    logic [3-1:0] r_clkshamt    ;
    logic         w_posedge     ;
    logic         w_negedge     ;


    // データの送受信用信号
    logic [8-1:0] r_shift_reg     ;
    logic [4-1:0] r_bit_counter   ;
    logic         r_busy          ;
    logic         r_miso_buf      ;
    logic         r_spi_mode_ready;
    logic         r_clkshamt_ready;
    logic         r_out_valid     ;
    logic         r_cpol          ; // アイドル状態でのクロックのHIGH/LOW (clocl polarity)
    logic         r_cpha          ; // サンプリングの極性 posedge/negedge (clock phase)
    logic         w_mode_1_2      ;
    logic         r_is_first_sclk ;

    always_comb o_clkshamt = r_clkshamt;
    always_comb o_spi_mode = {r_cpol, r_cpha};

    // クロックの分周
    always_comb o_sclk = r_sclk;

    always_comb begin
        if (r_busy && r_sclk_counter == 0) begin
            w_posedge = ~r_sclk;
            w_negedge = r_sclk;
        end else begin
            w_posedge = 0;
            w_negedge = 0;
        end
    end

    always_ff @ (posedge i_clk) begin
        if (i_rst) begin
            r_sclk          <= 0;
            r_sclk_counter  <= 0;
            r_is_first_sclk <= 1;
        end else if (r_busy) begin
            if (r_sclk_counter == 0) begin
                r_is_first_sclk <= 0;
                r_sclk_counter  <= (1 >> r_clkshamt) - 1;
                if (!(r_bit_counter == 1 && r_sclk == r_cpol && r_cpha)) begin
                    r_sclk <= ~r_sclk;
                end
            end else begin
                r_sclk_counter <= r_sclk_counter - (1);
            end
        end else begin
            // din と clkshamt が同じクロックで設定された場合への対処
            if (if_din.valid && if_clkshamt.valid && if_clkshamt.ready) begin
                r_sclk_counter <= (1 << (if_clkshamt.bits + 1)) - 1;
            end else begin
                r_sclk_counter <= (1 << (r_clkshamt + 1)) - 1;
            end

            if (if_spi_mode.valid && if_spi_mode.ready) begin
                r_sclk <= if_spi_mode.bits[1];
            end else begin
                r_sclk <= r_cpol;
            end
        end
    end

    // CPU 読み取りデータの準備
    always_comb if_dout.bits  = r_shift_reg;
    always_comb if_dout.valid = r_out_valid;

    always_ff @ (posedge i_clk) begin
        if (i_rst) begin
            r_out_valid <= 0;
        end else if (r_busy && r_bit_counter == 0) begin
            r_out_valid <= 1;
        end else if (if_dout.valid && if_dout.ready) begin
            r_out_valid <= 0;
        end
    end

    // clkShamt の準備
    always_comb if_clkshamt.ready = r_clkshamt_ready;

    always_ff @ (posedge i_clk) begin
        if (i_rst) begin
            r_clkshamt_ready <= 1;
            r_clkshamt       <= 0;
        end else if (r_busy && r_bit_counter == 0) begin
            r_clkshamt_ready <= 1;
        end else if (if_clkshamt.valid && if_clkshamt.ready) begin
            r_clkshamt_ready <= 0;
            r_clkshamt       <= if_clkshamt.bits;
        end
    end

    // spiMode の準備
    // mode 0: cpol = 0, cpha = 0 (データをposedgeでサンプリング / negedgeでシフト)
    // mode 1: cpol = 0, cpha = 1 (データをnegedgeでサンプリング / posedgeでシフト)
    // mode 2: cpol = 1, cpha = 0 (データをnegedgeでサンプリング / posedgeでシフト)
    // mode 3: cpol = 1, cpha = 1 (データをposedgeでサンプリング / negedgeでシフト)
    always_comb w_mode_1_2        = r_cpol ^ r_cpha;
    always_comb if_spi_mode.ready = r_spi_mode_ready;

    always_ff @ (posedge i_clk) begin
        if (i_rst) begin
            r_cpol           <= 0;
            r_cpha           <= 0;
            r_spi_mode_ready <= 1;
        end else if (r_busy && r_bit_counter == 0) begin
            r_spi_mode_ready <= 1;
        end else if (if_spi_mode.valid && if_spi_mode.ready) begin
            r_cpol           <= if_spi_mode.bits[1];
            r_cpha           <= if_spi_mode.bits[0];
            r_spi_mode_ready <= 0;
        end
    end

    // 送受信処理
    always_comb if_din.ready = if_din.valid && r_busy && r_bit_counter == 0;
    always_comb o_mosi       = r_shift_reg[7];

    always_ff @ (posedge i_clk) begin
        if (i_rst) begin
            r_shift_reg   <= 0;
            r_busy        <= 0;
            r_bit_counter <= 0;
            r_miso_buf    <= 0;
        end else if (r_busy && r_bit_counter == 0) begin
            r_busy <= 0;
        end else if (!r_busy && if_din.valid) begin // 送信開始処理
            r_shift_reg   <= if_din.bits;
            r_busy        <= 1;
            r_bit_counter <= 8;
        end else if (r_busy && r_bit_counter != 0) begin // 送受信処理の本体
            if (w_mode_1_2) begin
                // posedge かつ mode 1 の最初のクロックでない場合
                if (w_posedge && !(r_cpha && r_is_first_sclk)) begin
                    // シフト
                    r_shift_reg   <= {r_shift_reg[6:0], r_miso_buf};
                    r_bit_counter <= r_bit_counter - 1;
                end
                if (w_negedge) begin
                    // サンプリング
                    r_miso_buf <= i_miso;
                end
            end else begin
                if (w_negedge && !(r_cpol && r_is_first_sclk)) begin
                    // シフト
                    r_shift_reg   <= {r_shift_reg[6:0], r_miso_buf};
                    r_bit_counter <= r_bit_counter - 1;
                end
                if (w_posedge) begin
                    // サンプリング
                    r_miso_buf <= i_miso;
                end
            end
        end
    end
endmodule
//# sourceMappingURL=Spi.sv.map
