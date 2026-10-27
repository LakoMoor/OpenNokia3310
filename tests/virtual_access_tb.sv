`timescale 1ns/1ps
module virtual_access_tb;
    reg clk=0,reset=1,start=0,grant=0,ready=0;
    reg [7:0] ra=8'h16;
    reg [21:0] request_fn=12345;
    reg [9:0] arfcn=586;
    reg [5:0] bsic=5;
    wire valid,busy,done,last;
    wire [7:0] data;
    reg [7:0] captured[0:34];
    virtual_access dut(.*);
    always #5 clk=~clk;
    task packet(input integer length);
        reg [7:0] held;
        reg [7:0] saved_ra;
        reg [21:0] saved_fn;
        reg [9:0] saved_arfcn;
        reg [5:0] saved_bsic;
        saved_ra=ra;saved_fn=request_fn;saved_arfcn=arfcn;saved_bsic=bsic;
        @(negedge clk);start=1;@(negedge clk);start=0;
        ra=0;request_fn=0;arfcn=0;bsic=0; // in-flight fields must be latched
        for(integer i=0;i<length;i++)begin
            ready=0;held=data;
            repeat(3)begin @(posedge clk);#1;if(!valid || data!==held)$fatal(1,"stalled access packet changed");end
            @(negedge clk);captured[i]=data;
            if(last!==(i==length-1))$fatal(1,"access packet length");
            ready=1;@(negedge clk);ready=0;
        end
        if(!done || busy)$fatal(1,"access completion");
        ra=saved_ra;request_fn=saved_fn;arfcn=saved_arfcn;bsic=saved_bsic;
    endtask
    initial begin
        repeat(4)@(negedge clk);reset=0;
        packet(10);
        if({captured[0],captured[1],captured[2],captured[3],captured[4],captured[5]}!==48'h088416003039)
            $fatal(1,"RA_INFO reference/FN");
        for(integer i=6;i<10;i++)if(captured[i]!=0)$fatal(1,"RA_INFO padding");
        grant=1;packet(35);
        if(captured[0]!=33 || captured[1]!='h80 || captured[2]!='h60 ||
           {captured[12],captured[13],captured[14]}!==24'h2d063f ||
           {captured[16],captured[17],captured[18]}!==24'h41a24a ||
           {captured[19],captured[20],captured[21]}!==24'h164875)
            $fatal(1,"Immediate Assignment channel or RA/FN tuple");
        for(integer i=24;i<35;i++)if(captured[i]!='h2b)$fatal(1,"IA rest padding");
        // One complete reduced-FN period must preserve the request-reference IE.
        request_fn=12345+42432;packet(35);
        if({captured[20],captured[21]}!==16'h4875)$fatal(1,"reduced FN wrap");
        @(negedge clk);start=1;@(negedge clk);start=0;reset=1;
        @(negedge clk);if(busy || valid || done)$fatal(1,"access reset");
        $display("PASS virtual access: RA_INFO, correlated Immediate Assignment, reduced FN, stalls");$finish;
    end
    initial begin #20000;$fatal(1,"access timeout");end
endmodule
