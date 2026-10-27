`timescale 1ns/1ps
module dsp_link_reset_tb;
    reg clk=0,reset=1,event_valid=0;
    reg [31:0] event_address=0;
    reg [15:0] event_value=0;
    wire busy,fiq0,irq4,m_valid,m_write;
    wire [31:0] m_address,m_wdata,messages,network_packets;
    wire [3:0] m_be;
    wire [7:0] last_opcode,last_sub;
    reg [31:0] memory[0:127];
    reg [3:0] ticks=0;
    wire m_ready=ticks[1:0]==2;
    wire [31:0] m_rdata=memory[m_address[8:2]];
    integer interrupts=0;
    always #5 clk=~clk;
    dsp_network #(.CLK_HZ(10000),.ENABLE_NETWORK(1)) dut(.*);
    always @(posedge clk) begin
        ticks<=ticks+1'b1;
        if(fiq0)interrupts<=interrupts+1;
        if(m_valid && m_ready && m_write)
            for(integer i=0;i<4;i=i+1)
                if(m_be[i]) memory[m_address[8:2]][i*8+:8]<=m_wdata[i*8+:8];
    end
    task doorbell(input [31:0] address,input [15:0] value);
        wait(!busy);@(negedge clk);
        event_address=address;event_value=value;event_valid=1;
        @(negedge clk);event_valid=0;
        // MCU consumes responses concurrently; do not wait for all periodic
        // network work before releasing the first response's consumer cursor.
    endtask
    initial begin
        for(integer i=0;i<128;i++)memory[i]=0;
        memory['h1c8/4]=32'h00800080;
        memory[0]=32'h051b0080;memory[1]=32'h033f0100;
        repeat(4)@(negedge clk);reset=0;
        doorbell('h100a4,4);wait(messages==1);repeat(100)@(negedge clk);
        if(dut.network.ua_pending || interrupts || memory['h1c8/4]!==32'h00800080)
            $fatal(1,"unconfigured channel accepted SABM");
        memory[2]=32'h0c020000;memory[3]=0;memory[4]=32'h01008000;memory[5]=32'h024a0000;
        doorbell('h100a4,11);
        wait(memory['h1c8/4][31:16]==16'h82);repeat(4)@(negedge clk);
        memory['h1c8/4]=32'h00820082;
        wait(memory['h1c8/4][31:16]==16'h94);repeat(4)@(negedge clk);
        if(memory['h110/4]!==32'h0303012b)$fatal(1,"old unsolicited UA leaked into new link");
        memory['h1c8/4]=32'h00940094;
        memory[5][15:0]=16'h051b;memory[6]=32'h0080033f;memory[7]=32'h01000000;
        doorbell('h100a4,15);wait(dut.network.ua_pending);
        memory[7][15:0]=16'h0c02;memory[8]=0;memory[9]=32'h00000100;memory[10]=32'h8000024a;
        doorbell('h100a4,22);
        wait(memory['h1c8/4][31:16]==16'h96);repeat(4)@(negedge clk);
        if(dut.network.ua_pending)$fatal(1,"reconfiguration retained previous link UA");
        memory['h1c8/4]=32'h00960096;
        wait(memory['h1c8/4][31:16]==16'ha8);repeat(4)@(negedge clk);
        if(memory['h138/4]!==32'h0303012b)$fatal(1,"old UA sent after reconfiguration");
        $display("PASS DSP link reset: unsolicited SABM rejected, old pending UA discarded on reconfiguration");$finish;
    end
    initial begin #200000;$fatal(1,"link reset timeout");end
endmodule
