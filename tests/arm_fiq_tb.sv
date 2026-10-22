`timescale 1ns/1ps
module arm_fiq_tb;
    reg clk=0,resetn=0,irq=0,fiq=0;
    wire valid,wr;
    wire [31:0] addr,wdata;
    wire [3:0] be;
    reg [31:0] rdata;
    reg [31:0] memory[0:4095];
    reg ready=1;
    integer handled=0;
    always #5 clk=~clk;
    arm7_probe dut(.*);
    always_comb rdata=memory[addr[13:2]];
    always @(posedge clk) if(valid && ready && wr) begin
        for(integer i=0;i<4;i=i+1) if(be[i]) memory[addr[13:2]][i*8+:8]<=wdata[i*8+:8];
        if(addr=='h2008) begin fiq<=0;handled<=handled+1;end
    end
    initial begin
        for(integer i=0;i<4096;i=i+1) memory[i]=32'heafffffe;
        memory[0]=32'hea00000e; // reset -> 40
        memory[7]=32'hea000037; // FIQ vector -> 100
        memory['h40/4]=32'he321f0d1; // masked FIQ mode
        memory['h44/4]=32'he3a0dc90; // fiq sp=9000
        memory['h48/4]=32'he321f01f; // system, interrupts enabled
        memory['h4c/4]=32'he3a00a01; // r0=1000
        memory['h50/4]=32'he3a01a02; // r1=2000
        memory['h54/4]=32'he5908000; // LDR r8,[r0], banked destination
        memory['h58/4]=32'he5818000; // STR r8,[r1]
        memory['h5c/4]=32'heafffffc; // loop loads/stores
        memory['h100/4]=32'he581e004; // save FIQ return link
        memory['h104/4]=32'he3a02001;
        memory['h108/4]=32'he5812008;
        memory['h10c/4]=32'he25ef004; // SUBS pc,lr,#4
        memory['h1000/4]=32'h12345678;
        memory['h2000/4]=0;memory['h2004/4]=0;memory['h2008/4]=0;
        repeat(5) @(negedge clk);resetn=1;
        wait(valid && !wr && addr=='h1000);
        ready=0;fiq=1;
        repeat(12) @(negedge clk);ready=1;
        wait(handled==1);
        repeat(200) @(negedge clk);
        if(memory['h2004/4]!==32'h5c) $fatal(1,"FIQ lost return link: %h",memory['h2004/4]);
        if(memory['h2000/4]!==32'h12345678) $fatal(1,"load committed into wrong register bank");
        if(handled!=1) $fatal(1,"duplicate FIQ");
        $display("PASS ARM FIQ: pending during stalled load, banked r8 commit, link and exception return");$finish;
    end
    initial begin #100000;$fatal(1,"FIQ test timeout");end
endmodule
