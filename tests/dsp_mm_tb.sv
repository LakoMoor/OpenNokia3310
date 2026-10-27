`timescale 1ns/1ps
module dsp_mm_tb;
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
    function automatic [7:0] ring_byte(input integer cursor,offset);
        integer slot,lane;
        slot=cursor+offset/2;if(slot>='he4)slot-=100;
        lane=(slot%2)*2+offset%2;
        ring_byte=8'(memory[slot/2]>>(24-lane*8));
    endfunction
    integer stage=0,records=0,cursor;
    initial begin
        for(integer i=0;i<128;i++)memory[i]=0;
        memory['h1c8/4]=32'h00800080;
        memory[0]=32'h0c020000;memory[1]=0;memory[2]=32'h01008000;memory[3]=32'h024a0000;
        repeat(4)@(negedge clk);reset=0;
        doorbell('h100a4,7);
        wait(fiq0);@(negedge clk);memory['h1c8/4][15:0]=memory['h1c8/4][31:16];
        memory[3][15:0]=16'h1c1b;memory[4]=32'h0080033f;memory[5]=32'h0d050811;
        for(integer i=6;i<11;i++)memory[i]=32'h2b2b2b2b;
        doorbell('h100a4,22);
        while(stage<3 && records<12)begin
            wait(fiq0);@(negedge clk);records++;
            cursor=memory['h1c8/4][15:0];
            if(ring_byte(cursor,1)=='h80 && ring_byte(cursor,12)==1 && ring_byte(cursor,13)=='h73)begin
                if(stage!=0)$fatal(1,"unexpected UA ordering");stage=1;
            end
            if(ring_byte(cursor,1)=='h80 && ring_byte(cursor,12)==3 && ring_byte(cursor,13)==0)begin
                if(stage!=1 || ring_byte(cursor,15)!=5 || ring_byte(cursor,16)!=2 ||
                   ring_byte(cursor,17)!=0 || ring_byte(cursor,18)!='hf1 || ring_byte(cursor,19)!='h10 ||
                   ring_byte(cursor,20)!=0 || ring_byte(cursor,21)!=1)$fatal(1,"LU Accept before UA or wrong LAI");
                stage=2;
            end else if(ring_byte(cursor,1)=='h80 && ring_byte(cursor,12)==3 && ring_byte(cursor,13)==2)begin
                if(stage!=2 || ring_byte(cursor,15)!=6 || ring_byte(cursor,16)!='h0d)$fatal(1,"release without LU acknowledgement");
                stage=3;
            end
            memory['h1c8/4][15:0]=memory['h1c8/4][31:16];
            if(stage==2 && ring_byte(cursor,13)==0 && ring_byte(cursor,12)==3)begin
                memory[11]=32'h051b0080;memory[12]=32'h03210100;
                doorbell('h100a4,26);
            end
        end
        if(stage!=3)$fatal(1,"MM sequence did not complete");
        memory[13]=32'h051b0080;memory[14]=32'h03410100;
        doorbell('h100a4,30);repeat(100)@(negedge clk);
        if(!dut.network.mm_peer.registered)$fatal(1,"MM peer completed before/without release acknowledgement");
        $display("PASS DSP MM: SEND_BLOCK SABM -> UA -> LU Accept -> RR -> release -> RR through queue");$finish;
    end
    initial begin #200000;$fatal(1,"DSP MM timeout");end
endmodule
