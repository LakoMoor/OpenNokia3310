`timescale 1ns/1ps
module dsp_tang_phase_tb;
    reg clk=0,reset=1,event_valid=0,m_ready=0;
    reg [31:0] event_address=0,m_rdata=0;
    reg [15:0] event_value=0;
    wire busy,fiq0,irq4,m_valid,m_write;
    wire [31:0] m_address,m_wdata,messages,network_packets;
    wire [3:0] m_be;
    wire [7:0] last_opcode,last_sub;
    longint unsigned reference_phase=0,reference_frames=0;
    localparam longint unsigned PERIOD=16875000*60;
    dsp_network #(.CLK_HZ(16875000),.ENABLE_NETWORK(1)) dut(.*);
    always #5 clk=~clk;
    initial begin
        repeat(4)@(negedge clk);reset=0;
        for(integer i=0;i<200000;i++)begin
            @(posedge clk);
            reference_phase+=13000;
            if(reference_phase>=PERIOD)begin reference_phase-=PERIOD;reference_frames++;end
            #1;
            if(dut.network.frame_phase!==reference_phase || dut.network.frame_number!==reference_frames)
                $fatal(1,"Tang timer mismatch at cycle %0d",i);
        end
        if(reference_frames<2)$fatal(1,"test did not cross frame boundaries");
        @(negedge clk);
        dut.network.grant_delay=1687500;
        dut.network.delay_count=4218750;
        #1;
        if(dut.network.grant_delay!==1687500 || dut.network.delay_count!==4218750)
            $fatal(1,"Tang delay reload was truncated");
        @(negedge clk);
        if(dut.network.grant_delay!==1687499 || dut.network.delay_count!==4218749)
            $fatal(1,"Tang delay countdown mismatch");
        dut.network.grant_delay=1;dut.network.delay_count=1;
        @(negedge clk);
        if(dut.network.grant_delay!==0 || dut.network.delay_count!==0 || !dut.network.grant_pending || !dut.network.pending)
            $fatal(1,"Tang delay completion did not schedule pending traffic");
        $display("PASS Tang GSM phase: 200000 clocks against independent 64-bit reference");$finish;
    end
    initial begin #3000000;$fatal(1,"Tang phase timeout");end
endmodule
