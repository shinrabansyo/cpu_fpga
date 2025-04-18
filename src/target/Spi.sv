/*
module Spi #(
    param CLK_FREQ: u32,
) (
    i_clk: clock,
    i_rst: reset,

    o_mosi: logic,
    i_miso: logic,
    o_sclk: logic,

    if_din: Decoupled::receiver, // 任意のデータを送るとき
    if_dout: Decoupled::sender, // データを読み取るとき

    if_clkshamt: Decoupled::receiver, // シフト量(shift amout) + 1
    o_clkshamt: logic<3>,

    if_spi_mode: Decoupled::receiver, // SPIモード
    o_spi_mode: logic<2>,
    // SCLK クロックの速度 = CLK_FREQ >> (clkshamt + 1)
) {
    // クロックの分周用信号
    var r_sclk: logic;
    var r_sclk_counter: logic<9>;
    var r_clkshamt: logic<3>;
    var w_posedge: logic;
    var w_negedge: logic;


    // データの送受信用信号
    var r_shift_reg: logic<8>;
    var r_bit_counter: logic<4>;
    var r_busy: logic;
    var r_miso_buf: logic,
    var r_spi_mode_ready: logic;
    var r_clkshamnt_ready: logic;
    var r_out_valid: logic;
    var r_cpol: logic; // アイドル状態でのクロックのHIGH/LOW (clocl polarity)
    var r_cpha: logic; // サンプリングの極性 posedge/negedge (clock phase)
    var w_mode_1_2: logic;
    var r_is_first_sclk: logic;

    assign o_clkshamt = r_clkshamt;
    assign o_spi_mode = {r_cpol, r_cpha};

    // クロックの分周
    assign o_sclk = r_sclk;

    always_comb {
        if busy && r_sclk_counter == 0 {
            posedge = ~r_sclk;
            negedge = r_sclk;
        } else {
            posedge = 0;
            negedge = 0;
        }
    }

    always_ff {
        if_reset {
            r_sclk = 0;
            r_sclk_counter = 0;
            r_clkshamt = 0;

            r_is_first_sclk = 1;
        } else {
            if r_busy {
                if r_sclk_counter == 0 {
                    r_is_first_sclk = 0;
                    r_sclk_counter = (1 >> r_clkshamt) - 1;
                    if !(r_bit_counter == 1 && r_sclk == r_cpol && r_cpha) {
                        r_sclk = ~r_sclk;
                    }
                } else {
                    r_sclk_counter -= 1;
                }
            } else if !(if_spi_mode.valid && if_spi_mode.ready) {
                r_sclk = cpol;
            }
        }
    }

    // データの送受信
    // mode 0: cpol = 0, cpha = 0 (データをposedgeでサンプリング / negedgeでシフト)
    // mode 1: cpol = 0, cpha = 1 (データをnegedgeでサンプリング / posedgeでシフト)
    // mode 2: cpol = 1, cpha = 0 (データをnegedgeでサンプリング / posedgeでシフト)
    // mode 3: cpol = 1, cpha = 1 (データをposedgeでサンプリング / negedgeでシフト)
    assign w_mode_1_2 = r_cpol ^ r_cpha;
    assign if_din.ready = if_din.valid && r_busy && r_bit_counter == 0;

    always_ff {
        if_reset {
            r_sclk: logic;
            r_sclk_counter: logic<9>;
            r_clkshamt: logic<3>;

            r_shift_reg: logic<8>;
            r_bit_counter: logic<4>;
            r_busy: logic;
            r_miso_buf: logic,
            r_spi_mode_ready: logic;
            r_clkshamnt_ready: logic;
            r_out_valid: logic;
            r_cpol: logic; // アイドル状態でのクロックのHIGH/LOW (clocl polarity)
            r_cpha: logic; // サンプリングの極性 posedge/negedge (clock phase)
            r_is_first_sclk: logic;
        } else {
            if if_din.valid && !r_busy {
                r_shift_reg = if_din.bits;
                r_busy = 1;
                r_bit_counter = 8;

                if 
            }
        }
    }
}

*/

//# sourceMappingURL=Spi.sv.map
