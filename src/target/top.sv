`ifdef __veryl_test_veryl_test1__
    `ifdef __veryl_wavedump_veryl_test1__
        module __veryl_wavedump;
            initial begin
                $dumpfile("test1.vcd");
                $dumpvars();
            end
        endmodule
    `endif

    module top();
        logic i_clk;
        logic i_rst;
        logic o_tx;
        logic i_rx;
        logic o_sclk;
        logic o_mosi;
        logic i_miso;
        logic [7:0] o_gpout;

        logic i_clk_dvi;
        logic i_rst_dvi;
        logic o_vsync;
        logic o_hsync;
        logic o_de;
        logic [23:0] o_data;

        veryl_Core core(.*);

        initial begin
            /* verilator lint_off INITIALDLY */
            i_clk_dvi <= 0;
            i_rst_dvi <= 1;

            @(posedge i_clk_dvi);
            @(posedge i_clk_dvi);
            @(posedge i_clk_dvi)
            i_rst_dvi <= 0;

            repeat (32'h40000) @(posedge i_clk_dvi);
            $finish;
            /* verilator lint_on INITIALDLY */
        end

        initial begin
            $dumpfile("wave.vcd");
            $dumpvars(0);

            // initial 内部でのノンブロッキング代入を許可
            /* verilator lint_off INITIALDLY */
            i_clk <= 0;
            i_rst <= 1;
            i_rx <= 1;
            i_miso <= 0;

            @(posedge i_clk);
            @(posedge i_clk);
            @(posedge i_clk)
            i_rst <= 0;
            /* verilator lint_on INITIALDLY */
            @(posedge i_clk);

            // UART RX に 0x42 ('B') を送信
            #1000 i_rx = 0;
            #1000 i_rx = 0;
            #1000 i_rx = 1;
            #1000 i_rx = 0;
            #1000 i_rx = 0;
            #1000 i_rx = 0;
            #1000 i_rx = 0;
            #1000 i_rx = 1;
            #1000 i_rx = 0;
            #1000 i_rx = 1;
            repeat(1000) @(posedge i_clk);
            // $finish;
        end

        always #(2) begin
            i_clk <= ~i_clk;
        end

        always #(3) begin
            i_clk_dvi <= ~i_clk_dvi;
        end

    endmodule
`endif
//# sourceMappingURL=top.sv.map
