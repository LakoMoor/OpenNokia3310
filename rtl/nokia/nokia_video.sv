// SPDX-License-Identifier: GPL-3.0-or-later
// One clock for PCD8544 DDRAM, HDMI pixels and the LCD capture stream.
module nokia_video (
    input logic clk, reset,
    input logic lcd_wr, lcd_dc,
    input logic [7:0] lcd_data,
    output logic ready,
    input logic [9:0] hdmi_x, hdmi_y,
    output logic [23:0] rgb,
    output logic lcd_scl, lcd_sda, lcd_cs, lcd_dc_out, lcd_rst, lcd_bl
);
    // 84x48 -> 672x384, centered in 720x480. Address before RAM edge.
    wire in_hdmi = hdmi_x >= 24 && hdmi_x < 696 && hdmi_y >= 48 && hdmi_y < 432;
    wire [9:0] hx = hdmi_x - 10'd24;
    wire [9:0] hy = hdmi_y - 10'd48;
    logic in_hdmi_q;
    wire pixel_hdmi, pixel_lcd;
    // Feed the upstream LCD in crop mode: its central 128x128 becomes the panel.
    // Center Nokia in the 160x144 input at (38,48), hence panel offset (22,40).
    logic [7:0] sx, sy;
    logic [18:0] period;
    logic scanning, stream_valid, stream_first;
    logic [14:0] stream_data;
    wire in_lcd = sx >= 38 && sx < 122 && sy >= 48 && sy < 96;
    wire [7:0] lx = sx - 8'd38;
    wire [7:0] ly = sy - 8'd48;
    logic valid_q, first_q, in_lcd_q;
    pcd8544 u_lcd (
        .clk(clk), .reset(reset), .wr(lcd_wr), .dc(lcd_dc), .data(lcd_data), .ready(ready),
        .x0(in_hdmi ? hx[9:3] : 7'd127), .y0(in_hdmi ? hy[8:3] : 6'd63),
        .x1(in_lcd ? lx[6:0] : 7'd127), .y1(in_lcd ? ly[5:0] : 6'd63),
        .pixel0(pixel_hdmi), .pixel1(pixel_lcd)
    );
    always_ff @(posedge clk) begin
        in_hdmi_q <= in_hdmi;
        valid_q <= scanning;
        first_q <= sx == 0 && sy == 0;
        in_lcd_q <= in_lcd;
        if (reset || !ready) begin
            sx <= 0; sy <= 0; period <= 0; scanning <= 0;
            valid_q <= 0; first_q <= 0; in_lcd_q <= 0; in_hdmi_q <= 0;
        end else begin
            period <= period == 449999 ? 19'd0 : period + 1'b1;
            if (period == 0) begin scanning <= 1; sx <= 0; sy <= 0; end
            else if (scanning) begin
                if (sx == 159) begin
                    sx <= 0;
                    if (sy == 143) begin sy <= 0; scanning <= 0; end
                    else sy <= sy + 1'b1;
                end else sx <= sx + 1'b1;
            end
        end
    end
    // No extra register: RAM pixel and valid/first flags already have equal latency.
    always_comb begin
        rgb = in_hdmi_q ? (pixel_hdmi ? 24'h26351c : 24'hc4cfa1) : 24'h101810;
        stream_valid = valid_q;
        stream_first = first_q;
        stream_data = in_lcd_q && pixel_lcd ? 15'd3 : 15'd0;
    end
    lcd_st7735 #(.CLK_HZ(27_000_000)) u_panel (
        .clk(clk), .reset(reset), .px_we(stream_valid), .px_first(stream_first), .px_data(stream_data),
        .isGBC(1'b0), .dmg_pal(3'd2), .gbc_raw(1'b0), .crop(1'b1),
        .menu_open(1'b0), .dbg_on(1'b0), .slow(1'b0), .txt_addr(), .txt_q(16'b0),
        .lcd_scl(lcd_scl), .lcd_sda(lcd_sda), .lcd_cs(lcd_cs), .lcd_dc(lcd_dc_out),
        .lcd_rst(lcd_rst), .lcd_bl(lcd_bl)
    );
endmodule
