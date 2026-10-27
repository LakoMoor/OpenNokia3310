`timescale 1ns/1ps
module virtual_dedicated_tb;
    reg clk=0,reset=1,start=0,request_block=0,ready=0;
    reg [21:0] frame_number=22'h123456;
    reg [9:0] arfcn=586;
    reg [5:0] bsic=27;
    wire valid,busy,done,last;
    wire [7:0] data;
    reg [7:0] captured[0:34];
    virtual_dedicated dut(.*);
    always #5 clk=~clk;
    task packet(input integer length);
        reg [7:0] held;
        @(negedge clk);start=1;@(negedge clk);start=0;
        for(integer i=0;i<length;i++)begin
            ready=0;held=data;
            repeat(3)begin @(posedge clk);#1;if(data!==held || !valid)$fatal(1,"dedicated stalled byte");end
            @(negedge clk);captured[i]=data;
            if(last!==(i==length-1))$fatal(1,"dedicated record length");
            ready=1;@(negedge clk);ready=0;
        end
        if(!done || busy)$fatal(1,"dedicated completion");
    endtask
    initial begin
        repeat(4)@(negedge clk);reset=0;packet(35);
        if({captured[0],captured[1],captured[2],captured[3]}!==32'h2180801b ||
           {captured[5],captured[6],captured[7]}!==24'h123456 ||
           {captured[8],captured[9]}!==16'd586 ||
           {captured[12],captured[13],captured[14]}!==24'h030301)$fatal(1,"SDCCH idle envelope");
        for(integer i=15;i<35;i++)if(captured[i]!='h2b)$fatal(1,"idle padding");
        request_block=1;packet(3);
        if({captured[0],captured[1],captured[2]}!==24'h018680)$fatal(1,"uplink block request");
        $display("PASS dedicated: SDCCH idle fill, frame/carrier, block request, stalls");$finish;
    end
    initial begin #20000;$fatal(1,"dedicated timeout");end
endmodule
