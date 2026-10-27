`timescale 1ns/1ps
module lapdm_ua_tb;
    reg clk=0,reset=1,start=0;
    reg [183:0] frame={23{8'h2b}};
    reg [4:0] frame_length=23;
    wire done,accepted;
    wire [183:0] response;
    wire [4:0] information_length;
    lapdm_ua dut(.*);
    always #5 clk=~clk;
    task issue(input bit expected);
        @(negedge clk);start=1;@(negedge clk);start=0;
        if(!done || accepted!==expected)$fatal(1,"UA validation %h",frame[183:160]);
    endtask
    initial begin
        repeat(4)@(negedge clk);reset=0;
        frame[183:160]=24'h033f51; // SABM P=1, 20 information bytes
        for(integer i=0;i<20;i++)frame[159-i*8-:8]=8'(i);
        issue(1);
        if(response[183:160]!==24'h017351 || information_length!=20 || response[159:0]!==frame[159:0])
            $fatal(1,"contention resolution must echo exact information");
        frame[183:160]=24'h0f2f01;issue(1);
        if(response[183:160]!==24'h0d6301 || response[159:0]!=={20{8'h2b}})$fatal(1,"SAPI3 UA without poll");
        frame[183:160]=24'h035301;issue(1);
        if(response[183:160]!==24'h017301)$fatal(1,"DISC UA");
        frame[183:160]=24'h033f55;issue(0); // 21 bytes cannot fit
        frame[183:160]=24'h033f11;frame_length=6;issue(0); // truncated 4-byte info
        frame_length=23;frame[183:160]=24'h023f01;issue(0); // EA
        frame[183:160]=24'h233f01;issue(0); // unsupported LPD/spare bits
        frame[183:160]=24'h033f03;issue(0); // segmented
        frame[183:160]=24'h033f00;issue(0); // EL
        frame[183:160]=24'h030001;issue(0); // I frame is not SABM
        frame[183:160]=24'h035305;issue(0); // DISC cannot carry data
        @(negedge clk);reset=1;@(negedge clk);
        if(done || accepted)$fatal(1,"UA reset");
        $display("PASS LAPDm UA: SABM echo, SAPI/PF, DISC, truncation, invalid framing, reset");$finish;
    end
    initial begin #10000;$fatal(1,"UA timeout");end
endmodule
