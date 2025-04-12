module veryl_ClkCounter #(
    parameter int unsigned ClockFrequency = 15_000_000 // default 15 MHz
) (
    input logic i_clk,
    input logic i_rst,

    // クロック関連
    output logic [64-1:0] o_clk_count,
    output logic [32-1:0] o_clk_freq ,

    // タイマー関連
    output logic [64-1:0] o_ms_count
);
    logic [64-1:0] r_counter;

    logic [64-1:0] r_ms_count  ;
    logic [32-1:0] r_ms_counter;

    localparam int unsigned MS_THRESHOLD = ClockFrequency / 1000;

    always_comb o_clk_count = r_counter;
    always_comb o_clk_freq  = ClockFrequency;
    always_comb o_ms_count  = r_ms_count;

    always_ff @ (posedge i_clk) begin
        if (i_rst) begin
            r_counter    <= 0;
            r_ms_count   <= 0;
            r_ms_counter <= 0;
        end else begin
            r_counter <= r_counter + (1);

            if (r_ms_counter >= MS_THRESHOLD) begin
                r_ms_counter <= 0;
                r_ms_count   <= r_ms_count   + (1);
            end else begin
                r_ms_counter <= r_ms_counter + (1);
            end
        end
    end
endmodule
//# sourceMappingURL=ClkCounter.sv.map
