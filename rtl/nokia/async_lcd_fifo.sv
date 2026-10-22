// SPDX-License-Identifier: GPL-3.0-or-later
// 16 command/data words; independent Gray-coded pointers, two-flop CDC.
module async_lcd_fifo (
    input logic wclk,wrst,wvalid,
    input logic [8:0] wdata,
    output logic wready,
    input logic rclk,rrst,rready,
    output logic rvalid,
    output logic [8:0] rdata
);
    logic [8:0] mem [0:15];
    logic [4:0] wp,rp,wgray,rgray;
    (* async_reg="true" *) logic [4:0] rmeta,rsync,wmeta,wsync;
    assign wgray=(wp>>1)^wp;
    assign rgray=(rp>>1)^rp;
    assign wready=wgray!={~rsync[4:3],rsync[2:0]};
    assign rvalid=rgray!=wsync;
    assign rdata=mem[rp[3:0]];
    always_ff @(posedge wclk) begin
        rmeta<=rgray;rsync<=rmeta;
        if(wvalid && wready) begin mem[wp[3:0]]<=wdata;wp<=wp+1'b1;end
        if(wrst) begin wp<=0;rmeta<=0;rsync<=0;end
    end
    always_ff @(posedge rclk) begin
        wmeta<=wgray;wsync<=wmeta;
        if(rvalid && rready) rp<=rp+1'b1;
        if(rrst) begin rp<=0;wmeta<=0;wsync<=0;end
    end
endmodule
