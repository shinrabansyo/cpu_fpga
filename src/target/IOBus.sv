module veryl_IOBus #(
    parameter int unsigned ClockFrequency = 15_000_000, // default 15Mhz
    parameter int unsigned UartBaudRate   = 115200     // default 115200bps
) (
    // クロック・リセット
    input logic i_clk,
    input logic i_rst,

    // デバイス制御
    input logic                    [32-1:0] i_dev_id,
    veryl_Decoupled.receiver          if_din  ,
    veryl_Decoupled.sender            if_dout ,

    // UART
    output logic [1-1:0] o_tx,
    input  logic [1-1:0] i_rx,

    // SPI
    // o_sclk: output logic<1>,
    // o_mosi: output logic<1>,
    // i_miso: input  logic<1>,

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
    // UART
    veryl_Decoupled #(.Width (8)) if_uart_tx      ();
    veryl_Decoupled #(.Width (8)) if_uart_rx      ();
    logic [1-1:0] uart_rx_overrun;

    veryl_UartTx #(
        .ClockFrequency (ClockFrequency),
        .BaudRate       (UartBaudRate  )
    ) uart_tx (
        .i_clk  (i_clk     ),
        .i_rst  (i_rst     ),
        .o_tx   (o_tx      ),
        .if_din (if_uart_tx)
    );

    veryl_UartRx #(
        .ClockFrequency (ClockFrequency),
        .BaudRate       (UartBaudRate  ),
        .RxSyncStages   (2             )
    ) uart_rx (
        .i_clk     (i_clk          ),
        .i_rst     (i_rst          ),
        .if_dout   (if_uart_rx     ),
        .i_rx      (i_rx           ),
        .o_overrun (uart_rx_overrun)
    );

    // GPIO
    veryl_Decoupled #(.Width (8)) if_gpout_read  ();
    veryl_Decoupled #(.Width (8)) if_gpout_write ();

    veryl_GeneralPurposeOutput gpout (
        .i_clk   (i_clk         ),
        .i_rst   (i_rst         ),
        .if_din  (if_gpout_write),
        .if_dout (if_gpout_read ),
        .o_gpout (o_gpout       )
    );

    // Counter
    logic [64-1:0] clk_count;
    logic [32-1:0] clk_freq ;
    logic [64-1:0] ms_count ;
    veryl_ClkCounter #(
        .ClockFrequency (ClockFrequency)
    ) counter (
        .i_clk       (i_clk    ),
        .i_rst       (i_rst    ),
        .o_clk_count (clk_count),
        .o_clk_freq  (clk_freq ),
        .o_ms_count  (ms_count )
    );

    // HDMI
    localparam int unsigned HDMI_BASE          = 32'h10000000;
    localparam int unsigned HDMI_LENGTH        = 32'h1000000;
    localparam int unsigned HDMI_VRAM_ADR_BITS = $clog2((128 * 128 + 1) >> 1);
    // inst if_col_mode_din   : Decoupled #(Width: 8,);
    veryl_Decoupled #(.Width (32)) if_col_table_din ();
    veryl_Decoupled #(.Width (8)) if_vdata_in      ();
    // inst if_vdata_out      : Decoupled #(Width: 32,);
    logic [HDMI_VRAM_ADR_BITS-1:0] i_vdata_adr; always_comb i_vdata_adr = HDMI_VRAM_ADR_BITS'((i_dev_id - HDMI_BASE));
    veryl_VideoControllerColTable vc (
        .i_clk (i_clk),
        .i_rst (i_rst),
        // if_col_mode_din   ,
        .if_col_table_din (if_col_table_din),
        .if_vdata_in      (if_vdata_in     ),
        // if_vdata_out      ,
        .i_vdata_adr (i_vdata_adr),
        .
        i_clk_dvi (i_clk_dvi),
        .i_rst_dvi (i_rst_dvi),
        .o_vsync   (o_vsync  ),
        .o_hsync   (o_hsync  ),
        .o_de      (o_de     ),
        .o_data    (o_data   )
    );

    // デバイス選択
    logic [1-1:0] is_in_instr      ; always_comb is_in_instr       = if_dout.ready;
    logic [1-1:0] is_out_instr     ; always_comb is_out_instr      = if_din.valid;
    logic [1-1:0] is_inout_instr   ; always_comb is_inout_instr    = is_in_instr | is_out_instr;
    logic [1-1:0] is_uart          ; always_comb is_uart           = is_inout_instr & (i_dev_id == 32'h0000);
    logic [1-1:0] is_gpout         ; always_comb is_gpout          = is_inout_instr & (i_dev_id == 32'h0004);
    logic [1-1:0] is_hdmi_col_mode ; always_comb is_hdmi_col_mode  = is_out_instr & (i_dev_id == 32'h0006);
    logic [1-1:0] is_hdmi_col_table; always_comb is_hdmi_col_table = is_out_instr & (i_dev_id == 32'h0007);
    logic [1-1:0] is_clk_count_l   ; always_comb is_clk_count_l    = is_in_instr & (i_dev_id == 32'h1000);
    logic [1-1:0] is_clk_count_h   ; always_comb is_clk_count_h    = is_in_instr & (i_dev_id == 32'h1001);
    logic [1-1:0] is_clk_freq      ; always_comb is_clk_freq       = is_in_instr & (i_dev_id == 32'h1002);
    logic [1-1:0] is_ms_count_l    ; always_comb is_ms_count_l     = is_in_instr & (i_dev_id == 32'h1003);
    logic [1-1:0] is_ms_count_h    ; always_comb is_ms_count_h     = is_in_instr & (i_dev_id == 32'h1004);
    logic [1-1:0] is_hdmi_vram     ; always_comb is_hdmi_vram      = is_inout_instr & (HDMI_BASE <= i_dev_id & i_dev_id < HDMI_BASE + HDMI_LENGTH);

    // デバイス間接続
    always_comb if_uart_tx.valid = is_uart & if_din.valid;
    always_comb if_uart_tx.bits  = if_din.bits[7:0];
    always_comb if_uart_rx.ready = is_uart & if_dout.ready;

    always_comb if_gpout_write.valid = is_gpout & if_din.valid;
    always_comb if_gpout_write.bits  = if_din.bits[7:0];
    always_comb if_gpout_read.ready  = is_gpout & if_dout.ready;

    always_comb if_col_table_din.valid = is_hdmi_col_table & if_din.valid;
    always_comb if_col_table_din.bits  = if_din.bits;
    always_comb if_vdata_in.valid      = is_hdmi_vram & if_din.valid;
    always_comb if_vdata_in.bits       = if_din.bits[7:0];
    // assign if_vdata_out.ready     = is_hdmi_vram & if_dout.ready;

    always_comb begin
        if (is_uart) begin
            if_din.ready  = is_out_instr & if_uart_tx.ready;
            if_dout.valid = is_in_instr & if_uart_rx.valid;
            if_dout.bits  = {24'b0, if_uart_rx.bits};
        end else if (is_gpout) begin
            if_din.ready  = is_out_instr & if_gpout_write.ready;
            if_dout.valid = is_in_instr & if_gpout_read.valid;
            if_dout.bits  = {24'b0, if_gpout_read.bits};
        end else if (is_hdmi_col_mode) begin
            // if_din.ready  = is_out_instr & if_col_table_din.ready;
            if_din.ready  = 1; // 16色モード固定
            if_dout.valid = 0;
            if_dout.bits  = 0;
        end else if (is_hdmi_col_table) begin
            if_din.ready  = is_out_instr & if_col_table_din.ready;
            if_dout.valid = 0;
            if_dout.bits  = 0;
        end else if (is_clk_count_l) begin
            if_din.ready  = 0;
            if_dout.bits  = clk_count[31:0];
            if_dout.valid = 1;
        end else if (is_clk_count_h) begin
            if_din.ready  = 0;
            if_dout.bits  = clk_count[63:32];
            if_dout.valid = 1;
        end else if (is_clk_freq) begin
            if_din.ready  = 0;
            if_dout.bits  = clk_freq;
            if_dout.valid = 1;
        end else if (is_ms_count_l) begin
            if_din.ready  = 0;
            if_dout.bits  = ms_count[31:0];
            if_dout.valid = 1;
        end else if (is_ms_count_h) begin
            if_din.ready  = 0;
            if_dout.bits  = ms_count[63:32];
            if_dout.valid = 1;
        end else if (is_hdmi_vram) begin
            if_din.ready = is_out_instr & if_vdata_in.ready;
            // if_dout.valid = is_in_instr & if_vdata_out.valid;
            if_dout.valid = 1;
            if_dout.bits  = 32'hdeadbeef;
            // if_dout.bits  = if_vdata_out.bits;
        end else begin
            if_din.ready  = 0;
            if_dout.valid = 0;
            if_dout.bits  = 0;
        end
    end
endmodule
//# sourceMappingURL=IOBus.sv.map
