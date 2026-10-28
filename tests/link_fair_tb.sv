`timescale 1ns/1ps
module link_fair_tb;
    reg clk=0,reset=1,stream_enabled=1,lcd_wr=0,lcd_dc=0;
    reg [7:0] lcd_data=0,flags=0;
    reg [31:0] address=0;
    reg [15:0] lcd_count=0;
    reg [72:0] audio_control=0;
    reg [3:0] volume=5;
    reg menu_open=0,gray=0;
    reg [2:0] menu_row=0;
    wire tx;
    integer frame_count=0,status_count=0,audio_count=0;
    always #5 clk=~clk;
    nokia_link #(.CLK_HZ(115200),.BAUD(11520)) dut(.*);
    // A new device audio state is waiting whenever a packet finishes.
    always @(negedge clk) if(!reset) audio_control<=audio_control+1'b1;
    always @(posedge clk) if(!reset && dut.state==dut.LOAD && dut.tx_index==0) begin
        if(dut.kind==1)frame_count<=frame_count+1;
        if(dut.kind==2)status_count<=status_count+1;
        if(dut.kind==3)audio_count<=audio_count+1;
    end
    initial begin
        repeat(4) @(negedge clk);reset=0;
        repeat(300000) @(negedge clk);
        if(frame_count<2 || status_count<2 || audio_count<2)
            $fatal(1,"starved traffic: frames=%0d status=%0d audio=%0d",frame_count,status_count,audio_count);
        $display("PASS link fairness: screen, status and changing audio all progress");$finish;
    end
endmodule
