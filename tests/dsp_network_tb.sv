`timescale 1ns/1ps
module dsp_network_tb;
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
    dsp_network #(.CLK_HZ(1000),.ENABLE_NETWORK(1)) dut(.*);
    always @(posedge clk) begin
        ticks<=ticks+1'b1;
        if(fiq0) interrupts<=interrupts+1;
        if(m_valid && m_ready && m_write)
            for(integer i=0;i<4;i=i+1)
                if(m_be[i]) memory[m_address[8:2]][i*8+:8]<=m_wdata[i*8+:8];
    end
    task doorbell(input [31:0] address,input [15:0] value);
        wait(!busy);@(negedge clk);
        event_address=address;event_value=value;event_valid=1;
        @(negedge clk);event_valid=0;
        wait(!busy);repeat(2) @(negedge clk);
    endtask
    initial begin
        for(integer i=0;i<128;i=i+1) memory[i]=0;
        // Start at the last D2M slot: the two-word response must wrap.
        memory['h1c8/4]=32'h00e300e3;
        memory[0]=32'h02700d00; // len=2, local command 0D self-test
        repeat(4) @(negedge clk);reset=0;
        doorbell('h100a4,2);
        if(messages!=1 || last_opcode!='h70 || last_sub!='h0d)
            $fatal(1,"M2D descriptor parsing");
        if(memory['h1c4/4][15:0]!==16'h0274 || memory['h100/4][31:16]!==16'h0d00)
            $fatal(1,"D2M response header/payload or wrap");
        if(memory['h1c8/4]!==32'h008100e3 || memory['ha4/4][15:0]!==16'h0002 || interrupts!=1)
            $fatal(1,"producer/consumer ownership or notification");
        // Next local command, echoed MSID seed. Firmware advances consumer.
        memory['h1c8/4]=32'h00810081;
        memory[1]=32'h107013aa;memory[2]=32'hbbccddee;
        memory[3]=32'h11223344;memory[4]=32'h55667788;
        memory[5]=32'h99000000;
        doorbell('h100a4,11);
        if(messages!=2 || memory['h100/4][15:0]!==16'h1074 ||
            memory['h104/4]!==32'h340e00aa || memory['h108/4]!==32'hbbccddee)
            $fatal(1,"MSID command reply");
        if(memory['h1c8/4][15:0]!==16'h0081)
            $fatal(1,"DSP changed MCU consumer");
        // The real observed opcode 56 triggers a device-side SCH response.
        memory['h1c8/4]=32'h008a008a;
        memory[5][15:0]=16'h0256;memory[6]=32'h02000000;
        doorbell('h100a4,13);
        wait(memory['h1c8/4][31:16]==16'h90);repeat(4)@(negedge clk);
        if(memory['h1c8/4][15:0]!==16'h8a || memory['h114/4]!==32'h0a804000 ||
           memory['h11c/4][31:16]!==16'h024a || interrupts!=3)
            $fatal(1,"SCH transport or queue ownership");
        // Firmware drains SCH; periodic SI3 must then reach the same queue.
        memory['h1c8/4]=32'h00900090;
        wait(memory['h1c8/4][31:16]==16'ha2);repeat(4)@(negedge clk);
        if(memory['h120/4][31:16]!==16'h2180 || memory['h12c/4]!==32'h49061b00 || interrupts!=4)
            $fatal(1,"BCCH/SI3 follow-up");
        memory['h1c8/4]=32'h00a200a2;
        wait(memory['h1c8/4][31:16]==16'hb4);repeat(4)@(negedge clk);
        if(memory['h150/4]!==32'h59061a00 || interrupts!=5)
            $fatal(1,"BCCH/SI2 follow-up");
        memory['h1c8/4]=32'h00b400b4;
        wait(memory['h1c8/4][31:16]==16'hc6);repeat(4)@(negedge clk);
        if(memory['h174/4]!==32'h31061c00 || memory['h178/4]!==32'hf1100001 || interrupts!=6)
            $fatal(1,"BCCH/SI4 follow-up and LAI");
        memory['h1c8/4]=32'h00c600c6;
        wait(memory['h1c8/4][31:16]==16'hd8);repeat(4)@(negedge clk);
        if(memory['h198/4]!==32'h49061b00 || interrupts!=7 || network_packets!=5)
            $fatal(1,"BCCH cycle must return to SI3");
        memory['h1c8/4]=32'h00d800d8;
        memory[6][15:0]=16'h0c02;memory[7]=0;
        memory[8]=32'h00000100;memory[9]=32'h5000024a;
        doorbell('h100a4,20);
        wait(memory['h1c8/4][31:16]==16'hda);repeat(4)@(negedge clk);
        if(memory['h1b0/4]!==32'h01890100 || interrupts!=8)
            $fatal(1,"observed channel configure must receive confirmed-channel record");
        memory['h1c8/4]=32'h00da00da;
        wait(memory['h1c8/4][31:16]==16'h88);repeat(4)@(negedge clk);
        if(memory['h1b4/4][31:16]!==16'h2180 || memory['h1c0/4]!==32'h59061a00 || interrupts!=9)
            $fatal(1,"channel confirmation must preserve periodic SI2 and wrap");
        memory['h1c8/4]=32'h00880088;
        memory[10]=32'h0c020000;memory[11]=0;
        memory[12]=32'h0100c100;memory[13]=32'h024a0000;
        doorbell('h100a4,27);
        wait(memory['h1c8/4][31:16]==16'h8a);repeat(4)@(negedge clk);
        if(memory['h110/4]!==32'h01890000 || interrupts!=10)
            $fatal(1,"traffic confirm token must correlate with channel parity");
        $display("PASS DSP network: original local transport, observed search opcode, SCH/SI3/SI2/SI4 queue delivery and FIQ");$finish;
    end
    initial begin #100000;$fatal(1,"DSP timeout");end
endmodule
