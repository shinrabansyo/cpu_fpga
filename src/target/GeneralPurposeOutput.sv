module veryl_GeneralPurposeOutput (
    input var logic i_clk,
    input var logic i_rst,

    veryl_Decoupled.receiver         if_din ,
    veryl_Decoupled.sender           if_dout,
    output var logic                [8-1:0] o_gpout
);
    logic [8-1:0] r_pin_out;

    always_comb if_din.ready  = 1;
    always_comb if_dout.valid = 1;
    always_comb if_dout.bits  = r_pin_out;
    always_comb o_gpout       = r_pin_out;

    always_ff @ (posedge i_clk) begin
        if (i_rst) begin
            r_pin_out <= 0;
        end else begin
            if (if_din.valid) begin
                r_pin_out <= if_din.bits;
            end
        end
    end
endmodule
//# sourceMappingURL=GeneralPurposeOutput.sv.map
