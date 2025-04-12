package veryl_Video;
    typedef struct packed {
        int unsigned H_TOTAL      ;
        int unsigned H_SYNC       ;
        int unsigned H_BACK_PORCH ;
        int unsigned H_LBORDER    ;
        int unsigned H_ACTIVE     ;
        int unsigned H_RBORDER    ;
        int unsigned H_FRONT_PORCH;

        int unsigned V_TOTAL        ;
        int unsigned V_SYNC         ;
        int unsigned V_BACK_PORCH   ;
        int unsigned V_TOP_BORDER   ;
        int unsigned V_ACTIVE       ;
        int unsigned V_BOTTOM_BORDER;
        int unsigned V_FRONT_PORCH  ;
    } VesaDmtConfig;

    function automatic VesaDmtConfig Dmt1280x720At60Hz;
        VesaDmtConfig dmt_1280x720_at_60hz        ;
        dmt_1280x720_at_60hz.H_TOTAL = 1650;
        dmt_1280x720_at_60hz.H_SYNC  = 40;
        // dmt_1280x720_at_60hz.H_BACK_PORCH  = 220;
        dmt_1280x720_at_60hz.H_BACK_PORCH = 260;
        dmt_1280x720_at_60hz.H_LBORDER    = 0;
        dmt_1280x720_at_60hz.H_ACTIVE     = 1280;
        dmt_1280x720_at_60hz.H_RBORDER    = 0;
        // dmt_1280x720_at_60hz.H_FRONT_PORCH = 110;
        dmt_1280x720_at_60hz.H_FRONT_PORCH = 0;

        dmt_1280x720_at_60hz.V_TOTAL         = 750;
        dmt_1280x720_at_60hz.V_SYNC          = 5;
        dmt_1280x720_at_60hz.V_BACK_PORCH    = 20;
        dmt_1280x720_at_60hz.V_TOP_BORDER    = 0;
        dmt_1280x720_at_60hz.V_ACTIVE        = 720;
        dmt_1280x720_at_60hz.V_BOTTOM_BORDER = 0;
        // dmt_1280x720_at_60hz.V_FRONT_PORCH   = 5;
        dmt_1280x720_at_60hz.V_FRONT_PORCH = 0;
        return dmt_1280x720_at_60hz;
    endfunction
endpackage

