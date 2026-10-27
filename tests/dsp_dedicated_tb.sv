`timescale 1ns/1ps
module dsp_dedicated_tb;
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
        memory[0]=32'h0c020000;memory[1]=0;memory[2]=32'h01008000;memory[3]=32'h024a0000;
        repeat(4)@(negedge clk);reset=0;
        doorbell('h100a4,7);
        wait(memory['h1c8/4][31:16]==16'h82);repeat(4)@(negedge clk);
        if(memory['h100/4]!==32'h01890100 || interrupts!=1)$fatal(1,"SDCCH confirmation");
        memory['h1c8/4]=32'h00820082;
        wait(memory['h1c8/4][31:16]==16'h94);repeat(4)@(negedge clk);
        if(memory['h104/4]!==32'h21808000 || memory['h110/4]!==32'h0303012b || interrupts!=2)
            $fatal(1,"SDCCH idle fill must precede uplink request");
        if(memory['h108/4][23:0]%51!=0)$fatal(1,"SDCCH fill frame alignment");
        memory['h1c8/4]=32'h00940094;
        wait(memory['h1c8/4][31:16]==16'h96);repeat(4)@(negedge clk);
        if(memory['h128/4]!==32'h01868000 || interrupts!=3)$fatal(1,"uplink block request");
        memory['h1c8/4]=32'h00960096;
        memory[3][15:0]=16'h0c02;memory[4]=0;
        memory[5]=32'h00000100;memory[6]=32'h6000024a;
        doorbell('h100a4,14);
        wait(memory['h1c8/4][31:16]==16'h98);repeat(4)@(negedge clk);
        if(memory['h12c/4]!==32'h01890100 || interrupts!=4)$fatal(1,"leave SDCCH confirmation");
        memory['h1c8/4]=32'h00980098;
        repeat(6000)@(negedge clk);
        if(interrupts!=4 || memory['h1c8/4]!==32'h00980098)$fatal(1,"dedicated events continued after channel change");
        $display("PASS DSP dedicated: SDCCH configure, aligned fill then uplink request, queue/FIQ");$finish;
    end
    initial begin #100000;$fatal(1,"DSP dedicated timeout");end
endmodule
