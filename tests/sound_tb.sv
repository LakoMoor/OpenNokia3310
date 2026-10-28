`timescale 1ns/1ps
module sound_tb;
    reg clk=0,reset=1,write=0,test_start=0;
    reg [31:0] address=0,wdata=0;
    reg [3:0] be=0,volume=8;
    wire [72:0] control;
    wire audio_clk,speaker_p,speaker_n,test_active;
    wire [15:0] sample;
    integer rises=0,positive=0,negative=0;
    always #5 clk=~clk;
    nokia_audio_regs regs(.*);
    nokia_sound sound(.*);
    always @(posedge audio_clk) if(!reset)rises=rises+1;
    task put(input [31:0] a,d,input [3:0] mask);
        @(negedge clk);address=a;wdata=d;be=mask;write=1;
        @(negedge clk);write=0;
    endtask
    initial begin
        repeat(5)@(negedge clk);reset=0;
        put('h100ae,4000,3);put('h100b0,32'd3080<<16,12);put('h100b6,1,3);
        if(control[72:57]!=4000 || control[56:41]!=3080 || control[40:25]!=1)$fatal(1,"BE tone register lanes");
        repeat(40000)begin @(negedge clk);if($signed(sample)>0)positive++;if($signed(sample)<0)negative++;end
        if(positive==0 || negative==0 || rises<110 || rises>116)$fatal(1,"tone/sample clocks %0d %0d %0d",positive,negative,rises);
        volume=0;#1;if(sample!==0 || speaker_p || speaker_n)$fatal(1,"mute must silence all outputs");
        volume=8;put('h100b6,0,3);#1;if(sample!==0)$fatal(1,"amplitude zero must silence DSP tones");
        put('h2001c,32'h12340000,12);put('h20015,32'h00200000,4);
        if(control[24:9]!==16'h1234 || !control[0])$fatal(1,"buzzer registers");
        #1;if(sample!==0 || speaker_p || speaker_n)$fatal(1,"zero PUP volume must mute buzzer");
        put('h2001e,32'h0000ff00,2);
        #1;if($signed(sample)!=2040 && $signed(sample)!=-2040)$fatal(1,"full PUP volume scaling");
        put('h2001e,32'h00008000,2);
        #1;if($signed(sample)!=1024 && $signed(sample)!=-1024)$fatal(1,"half PUP volume scaling");
        put('h20015,0,4);
        #1;if(sample!==0 || speaker_p || speaker_n)$fatal(1,"disabled PUP must mute buzzer");
        @(negedge clk);test_start=1;@(negedge clk);test_start=0;
        if(!test_active)$fatal(1,"explicit output test");
        $display("PASS sound: BE DSP and buzzer registers, two tones, 48kHz clock, mute, output test");$finish;
    end
    initial begin #1000000;$fatal(1,"sound timeout");end
endmodule
