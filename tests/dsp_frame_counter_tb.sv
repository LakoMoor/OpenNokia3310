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
        repeat(4)@(negedge clk);reset=0;
        repeat(4000)begin @(posedge clk);verify();end
        // Exercise hyperframe and reduced-FN wrap without simulating 2.7M frames.
        @(negedge clk);dut.network.frame_number=2715647;dut.network.frame_t3=50;dut.network.reduced_fn=42431;
        repeat(30)begin @(posedge clk);verify();end
        if(dut.network.frame_number>10)$fatal(1,"hyperframe did not wrap");
        $display("PASS DSP frame counters: GSM modulo tracking and hyperframe wrap");$finish;
    end
    initial begin #100000;$fatal(1,"frame counter timeout");end
endmodule
