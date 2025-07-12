module veryl_UartTx #(
    parameter int unsigned ClockFrequency = 15_000_000, // default 15 MHz
    parameter int unsigned BaudRate       = 115200     // default 115200 bps
) (
    input var logic i_clk,
    input var logic i_rst,

    output var logic                [1-1:0] o_tx  ,
    veryl_Decoupled.receiver         if_din
);
    localparam int unsigned BAUD_DIVIDER = (ClockFrequency / BaudRate) - 1;

    logic [$clog2(BAUD_DIVIDER + 1)-1:0] r_rate_counter;
    logic [$clog2(8 + 2)-1:0]            r_bit_counter ;
    logic [8 + 2-1:0]                    r_bits        ;

    logic [1-1:0] w_ready     ; always_comb w_ready      = r_bit_counter == 0;
    always_comb o_tx         = w_ready | r_bits[0];
    always_comb if_din.ready = w_ready;

    always_ff @ (posedge i_clk) begin
        if (i_rst) begin
            r_rate_counter <= 0;
            r_bit_counter  <= 0;
            r_bits         <= '1;
        end else begin
            if ((w_ready && if_din.valid)) begin // 送信開始
                r_bits         <= {1'b1, if_din.bits, 1'b0};
                r_bit_counter  <= 8 + 2;
                r_rate_counter <= BAUD_DIVIDER[$bits(r_rate_counter) - 1:0];
            end else if (r_bit_counter > 0) begin // 送信中
                if ((r_rate_counter == 0)) begin
                    r_bits[8:0]    <= r_bits[9:1];
                    r_bit_counter  <= r_bit_counter  - (1);
                    r_rate_counter <= BAUD_DIVIDER[$bits(r_rate_counter) - 1:0];
                end else begin
                    r_rate_counter <= r_rate_counter - (1);
                end
            end
        end
    end
endmodule

module veryl_UartRx #(
    parameter int unsigned ClockFrequency = 15_000_000, // default 15 MHz
    parameter int unsigned BaudRate       = 115200    , // default 115200 bps
    parameter int unsigned RxSyncStages   = 2          // default 2 stages
) (
    input var logic i_clk,
    input var logic i_rst,

    veryl_Decoupled.sender         if_dout  , // 受信データをCPUに出力
    input  var logic              [1-1:0] i_rx     , // UART信号入力
    output var logic              [1-1:0] o_overrun // UARTデータ取りこぼし発生？
);
    localparam int unsigned BAUD_DIVIDER                = ClockFrequency / BaudRate;
    localparam int unsigned BAUD_DIVIDER_TIMES_3_OVER_2 = BAUD_DIVIDER * 3 / 2;

    logic [$clog2(BAUD_DIVIDER_TIMES_3_OVER_2)-1:0] r_rate_counter; // P.103 a～cを測るため 1.5倍
    logic [$clog2(8 + 2)-1:0]                       r_bit_counter ;
    logic [8 + 2-1:0]                               r_bits        ; // UARTから受け取るデータを入れる箱
    logic [RxSyncStages + 1-1:0]                    r_rx_regs     ; // RxSyncStages : 同期に使うフリップフロップ回路の個数
    logic [1-1:0]                                   r_overrun     ; // CPU側に送信中にUART相手から受信させられそうな時のフラグ
    logic [1-1:0]                                   r_running     ; // 受信中のフラグ

    // 受信データの出力信号
    logic [1-1:0] r_out_valid  ;
    logic [8-1:0] r_out_bits   ;
    logic [1-1:0] w_out_ready  ; always_comb w_out_ready   = if_dout.ready;
    always_comb if_dout.valid = r_out_valid;
    always_comb if_dout.bits  = r_out_bits;

    always_comb o_overrun = r_overrun;

    always_ff @ (posedge i_clk) begin
        if (i_rst) begin
            r_rate_counter <= 0;
            r_bit_counter  <= 0;
            r_bits         <= 0;
            r_rx_regs      <= 0;
            r_overrun      <= 0;
            r_running      <= 0;
            r_out_valid    <= 0;
            r_out_bits     <= 0;
        end else begin
            // CPU とのハンドシェイク
            if (r_out_valid && w_out_ready) begin
                r_out_valid <= 0;
            end

            // RX信号をクロックに同期
            //    10kHz
            // 生のrx:   1 1 01 1  1   1   1 1  1 0 0   0  0
            //         ~~~~~~~~~~~~~~~~~~~~~~~~~~~____________
            //    cpu:   |  |  |  |  |  |  |  |  |  |  |  |  |
            //         ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~________________________~~~~~~~~
            //  sample                              *            *
            //         ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~________________________~~~~~~~
            //    10MHz
            // ↓の信号:  1  1  1  1  1  1  1  1  1  0  0  0  0
            r_rx_regs[RxSyncStages]       <= i_rx;
            r_rx_regs[RxSyncStages - 1:0] <= r_rx_regs[RxSyncStages:1];
            // 相手は相手自身のクロックに合わせて送信してくるけど、自分側のクロックとそのクロックは
            // 同期していないので合わせる必要がある
            // UARTからの入力 => [ r_rx_regs ] => 受信
            //                       ↑ こいつを挟んで同期してる

            // UART受信処理
            // 受信中じゃないとき
            if (!r_running) begin
                if (!r_rx_regs[1] && r_rx_regs[0]) begin // aの検出をしたとき
                    // スタートビット検出(立ち下がり検出)、rxRegs(0)が1(平常電位)、rxRegs(1)がゼロ(start信号)
                    r_rate_counter <= BAUD_DIVIDER_TIMES_3_OVER_2[$bits(r_rate_counter) - 1:0] - 1; // Wait until the center of LSB.
                    r_bit_counter  <= 8 + 2 - 1;
                    r_running      <= 1; // 舌の処理にcの時移る
                end
            end else begin
                if (r_rate_counter == 0) begin // 1ビット周期ごとに処理
                    r_bits[8 + 2 - 1] <= r_rx_regs[0]; // つぎのビットを出力
                    r_bits[8:0]       <= r_bits[9:1]; // 1ビット右シフト

                    if (r_bit_counter == 0) begin // ストップビットまで受信したら
                        r_out_valid <= 1; // データ受信完了->CPUが読み取れる状態になる
                        r_out_bits  <= r_bits[8:1];
                        r_overrun   <= r_out_valid; // 前のデータが処理される前に次のデータの受信が完了した
                        // 上のr_out_valid = 1 と同時に入れられるので，普段はr_overrunには0が入るが
                        // やるべきタスクが終わっていない(r_out_valid = 0)がされていない状態で来ると
                        // r_overrun が 1 になる
                        r_running <= 0;
                    end else begin
                        r_rate_counter <= BAUD_DIVIDER[$bits(r_rate_counter) - 1:0] - 1;
                        r_bit_counter  <= r_bit_counter  - (1);
                    end
                end else begin
                    r_rate_counter <= r_rate_counter - (1);
                end
            end
        end
    end
endmodule
//# sourceMappingURL=Uart.sv.map
