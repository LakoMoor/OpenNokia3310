`timescale 1ns/1ps
module dsp_frame_counter_tb;
    reg clk=0,reset=1,event_valid=0,m_ready=0;
    reg [31:0] event_address=0,m_rdata=0;
    reg [15:0] event_value=0;
    wire busy,fiq0,irq4,m_valid,m_write;
    wire [31:0] m_address,m_wdata,messages,network_packets;
    wire [3:0] m_be;
    wire [7:0] last_opcode,last_sub;
    dsp_network #(.CLK_HZ(1300),.ENABLE_NETWORK(1)) dut(.*);
    always #5 clk=~clk;
    task verify;
        #1;
        if(dut.network.frame_t3!==6'(dut.network.frame_number%51) ||
           dut.network.reduced_fn!==16'(dut.network.frame_number%42432))
            $fatal(1,"frame counter drift at FN=%0d",dut.network.frame_number);
    endtask
    initial begin
        for(integer f=0;f<2715648;f++)begin
            integer t,off,expected;
            t=f%51;
            if(t<=6)off=6;else if(t<=12)off=12;else if(t<=16)off=16;
            else if(t<=22)off=22;else if(t<=26)off=26;else if(t<=32)off=32;
            else if(t<=36)off=36;else if(t<=42)off=42;else if(t<=46)off=46;else off=57;
            expected=(f-t+off)%2715648;
            if(dut.network.next_ccch(22'(f),6'(t))!==22'(expected))$fatal(1,"CCCH mismatch at %0d",f);
        end
        repeat(4)@(negedge clk);reset=0;
        repeat(4000)begin @(posedge clk);verify();end
        // Exercise hyperframe and reduced-FN wrap without simulating 2.7M frames.
        @(negedge clk);dut.network.frame_number=2715647;dut.network.frame_t3=50;dut.network.reduced_fn=42431;
        repeat(30)begin @(posedge clk);verify();end
        if(dut.network.frame_number>10)$fatal(1,"hyperframe did not wrap");
        @(negedge clk);dut.network.frame_phase=65000;
        @(posedge clk);#1;
        if(dut.network.frame_phase!==0)$fatal(1,"exact threshold must wrap to zero");
        @(negedge clk);dut.network.frame_phase=64999;
        @(posedge clk);#1;
        if(dut.network.frame_phase!==77999)$fatal(1,"phase below threshold wrapped early");
        $display("PASS DSP frame counters: GSM modulo tracking and hyperframe wrap");$finish;
    end
    initial begin #100000;$fatal(1,"frame counter timeout");end
endmodule
