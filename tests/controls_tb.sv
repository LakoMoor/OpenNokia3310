`timescale 1ns/1ps
module controls_tb;
    reg clk=0,reset=1,menu_button=0,control_wr=0;
    reg [16:0] keys=0;
    reg [7:0] control_opcode=0,control_data=0;
    wire menu_open,stream_enabled,gray,reset_request,test_start;
    wire [2:0] menu_row;
    wire [3:0] volume;
    always #5 clk=~clk;
    nokia_controls #(.CLK_HZ(3000)) dut(.*);
    task command(input [7:0] op,d);
        @(negedge clk);control_wr=1;control_opcode=op;control_data=d;
        @(negedge clk);control_wr=0;
    endtask
    task key(input integer k);
        @(negedge clk);keys=17'b1<<k;@(negedge clk);keys=0;@(negedge clk);
    endtask
    initial begin
        repeat(4)@(negedge clk);reset=0;
        command(5,3);if(!stream_enabled || !menu_open)$fatal(1,"app stream/menu command");
        key(15);if(menu_row!=1)$fatal(1,"down");
        key(6);if(volume!=6)$fatal(1,"volume right");
        key(4);if(volume!=5)$fatal(1,"volume left");
        key(15);key(12);if(!gray)$fatal(1,"palette");
        key(13);if(menu_open)$fatal(1,"back");
        @(negedge clk);menu_button=1;repeat(10)@(negedge clk);if(!menu_open)$fatal(1,"held menu must toggle once");menu_button=0;
        command(6,255);if(volume!=10)$fatal(1,"volume clamp");
        command(5,5);if(!reset_request)$fatal(1,"reset pulse");
        @(negedge clk);if(reset_request)$fatal(1,"reset request must clear");
        $display("PASS controls: app commands, menu navigation, volume, palette, edge/release, reset pulse");$finish;
    end
endmodule
