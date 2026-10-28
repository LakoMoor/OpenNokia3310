`timescale 1ns/1ps
module link_resume_tb;
    reg clk=0,reset=1,stream_enabled=0,lcd_wr=0,lcd_dc=0;
    reg [7:0] lcd_data=0,flags=0;
    reg [31:0] address=0;
    reg [15:0] lcd_count=0;
    reg [72:0] audio_control={16'd4000,16'd0,16'd1,16'd0,8'd0,1'b0};
    reg [3:0] volume=5;
    reg menu_open=0,gray=0;
    reg [2:0] menu_row=0;
    wire tx;
    integer audio_count=0;
    always #5 clk=~clk;
    nokia_link #(.CLK_HZ(115200),.BAUD(11520)) dut(.*);
    always @(posedge clk) if(!reset && dut.state==dut.LOAD && dut.tx_index==0 && dut.kind==3) audio_count<=audio_count+1;
    initial begin
        repeat(4)@(negedge clk);reset=0;
        repeat(510)@(negedge clk);stream_enabled=1;
        wait(audio_count==1);repeat(2500)@(negedge clk);
        stream_enabled=0;repeat(20)@(negedge clk);stream_enabled=1;
        wait(audio_count==2);
        if(dut.audio_latch!==audio_control) $fatal(1,"reconnect lost unchanged audio state");
        $display("PASS link reconnect: unchanged device audio state is sent to a new host");$finish;
    end
    initial begin #3000000;$fatal(1,"link reconnect timeout");end
endmodule
