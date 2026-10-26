`timescale 1ns/1ps
module virtual_cell_tb;
    reg clk=0,reset=1,start=0,bcch=0,ready=0;
    reg [1:0] si_kind=0;
    reg channel_confirm=0;
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
        si_kind=1;launch();si_kind=2;receive(35);
        if(captured[12]!='h59 || captured[14]!='h1a || captured[31]!='hff)$fatal(1,"SI2 header/NCC");
        for(integer i=15;i<31;i++)if(captured[i]!=0)$fatal(1,"SI2 neighbour bitmap");
        for(integer i=32;i<35;i++)if(captured[i]!=0)$fatal(1,"SI2 RACH");
        plmn=24'h00f110;lac=16'h1234;si_kind=2;launch();receive(35);
        if(captured[12]!='h31 || captured[14]!='h1c ||
           {captured[15],captured[16],captured[17]}!==24'h00f110 ||
           {captured[18],captured[19]}!==16'h1234)$fatal(1,"SI4 length/LAI");
        for(integer i=20;i<25;i++)if(captured[i]!=0)$fatal(1,"SI4 selection/RACH");
        for(integer i=25;i<35;i++)if(captured[i]!='h2b)$fatal(1,"SI4 rest octets");
        channel_confirm=1;launch();channel_confirm=0;receive(12);
        if(captured[0]!=10 || captured[1]!='h89 || captured[2]!='h50 || captured[4]!=1 ||
           {captured[8],captured[9]}!==16'd586)$fatal(1,"channel confirm envelope");
        launch();@(negedge clk);reset=1;@(negedge clk);if(busy || valid || done)$fatal(1,"reset cancels pending packet");
        $display("PASS virtual cell: SCH/SI3/SI2/SI4 MDI envelopes, configured identity, backpressure, reset");$finish;
    end
    initial begin #20000;$fatal(1,"timeout");end
endmodule
