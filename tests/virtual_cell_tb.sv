`timescale 1ns/1ps
module virtual_cell_tb;
    reg clk=0,reset=1,start=0,bcch=0,ready=0;
    reg [23:0] plmn=24'h00f110;
    reg [15:0] lac=16'h1234,cell_id=16'h5678;
    reg [9:0] arfcn=586;
    reg [5:0] bsic=27;
    reg [21:0] frame_number=22'h234567;
    wire valid,busy,done,last;
    wire [7:0] data;
    reg [7:0] captured[0:34];
    integer count;
    always #5 clk=~clk;
    virtual_cell dut(.*);
    task receive(input integer length);
        reg [7:0] held;
        count=0;
        while(busy)begin
            @(negedge clk);ready=0;held=data;
            repeat(3)begin @(posedge clk);#1;if(!valid || data!==held)$fatal(1,"unstable stalled packet");end
            @(negedge clk);captured[count]=data;
            if(last!==(count==length-1))$fatal(1,"incorrect record length");
            ready=1;@(posedge clk);#1;count++;
        end
        @(negedge clk);ready=0;
        if(count!=length || !done)$fatal(1,"packet completion");
    endtask
    task launch;
        @(negedge clk);start=1;@(negedge clk);start=0;
    endtask
    initial begin
        repeat(4)@(negedge clk);reset=0;
        launch();receive(12);
        if(captured[0]!=10 || captured[1]!='h80 || captured[2]!='h40 || captured[3]!=27 ||
           {captured[5],captured[6],captured[7]}!==24'h234567 || {captured[8],captured[9]}!==16'd586)
            $fatal(1,"SCH DSP envelope");
        bcch=1;launch();plmn=24'hffffff;lac=0;cell_id=0; // in-flight fields must be latched
        receive(35);
        if(captured[0]!=33 || captured[2]!='h50 || captured[12]!='h49 || captured[13]!=6 || captured[14]!='h1b ||
           {captured[15],captured[16]}!==16'h5678 || {captured[17],captured[18],captured[19]}!==24'h00f110 ||
           {captured[20],captured[21]}!==16'h1234)$fatal(1,"SI3 identity/LAI");
        for(integer i=31;i<35;i++)if(captured[i]!='h2b)$fatal(1,"SI3 rest octets");
        launch();@(negedge clk);reset=1;@(negedge clk);if(busy || valid || done)$fatal(1,"reset cancels pending packet");
        $display("PASS virtual cell: SCH/SI3 MDI envelopes, configured identity, backpressure, reset");$finish;
    end
    initial begin #20000;$fatal(1,"timeout");end
endmodule
