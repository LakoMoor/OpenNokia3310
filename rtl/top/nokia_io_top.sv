// SPDX-License-Identifier: GPL-3.0-or-later
// Board I/O qualification only. CPU/firmware are NOT part of this target.
module nokia_io_top (
    input logic sys_clk, s1, uart_rx, ds_miso,
    output logic uart_tx,
    output logic [1:0] led,
    output logic tmds_clk_p, tmds_clk_n,
    output logic [2:0] tmds_d_p, tmds_d_n,
    output logic ds_clk, ds_cs, ds_mosi,
    output logic lcd_scl, lcd_sda, lcd_cs, lcd_dc, lcd_rst, lcd_bl
);
    wire clk_p5, clk_p, locked;
    pll_hdmi480 u_pll_a_hdmi (.clock_in(sys_clk), .pwrdn(1'b0), .clock_out(clk_p5), .locked(locked));
    CLKDIV #(.DIV_MODE("5")) u_div5 (.CLKOUT(clk_p), .HCLKIN(clk_p5), .RESETN(locked), .CALIB(1'b0));
    logic [7:0] por = 0;
    logic s1_meta=0, s1_sync=0;
    always_ff @(posedge clk_p) begin
        s1_meta <= s1; s1_sync <= s1_meta;
        if (!locked || s1_sync) por <= 0;
        else if (por != 255) por <= por + 1'b1;
    end
    wire reset = por != 255;
    wire [7:0] ds0,ds1;
    wire [7:0] pad_id;
    wire pad_connected;
    ds2_pad u_pad (
        .clk(clk_p), .reset(reset), .sck(ds_clk), .cs_n(ds_cs),
        .mosi(ds_mosi), .miso(ds_miso), .buttons0(ds0), .buttons1(ds1),
        .controller_id(pad_id),.connected(pad_connected)
    );
    wire [16:0] pad_keys, remote_keys;
    pad_3310 u_keys (.buttons0(ds0), .buttons1(ds1), .keys(pad_keys));
    wire wr, dc, ready;
    wire [7:0] data;
    uart_lcd u_uart (.clk(clk_p), .reset(reset), .rx(uart_rx), .wr(wr), .dc(dc), .data(data), .keys(remote_keys));
    wire [9:0] cx,cy;
    wire [23:0] rgb;
    nokia_video u_video (
        .clk(clk_p), .reset(reset), .lcd_wr(wr), .lcd_dc(dc), .lcd_data(data), .ready(ready),
        .hdmi_x(cx), .hdmi_y(cy), .rgb(rgb),
        .lcd_scl(lcd_scl), .lcd_sda(lcd_sda), .lcd_cs(lcd_cs), .lcd_dc_out(lcd_dc), .lcd_rst(lcd_rst), .lcd_bl(lcd_bl)
    );
    wire [2:0] tmds;
    wire tmds_clock;
    wire [15:0] silence [1:0];
    assign silence[0]=0; assign silence[1]=0;
    hdmi #(.VIDEO_ID_CODE(2), .DVI_OUTPUT(1)) u_hdmi (
        .clk_pixel_x5(clk_p5), .clk_pixel(clk_p), .clk_audio(1'b0), .reset(reset),
        .rgb(rgb), .audio_sample_word(silence), .tmds(tmds), .tmds_clock(tmds_clock),
        .cx(cx), .cy(cy), .frame_width(), .frame_height(), .screen_width(), .screen_height()
    );
    TLVDS_OBUF u_obuf [3:0] (.I({tmds_clock,tmds}), .O({tmds_clk_p,tmds_d_p}), .OB({tmds_clk_n,tmds_d_n}));
    assign led = {~(|(pad_keys | remote_keys)), ~ready};
    // I/O qualification telemetry: raw DS2 bytes, mapped key mask.
    uart_status #(.CLK_HZ(27_000_000)) u_status (.clk(clk_p),.reset(reset),
        .flags({7'b0,pad_connected}),.address({8'b0,pad_id,ds0,ds1}),.lcd_count(pad_keys[15:0]),.tx(uart_tx));
endmodule
