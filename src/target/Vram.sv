module veryl_VramSync #(
    parameter int unsigned OUT_MODE      = 2                                                                         , // 1: 24bit フルカラー, 2: 16色モード
    parameter int unsigned WIDTH         = 128                                                                       , // 画面横幅
    parameter int unsigned HEIGHT        = 128                                                                       , // 画面縦幅
    parameter int unsigned WORD_SIZE     = ((OUT_MODE == 1) ? ( WIDTH * HEIGHT * 3 ) : ( (WIDTH * HEIGHT + 1) >> 1 )), // 総ピクセル数 * 1ピクセルあたりのバイト数
    parameter int unsigned DATA_WIDTH    = 8                                                                         ,
    parameter type         DATA_TYPE     = logic [DATA_WIDTH-1:0]                                                    ,
    parameter int unsigned ADDRESS_WIDTH = $clog2(WORD_SIZE)                                                         ,
    parameter int unsigned ADDRESS_MAX   = DATA_WIDTH * $clog2(WORD_SIZE)                                            , // アドレスの最大値 = 命令サイズ*WORD_SIZE
    parameter bit          BUFFER_OUT    = 1                                                                         , // 同期読み出し
    parameter DATA_TYPE    INITIAL_VALUE = DATA_TYPE'(0                                                             )
) (
    input var logic                          i_clk , // クロック
    input var logic                          i_rst , // リセット
    input var logic                          i_clr , // リセット2
    input var logic                          i_mea , // セレクト (w)
    input var logic     [DATA_WIDTH / 8-1:0] i_wea , // バイト単位の書き込み許可 (w)
    input var logic     [ADDRESS_WIDTH-1:0]  i_adra, // アドレス (w)
    input var DATA_TYPE                      i_da  , // データ (w)
    // i_meb : input  logic                    , // セレクト (r)
    // i_adrb: input  logic    <ADDRESS_WIDTH> , // アドレス (r)
    // o_qb  : output DATA_TYPE                , // データ (r)

    input  var logic                             i_clk_video,
    input  var logic                             i_rst_video,
    input  var logic                             i_mev      ,
    input  var logic     [$clog2(WORD_SIZE)-1:0] i_adrv     ,
    output var DATA_TYPE                         o_qv   
);

    logic [$bits(DATA_TYPE)-1:0] ram_data [0:WORD_SIZE-1];
    // var r_qb     : logic<$bits(DATA_TYPE)>            ;
    logic [$bits(DATA_TYPE)-1:0] r_qv;

    initial begin
        $readmemh("ram_data.hex", ram_data);
    end

    always_ff @ (posedge i_clk) begin
        if (i_rst) begin
            
        end else begin
            if (i_mea && i_wea) begin
                ram_data[i_adra] <= i_da;
            end
        end
    end

    always_comb begin
        // o_qb = r_qb;
        o_qv = r_qv;
    end

    if (!BUFFER_OUT) begin
        // always_comb {
        //     if i_mea && i_wea && i_adra == i_adrb {
        //         r_qb = i_da;
        //     } else {
        //         r_qb = ram_data[i_adrb];
        //     }
        // }
     :g_out

        always_comb begin
            if (i_mea && i_wea && i_adra == i_adrv) begin
                r_qv = i_da;
            end else begin
                r_qv = ram_data[i_adrv];
            end
        end

    end else begin :g_out
        // always_ff (i_clk, i_rst) {
        //     if_reset {
        //         r_qb = 0;
        //     } else {
        //         if i_mea && i_wea && i_adra == i_adrb {
        //             r_qb = i_da;
        //         } else {
        //             r_qb = ram_data[i_adrb];
        //         }
        //     }
        // }

        always_ff @ (posedge i_clk_video) begin
            if (i_rst_video) begin
                r_qv <= 0;
            end else begin
                if (i_mea && i_wea && i_adra == i_adrv) begin
                    r_qv <= i_da;
                end else begin
                    r_qv <= ram_data[i_adrv];
                end
            end
        end

    end
endmodule
//# sourceMappingURL=Vram.sv.map
