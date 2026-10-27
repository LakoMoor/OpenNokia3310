`timescale 1ns/1ps
module dsp_access_tb;
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
        if(dut.network.next_ccch(22'd102,6'd0)!=108 || dut.network.next_ccch(22'd108,6'd6)!=108 ||
           dut.network.next_ccch(22'd109,6'd7)!=114 || dut.network.next_ccch(22'd152,6'd50)!=159 ||
           dut.network.next_ccch(22'd2715647,6'd50)!=6)$fatal(1,"CCCH block alignment/hyperframe wrap");
        for(integer i=0;i<128;i++)memory[i]=0;
        memory['h1c8/4]=32'h00e000e0;
        memory[0]=32'h060c0001;memory[1]=32'h16003039;
        repeat(4)@(negedge clk);reset=0;
        doorbell('h100a4,4);
        wait(memory['h1c8/4][31:16]==16'h81);repeat(4)@(negedge clk);
        if(memory['h1c0/4]!==32'h08841600 || memory['h1c4/4]!==32'h30390000 || interrupts!=1)
            $fatal(1,"RACH must report actual RA/FN before assignment");
        // Leave the MCU consumer unchanged across the grant deadline.
        repeat(200)@(negedge clk);
        if(memory['h1c8/4]!==32'h008100e0 || interrupts!=1)$fatal(1,"grant overwrote unread RA_INFO");
        memory['h1c8/4]=32'h00810081;
        wait(memory['h1c8/4][31:16]==16'h93);repeat(4)@(negedge clk);
        if(memory['h100/4][15:0]!==16'h2180 || memory['h110/4]!==32'h3f004102 ||
           memory['h114/4]!==32'h4a164875 || interrupts!=2 || network_packets!=2)
            $fatal(1,"correlated Immediate Assignment queue delivery");
        // The actual ROM also uses relative-FN mode; cross its reduced period.
        memory['h1c8/4]=32'h00930093;
        memory[2]=32'h060c0000;memory[3]=32'h166c0000;
        force dut.network.frame_number=22'd42420;
        force dut.network.reduced_fn=16'd42420;
        force dut.network.frame_t3=6'd39;
        doorbell('h100a4,8);
        release dut.network.frame_number;
        release dut.network.reduced_fn;
        release dut.network.frame_t3;
        wait(memory['h1c8/4][31:16]==16'h98);repeat(4)@(negedge clk);
        if(memory['h124/4][15:0]!==16'h0884 || memory['h128/4]!==32'h16000060)
            $fatal(1,"relative RACH FN must wrap 42420+108 to 96");
        memory['h1c8/4]=32'h00980098;
        wait(memory['h1c8/4][31:16]==16'haa);repeat(4)@(negedge clk);
        if(memory['h144/4][31:16]!==16'h05b2 || interrupts!=4)
            $fatal(1,"relative FN grant reference mismatch");
        // A second RACH before grant supplies an updated transmitted reference.
        @(negedge clk);reset=1;repeat(4)@(negedge clk);reset=0;
        memory['h1c8/4]=32'h00800080;
        memory[0]=32'h060c0001;memory[1]=32'h16003039;
        doorbell('h100a4,4);
        wait(memory['h1c8/4][31:16]==16'h85);repeat(4)@(negedge clk);
        memory['h1c8/4]=32'h00850085;
        memory[2]=32'h060c0001;memory[3]=32'h1700303a;
        doorbell('h100a4,8);
        wait(memory['h1c8/4][31:16]==16'h8a);repeat(4)@(negedge clk);
        if(memory['h10c/4]!==32'h1700303a)$fatal(1,"updated RA_INFO lost");
        memory['h1c8/4]=32'h008a008a;
        wait(memory['h1c8/4][31:16]==16'h9c);repeat(4)@(negedge clk);
        if(memory['h128/4][31:16]!==16'h4896 || memory['h124/4][7:0]!==8'h17)
            $fatal(1,"grant must use latest RA/FN rather than stale request");
        $display("PASS DSP access: actual RACH decode, RA_INFO before grant, unread queue protection, correlated FN");$finish;
    end
    initial begin #100000;$fatal(1,"DSP access timeout");end
endmodule
