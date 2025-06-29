
    module videosync #(
    parameter H_FRONT_PORCH = 16,
    parameter H_SYNC_PULSE = 96,
    parameter H_BACK_PORCH = 48,
    parameter H_ACTIVE_AREA = 640,
    parameter V_FRONT_PORCH = 10,
    parameter V_SYNC_PULSE = 2,
    parameter V_BACK_PORCH = 33,
    parameter V_ACTIVE_AREA = 480,

    // Additional parameters from VHDL
    parameter string BAR_MODE = "WIDE", // "WIDE" or "SD"
    parameter string COLORSPACE = "RGB", // "RGB", "BT601", "BT709"
    parameter string START_SIG = "SINGLE", // "SINGLE" or "WIDTH"
    parameter int EARLY_REQ = 0, // 0-16
    parameter int FRAME_TOP = 0,
    parameter int START_HPOS = 0,
    parameter int START_VPOS = 0
    ) (
    input clk,
    input rst,
    // Add scan_ena input
    input scan_ena,

    output logic hsync,
    output logic vsync,
    output logic de,
    output logic [10:0] hcount,
    output logic [10:0] vcount,

    // Add new outputs
    output logic framestart,
    output logic linestart,
    output logic pixrequest,
    output logic [3:0] hdmicontrol,
    output logic hblank,
    output logic vblank,
    output logic csync,
    output logic [7:0] cb_rout,
    output logic [7:0] cb_gout,
    output logic [7:0] cb_bout
    );

    // Horizontal timing parameters
    localparam H_TOTAL = H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH + H_ACTIVE_AREA;

    // Vertical timing parameters
    localparam V_TOTAL = V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH + V_ACTIVE_AREA;

    // Internal signals
    logic hsync_reg;
    logic vsync_reg;
    logic csync_reg;
    logic hblank_reg;
    logic vblank_reg;
    logic request_reg;
    logic preamble_reg;
    logic guard_reg;
    logic packet_reg;
    logic active_sig;

    logic vs_old_reg;
    logic hs_old_reg;
    logic scan_in_reg;
    logic scanena_reg;
    logic hsync_rise;
    logic vsync_rise;

    typedef enum {
        LEFTBAND1, WHITE, YELLOW, CYAN, GREEN, MAGENTA, RED, BLUE, RIGHTBAND1,
        LEFTBAND2, FULLWHITE, GRAY, RIGHTBAND2,
        LEFTBAND3, WHITELAMP, RIGHTBAND3,
        LEFTBAND4, REDLAMP, RIGHTBAND4,
        LEFTBAND5, GREENLAMP, RIGHTBAND5,
        LEFTBAND6, BLUELAMP, RIGHTBAND6
    } STATE_CB_AREA;
    STATE_CB_AREA areastate;
    logic [3*8-1:0] cb_rgb_reg;
    logic [15:0] cblamp_reg;
    logic [7:0] chroma_sig;

    // Constant declarations (from VHDL)
    localparam PREAMBLE_WIDTH = 8;
    localparam GUARDBAND_WIDTH = 2;
    localparam PACKETAREA_WIDTH = PREAMBLE_WIDTH + GUARDBAND_WIDTH*2 + 32 + 2;
    localparam ISLANDGAP_WIDTH = 4;

    // Function to calculate colorbar band positions
    function int cb_band(int N);
        int start = H_SYNC_PULSE + H_BACK_PORCH - EARLY_REQ - 1;
        begin
        if (BAR_MODE == "WIDE") begin
            if (N == 0) cb_band = start + H_ACTIVE_AREA/8;
            else if (N == 8) cb_band = start + H_ACTIVE_AREA;
            else if (N == 9) cb_band = start + H_ACTIVE_AREA/8 + (3 * H_ACTIVE_AREA * 3)/(28*2);
            else if (N == 10) cb_band = start + H_ACTIVE_AREA/8 + (7 * H_ACTIVE_AREA * 3)/(28*2);
            else cb_band = start + H_ACTIVE_AREA/8 + (N * H_ACTIVE_AREA * 3)/28;
        end else begin
            if (N == 0) cb_band = start;
            else if (N == 7) cb_band = start + H_ACTIVE_AREA;
            else if (N == 8) cb_band = start + H_ACTIVE_AREA + 1;
            else if (N == 9) cb_band = start + (3 * H_ACTIVE_AREA)/(7*2);
            else if (N == 10) cb_band = start + (7 * H_ACTIVE_AREA)/(7*2);
            else cb_band = start + (N * H_ACTIVE_AREA)/7;
        end
        end
    endfunction

    // Function to calculate colorbar lamp begin
    function int cb_lampbegin();
        begin
        if (COLORSPACE == "BT601" || COLORSPACE == "BT709") cb_lampbegin = 16;
        else cb_lampbegin = 0;
        end
    endfunction

    // Function to calculate colorbar lamp end
    function int cb_lampend();
        begin
        if (COLORSPACE == "BT601" || COLORSPACE == "BT709") cb_lampend = 235;
        else cb_lampend = 255;
        end
    endfunction

    // Function to calculate colorbar lamp step
    function int cb_lampstep();
        begin
        if (BAR_MODE == "WIDE") cb_lampstep = (cb_lampend() - cb_lampbegin()) * 256 / ((H_ACTIVE_AREA * 3 / 4) - 1);
        else cb_lampstep = (cb_lampend() - cb_lampbegin()) * 256 / (H_ACTIVE_AREA - 1);
        end
    endfunction

    // Function to convert RGB to YCbCr or return RGB based on COLORSPACE
    function logic [23:0] cb_color(real R, real G, real B);
        real y, cb, cr;
        begin
        if (COLORSPACE == "BT601") begin
            y  = 0.299*R + 0.587*G + 0.114*B;
            cb = 0.564*(B - y);
            cr = 0.713*(R - y);
            cb_color = {logic[7:0](int(224.0*cr+128.0)), logic[7:0](int(219.0*y + 16.0)), logic[7:0](int(224.0*cb+128.0))};
        end else if (COLORSPACE == "BT709") begin
            y  = 0.2126*R + 0.7152*G + 0.0722*B;
            cb = 0.5389*(B - y);
            cr = 0.6350*(R - y);
            cb_color = {logic[7:0](int(224.0*cr+128.0)), logic[7:0](int(219.0*y + 16.0)), logic[7:0](int(224.0*cb+128.0))};
        end else begin
            cb_color = {logic[7:0](int(R*255.0)), logic[7:0](int(G*255.0)), logic[7:0](int(B*255.0))};
        end
        end
    endfunction

    localparam CB_LEFTBAND = cb_band(0);
    localparam CB_75WHITE = cb_band(1);
    localparam CB_75YELLOW = cb_band(2);
    localparam CB_75CYAN = cb_band(3);
    localparam CB_75GREEN = cb_band(4);
    localparam CB_75MAGENTA = cb_band(5);
    localparam CB_75RED = cb_band(6);
    localparam CB_75BLUE = cb_band(7);
    localparam CB_RIGHTBAND = cb_band(8);
    localparam CB_BLACKBAND = cb_band(9);
    localparam CB_WHITEBAND = cb_band(10);
    localparam CB_NORMAL_V = V_SYNC_PULSE + V_BACK_PORCH + (V_ACTIVE_AREA*7)/12 - 1;
    localparam CB_GRAY_V = V_SYNC_PULSE + V_BACK_PORCH + (V_ACTIVE_AREA*8)/12 - 1;
    localparam CB_WLAMP_V = V_SYNC_PULSE + V_BACK_PORCH + (V_ACTIVE_AREA*9)/12 - 1;
    localparam CB_RLAMP_V = V_SYNC_PULSE + V_BACK_PORCH + (V_ACTIVE_AREA*10)/12 - 1;
    localparam CB_GLAMP_V = V_SYNC_PULSE + V_BACK_PORCH + (V_ACTIVE_AREA*11)/12 - 1;
    localparam CB_BLAMP_V = V_SYNC_PULSE + V_BACK_PORCH + V_ACTIVE_AREA - 1;

    localparam logic [23:0] COLOR_BLACK = cb_color(0.0 , 0.0 , 0.0 );
    localparam logic [23:0] COLOR_WHITE = cb_color(1.0 , 1.0 , 1.0 );
    localparam logic [23:0] COLOR_YELLOW = cb_color(1.0 , 1.0 , 0.0 );
    localparam logic [23:0] COLOR_CYAN = cb_color(0.0 , 1.0 , 1.0 );
    localparam logic [23:0] COLOR_RED = cb_color(1.0 , 0.0 , 0.0 );
    localparam logic [23:0] COLOR_BLUE = cb_color(0.0 , 0.0 , 1.0 );
    localparam logic [23:0] COLOR_15WHITE = cb_color(0.15, 0.15, 0.15);
    localparam logic [23:0] COLOR_40WHITE = cb_color(0.40, 0.40, 0.40);
    localparam logic [23:0] COLOR_75WHITE = cb_color(0.75, 0.75, 0.75);
    localparam logic [23:0] COLOR_75YELLOW = cb_color(0.75, 0.75, 0.0 );
    localparam logic [23:0] COLOR_75CYAN = cb_color(0.0 , 0.75, 0.75);
    localparam logic [23:0] COLOR_75GREEN = cb_color(0.0 , 0.75, 0.0 );
    localparam logic [23:0] COLOR_75MAGENTA = cb_color(0.75, 0.0 , 0.75);
    localparam logic [23:0] COLOR_75RED = cb_color(0.75, 0.0 , 0.0 );
    localparam logic [23:0] COLOR_75BLUE = cb_color(0.0 , 0.0 , 0.75);

    // Horizontal counters
    always_ff @(posedge clk) begin
        if (rst) begin
        hcount <= 0;
        end else begin
        if (hcount == H_TOTAL - 1) begin
            hcount <= 0;
        end else begin
            hcount <= hcount + 1;
        end
        end
    end

    // Vertical counters
    always_ff @(posedge clk) begin
        if (rst) begin
        vcount <= 0;
        end else begin
        if (hcount == H_TOTAL - 1) begin
            if (vcount == V_TOTAL - 1) begin
            vcount <= 0;
            end else begin
            vcount <= vcount + 1;
            end
        end
        end
    end

    // Horizontal sync generation
    always_ff @(posedge clk) begin
        if (rst) begin
        hsync <= 0;
        end else begin
        if ((hcount >= H_FRONT_PORCH) && (hcount < H_FRONT_PORCH + H_SYNC_PULSE)) begin
            hsync <= 0;
        end else begin
            hsync <= 1;
        end
        end
    end

    // Vertical sync generation
    always_ff @(posedge clk) begin
        if (rst) begin
        vsync <= 0;
        end else begin
        if ((vcount >= V_FRONT_PORCH) && (vcount < V_FRONT_PORCH + V_SYNC_PULSE)) begin
            vsync <= 0;
        end else begin
            vsync <= 1;
        end
        end
    end

    // Data enable generation
    always_ff @(posedge clk) begin
        if (rst) begin
        de <= 0;
        end else begin
        if ((hcount >= H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH) && (hcount < H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH + H_ACTIVE_AREA) &&
            (vcount >= V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH) && (vcount < V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH + V_ACTIVE_AREA)) begin
            de <= 1;
        end else begin
            de <= 0;
        end
        end
    end

    // Video Sync Signal Generation (adapted from VHDL)
    always_ff @(posedge clk) begin
        if (rst) begin
        hsync_reg <= 0;
        vsync_reg <= 0;
        csync_reg <= 0;
        hblank_reg <= 1;
        vblank_reg <= 1;
        request_reg <= 0;
        preamble_reg <= 0;
        guard_reg <= 0;
        packet_reg <= 0;
        end else begin
        if (hcount == H_TOTAL - 1) begin
            hsync_reg <= 1;
        end else if (hcount == H_SYNC_PULSE - 1) begin
            hsync_reg <= 0;
        end

        if (hcount == H_TOTAL - 1) begin
            csync_reg <= 1;
        end else if ((vsync_reg == 0 && hcount == H_SYNC_PULSE - 1) || (vsync_reg == 1 && hcount == H_TOTAL - H_SYNC_PULSE)) begin
            csync_reg <= 0;
        end

        if (hcount == H_SYNC_PULSE + H_BACK_PORCH - 1) begin
            hblank_reg <= 0;
        end else if (hcount == H_SYNC_PULSE + H_BACK_PORCH + H_ACTIVE_AREA - 1) begin
            hblank_reg <= 1;
        end

        if (hcount == H_TOTAL - 1) begin
            if (vcount == V_TOTAL - 1) begin
            vsync_reg <= 1;
            end else if (vcount == V_SYNC_PULSE - 1) begin
            vsync_reg <= 0;
            end

            if (vcount == V_SYNC_PULSE + V_BACK_PORCH - 1) begin
            vblank_reg <= 0;
            end else if (vcount == V_SYNC_PULSE + V_BACK_PORCH + V_ACTIVE_AREA - 1) begin
            vblank_reg <= 1;
            end
        end

        if (vblank_reg == 0) begin
            if (hcount == H_SYNC_PULSE + H_BACK_PORCH - EARLY_REQ - 1) begin
            request_reg <= 1;
            end else if (hcount == H_SYNC_PULSE + H_BACK_PORCH + H_ACTIVE_AREA - EARLY_REQ - 1) begin
            request_reg <= 0;
            end

            if (hcount == H_SYNC_PULSE + H_BACK_PORCH - (PREAMBLE_WIDTH + GUARDBAND_WIDTH) - 1) begin
            preamble_reg <= 1;
            end else if (hcount == H_SYNC_PULSE + H_BACK_PORCH - GUARDBAND_WIDTH - 1) begin
            preamble_reg <= 0;
            guard_reg <= 1;
            end else if (hcount == H_SYNC_PULSE + H_BACK_PORCH - 1) begin
            guard_reg <= 0;
            end

            if (hcount == H_SYNC_PULSE + H_BACK_PORCH - (PACKETAREA_WIDTH + ISLANDGAP_WIDTH + PREAMBLE_WIDTH + GUARDBAND_WIDTH) - 1) begin
            packet_reg <= 0;
            end else if (hcount == H_SYNC_PULSE + H_BACK_PORCH + H_ACTIVE_AREA + ISLANDGAP_WIDTH - 1) begin
            packet_reg <= 1;
            end
        end else begin
            packet_reg <= 1;
        end
        end
    end

    assign active_sig = (hblank_reg == 0 && vblank_reg == 0) ? 1 : 0;

    assign hdmicontrol[0] = active_sig;
    assign hdmicontrol[1] = preamble_reg;
    assign hdmicontrol[2] = guard_reg;
    assign hdmicontrol[3] = packet_reg;

    assign hblank = hblank_reg;
    assign vblank = vblank_reg;
    assign csync = csync_reg;

    // Frame data read signal generation
    assign hsync_rise = (hs_old_reg == 0 && hsync_reg == 1);
    assign vsync_rise = (vs_old_reg == 0 && vsync_reg == 1);

    always_ff @(posedge clk) begin
        if (rst) begin
        vs_old_reg <= 0;
        hs_old_reg <= 0;
        scan_in_reg <= 0;
        scanena_reg <= 0;
        end else begin
        vs_old_reg <= vsync_reg;
        hs_old_reg <= hsync_reg;
        scan_in_reg <= scan_ena;

        if (vsync_rise) begin
            scanena_reg <= scan_in_reg;
        end
        end
    end

    // Generate framestart and linestart signals
    if (START_SIG == "SINGLE") begin : gen_pulse
        assign framestart = (hcount == 0 && vcount == FRAME_TOP) ? 1 : 0;
        assign linestart = (hsync_rise && vblank_reg == 0) ? scanena_reg : 0;
    end else begin : gen_width
        assign framestart = (hsync_reg == 1 && vcount == FRAME_TOP) ? 1 : 0;
        assign linestart = (hsync_reg == 1 && vblank_reg == 0) ? scanena_reg : 0;
    end

    assign pixrequest = (request_reg == 1) ? scanena_reg : 0;

    // Colorbar signal generation
    logic [7:0] chroma_sig_temp;
    assign chroma_sig_temp = cblamp_reg[15:8] + 2; // Color difference lamp center position correction

    always_ff @(posedge clk) begin
        if (rst) begin
        areastate <= LEFTBAND1;
        cblamp_reg <= 0;
        cb_rgb_reg <= 0;
        end else begin
        if (hcount == CB_LEFTBAND-1) begin
            cblamp_reg <= {logic[7:0](cb_lampbegin()), 8'h00};
        end else begin
            cblamp_reg <= cblamp_reg + cb_lampstep();
        end

        case (areastate)
            LEFTBAND1: begin
            if (hcount == CB_LEFTBAND) begin
                areastate <= WHITE;
                cb_rgb_reg <= COLOR_75WHITE;
            end
            end
            WHITE: begin
            if (hcount == CB_75WHITE) begin
                areastate <= YELLOW;
                cb_rgb_reg <= COLOR_75YELLOW;
            end
            end
            YELLOW: begin
            if (hcount == CB_75YELLOW) begin
                areastate <= CYAN;
                cb_rgb_reg <= COLOR_75CYAN;
            end
            end
            CYAN: begin
            if (hcount == CB_75CYAN) begin
                areastate <= GREEN;
                cb_rgb_reg <= COLOR_75GREEN;
            end
            end
            GREEN: begin
            if (hcount == CB_75GREEN) begin
                areastate <= MAGENTA;
                cb_rgb_reg <= COLOR_75MAGENTA;
            end
            end
            MAGENTA: begin
            if (hcount == CB_75MAGENTA) begin
                areastate <= RED;
                cb_rgb_reg <= COLOR_75RED;
            end
            end
            RED: begin
            if (hcount == CB_75RED) begin
                areastate <= BLUE;
                cb_rgb_reg <= COLOR_75BLUE;
            end
            end
            BLUE: begin
            if (hcount == CB_75BLUE) begin
                areastate <= RIGHTBAND1;
                cb_rgb_reg <= COLOR_40WHITE;
            end
            end
            RIGHTBAND1: begin
            if (hcount == CB_RIGHTBAND) begin
                if (vcount == CB_NORMAL_V) begin
                areastate <= LEFTBAND2;
                cb_rgb_reg <= COLOR_CYAN;
                end else begin
                areastate <= LEFTBAND1;
                end
            end
            end
            LEFTBAND2: begin
            if (hcount == CB_LEFTBAND) begin
                areastate <= FULLWHITE;
                cb_rgb_reg <= COLOR_WHITE;
            end
            end
            FULLWHITE: begin
            if (hcount == CB_75WHITE) begin
                areastate <= GRAY;
                cb_rgb_reg <= COLOR_75WHITE;
            end
            end
            GRAY: begin
            if (hcount == CB_75BLUE) begin
                areastate <= RIGHTBAND2;
                cb_rgb_reg <= COLOR_BLUE;
            end
            end
            RIGHTBAND2: begin
            if (hcount == CB_RIGHTBAND) begin
                if (vcount == CB_GRAY_V) begin
                areastate <= LEFTBAND3;
                cb_rgb_reg <= COLOR_YELLOW;
                end else begin
                areastate <= LEFTBAND2;
                cb_rgb_reg <= COLOR_CYAN;
                end
            end
            end
            LEFTBAND3: begin
            if (hcount == CB_LEFTBAND) begin
                areastate <= WHITELAMP;

                if (COLORSPACE == "BT601" || COLORSPACE == "BT709") begin
                // Y LAMP Begin
                cb_rgb_reg <= {8'h80, cblamp_reg[15:8], 8'h80};
                end else begin
                // WHITE LAMP Begin
                cb_rgb_reg <= {cblamp_reg[15:8], cblamp_reg[15:8], cblamp_reg[15:8]};
                end
            end
            end
            WHITELAMP: begin
            if (hcount == CB_75BLUE) begin
                areastate <= RIGHTBAND3;
                cb_rgb_reg <= COLOR_RED;
            end else begin
                if (COLORSPACE == "BT601" || COLORSPACE == "BT709") begin
                // Y LAMP
                cb_rgb_reg <= {8'h80, cblamp_reg[15:8], 8'h80};
                end else begin
                // WHITE LAMP
                cb_rgb_reg <= {cblamp_reg[15:8], cblamp_reg[15:8], cblamp_reg[15:8]};
                end
            end
            end
            RIGHTBAND3: begin
            if (hcount == CB_RIGHTBAND) begin
                if (vcount == CB_WLAMP_V) begin
                areastate <= LEFTBAND4;
                cb_rgb_reg <= COLOR_15WHITE;
                end else begin
                areastate <= LEFTBAND3;
                cb_rgb_reg <= COLOR_YELLOW;
                end
            end
            end
            LEFTBAND4: begin
            if (hcount == CB_LEFTBAND) begin
                areastate <= REDLAMP;

                if (COLORSPACE == "BT601" || COLORSPACE == "BT709") begin
                // Cr LAMP (50% Y) Begin
                cb_rgb_reg <= {chroma_sig_temp, 8'h80, 8'h80};
                end else begin
                // RED LAMP begin
                cb_rgb_reg <= {cblamp_reg[15:8], 8'h00, 8'h00};
                end
            end
            end
            REDLAMP: begin
            if (hcount == CB_75BLUE) begin
                areastate <= RIGHTBAND4;
                cb_rgb_reg <= COLOR_15WHITE;
            end else begin
                if (COLORSPACE == "BT601" || COLORSPACE == "BT709") begin
                // Cr LAMP (50% Y)
                cb_rgb_reg <= {chroma_sig_temp, 8'h80, 8'h80};
                end else begin
                // RED LAMP
                cb_rgb_reg[23:16] <= cblamp_reg[15:8];
                end
            end
            end
            RIGHTBAND4: begin
            if (hcount == CB_RIGHTBAND) begin
                if (vcount == CB_RLAMP_V) begin
                areastate <= LEFTBAND5;
                end else begin
                areastate <= LEFTBAND4;
                end
            end
            end
            LEFTBAND5: begin
            if (hcount == CB_LEFTBAND) begin
                areastate <= GREENLAMP;

                if (COLORSPACE == "BT601" || COLORSPACE == "BT709") begin
                // Cb LAMP (50% Y) begin
                cb_rgb_reg <= {8'h80, 8'h80, chroma_sig_temp};
                end else begin
                // GREEN LAMP begin
                cb_rgb_reg <= {8'h00, cblamp_reg[15:8], 8'h00};
                end
            end
            end
            GREENLAMP: begin
            if (hcount == CB_75BLUE) begin
                areastate <= RIGHTBAND5;
                cb_rgb_reg <= COLOR_15WHITE;
            end else begin
                if (COLORSPACE == "BT601" || COLORSPACE == "BT709") begin
                // Cb LAMP (50% Y)
                cb_rgb_reg <= {8'h80, 8'h80, chroma_sig_temp};
                end else begin
                // GREEN LAMP
                cb_rgb_reg[15:8] <= cblamp_reg[15:8];
                end
            end
            end
            RIGHTBAND5: begin
            if (hcount == CB_RIGHTBAND) begin
                if (vcount == CB_GLAMP_V) begin
                areastate <= LEFTBAND6;
                end else begin
                areastate <= LEFTBAND5;
                end
            end
            end
            LEFTBAND6: begin
            if (hcount == CB_LEFTBAND) begin
                areastate <= BLUELAMP;

                if (COLORSPACE == "BT601" || COLORSPACE == "BT709") begin
                // 0%/100% BAR Begin
                cb_rgb_reg <= COLOR_BLACK;
                end else begin
                // BLUE LAMP Begin
                cb_rgb_reg <= {8'h00, 8'h00, cblamp_reg[15:8]};
                end

            end
            end
            BLUELAMP: begin
            if (hcount == CB_75BLUE) begin
                areastate <= RIGHTBAND6;
                cb_rgb_reg <= COLOR_15WHITE;
            end else begin
                if (COLORSPACE == "BT601" || COLORSPACE == "BT709") begin
                // 0%/100% BAR
                if (hcount == CB_BLACKBAND) begin
                    cb_rgb_reg <= COLOR_WHITE;
                end else if (hcount == CB_WHITEBAND) begin
                    cb_rgb_reg <= COLOR_BLACK;
                end
                end else begin
                // BLUE LAMP
                cb_rgb_reg[7:0] <= cblamp_reg[15:8];
                end
            end
            end
            RIGHTBAND6: begin
            if (hcount == CB_RIGHTBAND) begin
                if (vcount == CB_BLAMP_V) begin
                areastate <= LEFTBAND1;
                cb_rgb_reg <= COLOR_40WHITE;
                end else begin
                areastate <= LEFTBAND6;
                end
            end
            end
            default: areastate <= LEFTBAND1;
        endcase
        end
    end

    assign cb_rout = (request_reg == 1) ? cb_rgb_reg[23:16] : 8'h00;
    assign cb_gout = (request_reg == 1) ? cb_rgb_reg[15:8] : 8'h00;
    assign cb_bout = (request_reg == 1) ? cb_rgb_reg[7:0] : 8'h00;

    endmodule
//# sourceMappingURL=videosync.sv.map