module veryl_VideoControllerColTable #(
    parameter int unsigned               WIDTH              = 128                              ,
    parameter int unsigned               HEIGHT             = 128                              ,
    parameter int unsigned               NUM_TABLE          = 16                               ,
    parameter int unsigned               TABLE_BITS         = $clog2(NUM_TABLE)                ,
    parameter veryl_Video::VesaDmtConfig CONFIG             = veryl_Video::Dmt1280x720At60Hz() ,
    parameter int unsigned               NUM_PIXELS         = CONFIG.H_ACTIVE * CONFIG.V_ACTIVE,
    parameter int unsigned               PIXEL_ADR_BITS     = $clog2(NUM_PIXELS)               ,
    parameter int unsigned               VRAM_ADDRESS_WIDTH = $clog2((WIDTH * HEIGHT + 1) >> 1)
) (
    input wire i_clk,
    input wire i_rst,

    veryl_Decoupled.receiver if_col_table_din,

    veryl_Decoupled.receiver if_vdata_in,
    // if_vdata_out: modport Decoupled::sender                      ,
    input wire [VRAM_ADDRESS_WIDTH-1:0] i_vdata_adr,


    // o_clr : output logic                        ,
    // o_mea : output logic                        ,
    // o_wea : output logic                        ,
    // o_adra: output logic<$clog2(WIDTH * HEIGHT)>,
    // o_da  : output logic<TABLE_BITS>            ,
    // o_meb : output logic                        ,
    // o_adrb: output logic<$clog2(WIDTH * HEIGHT)>,
    // i_qb  : input wire<TABLE_BITS>            ,

    input wire          i_clk_dvi,
    input wire          i_rst_dvi,
    output logic [1-1:0]  o_vsync  ,
    output logic [1-1:0]  o_hsync  ,
    output logic [1-1:0]  o_de     ,
    output logic [24-1:0] o_data   

);
    // CPU -> (this module)
    // カラーテーブルの設定
    logic [24-1:0]                r_col_table           [0:NUM_TABLE-1];
    logic [$clog2(NUM_TABLE)-1:0] w_col_table_din_adr                  ; always_comb w_col_table_din_adr                   = if_col_table_din.bits[24+:$clog2(NUM_TABLE)];
    logic [24-1:0]                w_col_table_din_color                ; always_comb w_col_table_din_color                 = if_col_table_din.bits[0+:24];

    logic r_col_table_din_set_ready;
    always_comb if_col_table_din.ready    = r_col_table_din_set_ready;

    always_ff @ (posedge i_clk) begin
        if (i_rst) begin
            r_col_table[0] <= 24'h0000FF;
            r_col_table[1] <= 24'h00FF00;
            r_col_table[2] <= 24'hFF0000;
            for (int unsigned table_id = 3; table_id < NUM_TABLE; table_id++) begin
                r_col_table[table_id] <= 24'h000000;
            end
            r_col_table_din_set_ready <= 1'b0;
        end else begin
            if (if_col_table_din.valid) begin
                r_col_table[w_col_table_din_adr] <= w_col_table_din_color;
            end

            if (if_col_table_din.valid && !r_col_table_din_set_ready) begin
                r_col_table_din_set_ready <= 1'b1;
            end else begin
                r_col_table_din_set_ready <= 1'b0;
            end
        end
    end

    // VRAM -> (this module) -> CPU
    // VRAM 読み出し
    // var r_vram_read_valid: logic   ;
    // var w_vram_read_data : logic<8>;

    veryl_VramSync #(
        .OUT_MODE (2     ),
        .WIDTH    (WIDTH ),
        .HEIGHT   (HEIGHT)
    ) vram_sync (
        .i_clk  (i_clk                ),
        .i_rst  (i_rst                ),
        .i_clr  (0                    ),
        .i_mea  (if_vdata_in.valid    ),
        .i_wea  (if_vdata_in.valid    ),
        .i_adra (i_vdata_adr          ),
        .i_da   (if_vdata_in.bits[7:0]),
        // i_meb      : 1                    ,
        // i_adrb     : i_vdata_adr          ,
        // o_qb       : w_vram_read_data     ,
        .i_clk_video (i_clk_dvi  ),
        .i_rst_video (i_rst_dvi  ),
        .i_mev       (1          ),
        .i_adrv      (w_draw_adr ),
        .o_qv        (w_draw_data)
    );

    // if_vdata_out に信号が入力されてから valid が立つまで 1 クロック
    // i_vdata_adr  に信号が入力されてから o_qb にデータが出るまで 1 クロック
    // -> valid が立つタイミングと有効なデータが出るタイミングは一致
    // assign if_vdata_out.bits = w_vram_read_data as 32;

    // always_ff (i_clk, i_rst) {
    //     if_reset {
    //         r_vram_read_valid = 1'b0;
    //     } else {
    //         if if_vdata_out.ready && !r_vram_read_valid {
    //             r_vram_read_valid = 1'b1;
    //         } else {
    //             r_vram_read_valid = 1'b0;
    //         }
    //     }
    // }

    // CPU -> (this module) -> VRAM
    // VRAM 書き込み
    logic r_vram_write_ready;
    always_comb if_vdata_in.ready  = r_vram_write_ready;

    always_ff @ (posedge i_clk) begin
        if (i_rst) begin
            r_vram_write_ready <= 1'b0;
        end else begin
            if (if_vdata_in.valid && !r_vram_write_ready) begin
                r_vram_write_ready <= 1'b1;
            end else begin
                r_vram_write_ready <= 1'b0;
            end
        end
    end



    // VRAM -> (this module) -> GOWIN DVI TX IP
    logic [1-1:0]                      r_vsync        ;
    logic [1-1:0]                      r_hsync        ;
    logic [1-1:0]                      r_de           ;
    logic [24-1:0]                     r_data         ;
    logic [$clog2(CONFIG.H_TOTAL)-1:0] r_pixel_counter;
    logic [$clog2(CONFIG.V_TOTAL)-1:0] r_line_counter ;

    logic [8-1:0] r_red  ;
    logic [8-1:0] r_green;
    logic [8-1:0] r_blue ;
    always_comb o_data  = {r_blue, r_green, r_red};

    // let w_pixel_adr_flatten : `dvi logic<$clog2(CONFIG.H_ACTIVE * CONFIG.V_ACTIVE)> = YPos(r_line_counter) * CONFIG.H_ACTIVE + XPos(r_pixel_counter);
    logic [PIXEL_ADR_BITS-1:0]     w_pixel_adr_flatten ; always_comb w_pixel_adr_flatten  = PIXEL_ADR_BITS'((YPos(r_line_counter) * 128 + XPos(r_pixel_counter)));
    logic [VRAM_ADDRESS_WIDTH-1:0] w_draw_adr          ; always_comb w_draw_adr           = VRAM_ADDRESS_WIDTH'((w_pixel_adr_flatten >> 1));
    logic [8-1:0]                  w_draw_data         ;
    logic [TABLE_BITS-1:0]         w_draw_col_table_adr; always_comb w_draw_col_table_adr = TABLE_BITS'((w_draw_data >> (w_pixel_adr_flatten[0] << 1))); // pixel の番地が奇数のとき、上位 4bit を使う
    logic [1-1:0]                  w_is_vram_region    ; always_comb w_is_vram_region     = IsVramRegion(XPos(r_pixel_counter), YPos(r_line_counter));

    localparam int unsigned H_LBORDER_START      = CONFIG.H_SYNC + CONFIG.H_BACK_PORCH;
    localparam int unsigned H_ACTIVE_VIDEO_START = H_LBORDER_START + CONFIG.H_LBORDER;
    localparam int unsigned H_RBORDER_START      = H_ACTIVE_VIDEO_START + CONFIG.H_ACTIVE;
    localparam int unsigned H_FRONT_PORCH_START  = H_RBORDER_START + CONFIG.H_RBORDER;

    localparam int unsigned V_TOP_BORDER_START    = CONFIG.V_SYNC + CONFIG.V_BACK_PORCH;
    localparam int unsigned V_ACTIVE_VIDEO_START  = V_TOP_BORDER_START + CONFIG.V_TOP_BORDER;
    localparam int unsigned V_BOTTOM_BORDER_START = V_ACTIVE_VIDEO_START + CONFIG.V_ACTIVE;
    localparam int unsigned V_FRONT_PORCH_START   = V_BOTTOM_BORDER_START + CONFIG.V_BOTTOM_BORDER;

    // WIDTH x HEIGHT のVRAM領域のオフセット(原点：左上)
    localparam int unsigned OFFSET_X = 0;
    localparam int unsigned OFFSET_Y = 0;

    function automatic logic IsActiveRegion(
        input logic [$clog2(CONFIG.H_TOTAL)-1:0] i_pixel_counter,
        input logic [$clog2(CONFIG.V_TOTAL)-1:0] i_line_counter 
    ) ;
        return (H_ACTIVE_VIDEO_START <= 32'(i_pixel_counter) & 32'(i_pixel_counter) < H_RBORDER_START & V_ACTIVE_VIDEO_START <= 32'(i_line_counter) & 32'(i_line_counter) < V_BOTTOM_BORDER_START);
    endfunction

    function automatic int unsigned XPos(
        input logic [$clog2(CONFIG.H_TOTAL)-1:0] i_pixel_counter
    ) ;
        return 32'(i_pixel_counter) - H_ACTIVE_VIDEO_START;
    endfunction

    function automatic int unsigned YPos(
        input logic [$clog2(CONFIG.V_TOTAL)-1:0] i_line_counter
    ) ;
        return 32'(i_line_counter) - V_ACTIVE_VIDEO_START;
    endfunction

    function automatic logic IsVramRegion(
        input logic [32-1:0] i_x,
        input logic [32-1:0] i_y
    ) ;
        /* verilator lint_off UNSIGNED */
        return (OFFSET_X <= i_x && i_x < WIDTH + OFFSET_X && OFFSET_Y <= i_y && i_y < HEIGHT + OFFSET_Y);
        /* verilator lint_on UNSIGNED */
    endfunction

    logic [8-1:0] w_draw_red  ;
    logic [8-1:0] w_draw_green;
    logic [8-1:0] w_draw_blue ;

    always_comb {w_draw_blue, w_draw_green, w_draw_red} = r_col_table[w_draw_col_table_adr];

    always_ff @ (posedge i_clk_dvi) begin
        if (i_rst_dvi) begin
            r_pixel_counter <= 0;
            r_line_counter  <= 0;
            o_vsync         <= 1'b0;
            o_hsync         <= 1'b0;
            o_de            <= 1'b0;
            r_red           <= 8'b0;
            r_green         <= 8'b0;
            r_blue          <= 8'b0;
            r_vsync         <= 1'b0;
            r_hsync         <= 1'b0;
            r_de            <= 1'b0;
            r_data          <= 24'b0;
        end else begin
            // o_vsync = r_vsync;
            // o_hsync = r_hsync;
            // o_de    = r_de;

            // ほんとは as $bits(r_pixel_counter) を使いたいが、現状使えないので u32 に揃える
            if ((32'(r_pixel_counter) == CONFIG.H_TOTAL - 1)) begin
                r_pixel_counter <= 0;
                if ((32'(r_line_counter) == CONFIG.V_TOTAL - 1)) begin
                    r_line_counter <= 0;
                end else begin
                    r_line_counter <= r_line_counter + (1);
                end
            end else begin
                r_pixel_counter <= r_pixel_counter + (1);
            end
            o_hsync <= (32'(r_pixel_counter) < CONFIG.H_SYNC);
            o_vsync <= (32'(r_line_counter) < CONFIG.V_SYNC);
            o_de    <= IsActiveRegion(r_pixel_counter, r_line_counter);

            if ((IsActiveRegion(r_pixel_counter, r_line_counter) && IsVramRegion(XPos(r_pixel_counter), YPos(r_line_counter)))) begin
                r_red   <= w_draw_red;
                r_green <= w_draw_green;
                r_blue  <= w_draw_blue;
            end else begin
                r_red   <= 8'hFF;
                r_green <= 8'hFF;
                r_blue  <= 8'hFF;
            end
        end
    end
endmodule
//# sourceMappingURL=VideoController.sv.map
