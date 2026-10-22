`timescale 1ns/1ps
module pcd8544_tb;
    reg clk=0, reset=1, wr=0, dc=0;
    reg [7:0] data=0;
    wire ready, p0,p1;
    reg [6:0] x0=0,x1=0;
    reg [5:0] y0=0,y1=0;
    always #5 clk=~clk;
    pcd8544 dut(.clk(clk),.reset(reset),.wr(wr),.dc(dc),.data(data),.ready(ready),
        .x0(x0),.x1(x1),.y0(y0),.y1(y1),.pixel0(p0),.pixel1(p1));
    task send(input bit is_data,input [7:0] b);
        @(negedge clk); wr=1; dc=is_data; data=b;
        @(negedge clk); wr=0;
    endtask
    task check_pixel(input integer x,y,input bit expected);
        @(negedge clk); x0=x; y0=y; x1=x; y1=y;
        @(posedge clk); #1;
        if(p0 !== expected || p1 !== expected) $fatal(1,"pixel %0d,%0d expected %0d got %b,%b",x,y,expected,p0,p1);
    endtask
    reg [7:0] pattern;
    initial begin
        repeat(3) @(negedge clk); reset=0;
        wait(ready); send(0,8'h20); send(0,8'h0c);
        // Full DDRAM write, both independent read ports, all bank bit positions.
        for(integer bank=0;bank<6;bank=bank+1)
            for(integer x=0;x<84;x=x+1) send(1,(x+bank*17)&255);
        for(integer y=0;y<48;y=y+1)
            for(integer x=0;x<84;x=x+1) begin
                pattern=(x+(y/8)*17)&255;
                check_pixel(x,y,pattern[y%8]);
            end
        send(0,8'h0d); check_pixel(1,0,0); check_pixel(0,0,1);
        send(0,8'h09); check_pixel(0,0,1); check_pixel(83,47,1);
        send(0,8'h08); check_pixel(1,0,0);
        // Extended Vop command must not move X. Vertical address wraps banks first.
        send(0,8'h21); send(0,8'hff); send(0,8'h22);
        send(0,8'h80); send(0,8'h40); send(0,8'h0c);
        send(1,8'h80); send(1,8'h01);
        check_pixel(0,7,1); check_pixel(0,8,1); check_pixel(0,9,0);
        send(0,8'h24); repeat(2) @(negedge clk); check_pixel(0,7,0);
        send(0,8'h20); check_pixel(0,7,1);
        check_pixel(84,0,0); check_pixel(0,48,0);
        // Hardware reset clears DDRAM and ignores writes until clear has finished.
        @(negedge clk); reset=1;
        repeat(2) @(negedge clk); reset=0;
        wait(ready); send(0,8'h20); send(0,8'h0c); check_pixel(0,7,0);
        $display("PASS pcd8544: 4032 pixels, both scan ports, addressing, modes, reset");
        $finish;
    end
    initial begin #500000; $fatal(1,"timeout"); end
endmodule
