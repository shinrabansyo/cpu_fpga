module Top(
    input logic i_clk_27MHz,
    input logic i_rst,

    // UART
    output logic [1-1:0] o_tx_pin,
    output logic [1-1:0] o_tx,
    input  logic [1-1:0] i_rx,

    // SPI
    output logic [1-1:0] o_sclk,
    output logic [1-1:0] o_mosi,
    input  logic [1-1:0] i_miso,

    // GPIO
    output logic [8-1:0] o_gpout,

    // HDMI
    output wire			TMDS_CLOCK,		// LVCMOS33D
	output wire			TMDS_DATA0,		// LVCMOS33D
	output wire			TMDS_DATA1,		// LVCMOS33D
	output wire			TMDS_DATA2 		// LVCMOS33D
);
    assign o_tx_pin = o_tx;
    logic i_clk;
    logic i_clk_dvi;
    logic i_rst_dvi;
    logic o_vsync;
    logic o_hsync;
    logic o_de;
    logic [23:0] o_data;

    assign i_rst_dvi = !i_rst;
    
    cpu_rpll cpu_clk_gen(
        .clkout(i_clk), //output clkout
        .clkin(i_clk_27MHz) //input clkin
    );
    dvi_clkdiv dvi_clk_gen(
        .clkout(i_clk_dvi), //output clkout
        .hclkin(w_clk_dvi_x5), //input hclkin
        .resetn(i_rst) //input resetn
    );
    
    veryl_Core core(
        .i_clk,
        .i_rst(!i_rst),
        .*
    );

    logic w_clk_dvi_x5;
    dvi_x5_rpll dvi_x5_clk_gen(
        .clkout(w_clk_dvi_x5), //output clkout
        .clkin(i_clk_27MHz) //input clkin
    );

    localparam VGACLOCK_MHZ	= 74.25;
    localparam FSCLOCK_KHZ	= 44.1;
    hdmi_tx #(
		.DEVICE_FAMILY		("Cyclone IV E"),
		.CLOCK_FREQUENCY	(VGACLOCK_MHZ),
		.SCANMODE			("UNDER"),
		// .COLORSPACE			("BT709"),
		.AUDIO_FREQUENCY	(FSCLOCK_KHZ)
	)
	u_tx (
		.reset		(!i_rst),
		.clk		(i_clk_dvi),
		.clk_x5		(w_clk_dvi_x5),

		.active		(o_de),
		.r_data		(o_data[23:16]),
		.g_data		(o_data[15:8]),
		.b_data		(o_data[7:0]),
		.hsync		(o_hsync),
		.vsync		(o_vsync),

		.pcm_fs		('0),
		.pcm_l		('0),	// -12dB
		.pcm_r		('0),	// -12dB

		.data		({TMDS_DATA2,TMDS_DATA1,TMDS_DATA0}),
		.clock		(TMDS_CLOCK)
	);

endmodule