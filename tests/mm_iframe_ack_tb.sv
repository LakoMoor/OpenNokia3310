`timescale 1ns/1ps
module mm_iframe_ack_tb;
    reg clk=0,reset=1,uplink_valid=0,downlink_ready=0;
    reg [183:0] uplink_frame={23{8'h2b}};
    reg [4:0] uplink_length=23;
    reg [23:0] plmn=24'h00f110;
    reg [15:0] lac=1;
    wire downlink_valid,registered,failed;
    wire [183:0] downlink_frame;
    mm_registration dut(.*);
    always #5 clk=~clk;
    task uplink(input [23:0] header);
        @(negedge clk);uplink_frame[183:160]=header;uplink_valid=1;
        @(negedge clk);uplink_valid=0;
    endtask
    task sent;
        @(negedge clk);downlink_ready=1;@(negedge clk);downlink_ready=0;
    endtask
    initial begin
        repeat(4)@(negedge clk);reset=0;
        uplink_frame[159:144]=16'h0508;uplink(24'h033f09);sent();
        uplink_length=3;uplink(24'h032005);
        if(downlink_valid || registered)$fatal(1,"truncated I-frame acknowledged");
        uplink_length=23;uplink(24'h0f2005);
        if(downlink_valid)$fatal(1,"wrong SAPI I-frame acknowledged");
        uplink(24'h032004);if(downlink_valid)$fatal(1,"invalid EL I-frame acknowledged");
        uplink(24'h030005);if(downlink_valid)$fatal(1,"wrong N(R) I-frame acknowledged");
        uplink(24'h032005);
        if(!downlink_valid || downlink_frame[175:168]!=2)$fatal(1,"piggyback LU ACK ignored");
        sent();uplink(24'h032001);
        if(registered)$fatal(1,"duplicate I-frame ACK advanced release");
        uplink(24'h034001);
        if(!registered || failed)$fatal(1,"piggyback release ACK ignored");
        $display("PASS MM I-frame ACK: piggyback N(R), malformed/SAPI/duplicate rejection");$finish;
    end
    initial begin #10000;$fatal(1,"MM I-frame timeout");end
endmodule
