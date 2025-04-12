interface veryl_Decoupled #(
    parameter int unsigned Width = 32
);
    logic [1-1:0]     valid;
    logic [1-1:0]     ready;
    logic [Width-1:0] bits ;

    modport sender (
        output valid,
        input  ready,
        output bits 
    );

    modport receiver (
        input  valid,
        output ready,
        input  bits 
    );
endinterface
//# sourceMappingURL=Decoupled.sv.map
