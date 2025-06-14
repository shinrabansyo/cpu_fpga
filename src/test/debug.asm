===

@func_main
    out r0[2] = r0  // mode 0
    addi r4 = r0, 4
    out r0[3] = r4  // clkshamt 4

    addi r4 = r0, 0x12
    out r0[1] = r4 // spi data
    out r0[1] = r4 // spi data
    out r0[1] = r4 // spi data
    out r0[1] = r4 // spi data

    addi r4 = r0, 0x34
    out r0[0] = r4 // uart tx
    out r0[0] = r4 // uart tx
    out r0[0] = r4 // uart tx
    out r0[0] = r4 // uart tx

@inf_loop
    beq r0, (r0, r0) -> @inf_loop
