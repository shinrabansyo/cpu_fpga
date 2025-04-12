module veryl_Alu (
    input  logic [8-1:0]  i_command,
    input  logic [32-1:0] i_a      ,
    input  logic [32-1:0] i_b      ,
    output logic [1-1:0]  o_zero   ,
    output logic [32-1:0] o_out
);
    // 算術右シフト
    logic signed [32-1:0] i_a_signed; always_comb i_a_signed = i_a;
    logic signed [32-1:0] i_b_signed; always_comb i_b_signed = i_b;
    logic signed [32-1:0] o_sra_out ; always_comb o_sra_out  = i_a_signed >>> i_b_signed[4:0];

    // ゼロフラグ
    always_comb o_zero = (o_out == 32'b0);

    // 計算
    always_comb o_out = (((i_command) ==? (8'h1)) ? (
        i_a + i_b
    ) : ((i_command) ==? (8'h2)) ? (
        i_a - i_b
    ) : ((i_command) ==? (8'h3)) ? (
        i_a & i_b
    ) : ((i_command) ==? (8'h4)) ? (
        i_a | i_b
    ) : ((i_command) ==? (8'h5)) ? (
        i_a ^ i_b
    ) : ((i_command) ==? (8'h6)) ? (
        i_a >> i_b[4:0]
    ) : ((i_command) ==? (8'h7)) ? (
        o_sra_out
    ) : ((i_command) ==? (8'h8)) ? (
        i_a << i_b[4:0]
    ) : (
        32'b0
    ));
endmodule
//# sourceMappingURL=Alu.sv.map
