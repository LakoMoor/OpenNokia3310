// SPDX-License-Identifier: GPL-3.0-or-later
// Static menu and digit tiles share one synchronous 2KiB ROM per scan port.
// This uses spare BSRAM instead of several hundred LUTs of text/font multiplexers.
module nokia_overlay (
    input logic clk,
    input logic [6:0] x,
    input logic [5:0] y,
    input logic [2:0] row,
    input logic [3:0] volume,
    input logic gray,
    output logic pixel
);
    logic [7:0] bitmap[0:2047];
    initial $readmemh("rtl/nokia/menu_bitmap.hex",bitmap);
    logic [10:0] address;
    logic [3:0] digit;
    logic [7:0] data_q;
    logic [2:0] bit_q;
    logic highlight_q,valid_q;
    wire [8:0] position={y[5:3],6'b0}+{y[5:3],4'b0}+{y[5:3],2'b0}+{2'b0,x};
    always_comb begin
        digit=volume;
        address={1'b0,gray,position};
        if(y[5:3]==2 && (x[6:3]==7 || x[6:3]==8))begin
            if(x[6:3]==7)digit=volume==10 ? 4'd1 : 4'd10;
            else digit=volume==10 ? 4'd0 : volume;
            address=11'd1024+{4'b0,digit,3'b0}+{8'b0,x[2:0]};
        end
    end
    always_ff @(posedge clk)begin
        data_q<=bitmap[address];bit_q<=y[2:0];
        highlight_q<=y[5:3]==row+1'b1;valid_q<=x<84 && y<48;
    end
    assign pixel=valid_q && (data_q[bit_q]^highlight_q);
endmodule
