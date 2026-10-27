`timescale 1ns/1ps
module dsp_rx_tb;
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
    integer producer=7,cursor,records;
    reg [183:0] input_frame;
    task submit;
        reg [7:0] octet;
        integer offset;
        for(integer i=0;i<28;i++)begin
            if(i==0)octet=25;else if(i==1)octet='h1b;else if(i==2)octet=0;
            else if(i==3)octet='h80;else if(i<27)octet=input_frame[183-(i-4)*8-:8];else octet=0;
            offset=(producer*2+i)%164;
            memory[offset/4][(3-offset%4)*8+:8]=octet;
        end
        producer=(producer+14)%82;doorbell('h100a4,16'(producer));
    endtask
    task receive_rr(input [7:0] addr,ctrl);
        records=0;
        while(records<8)begin
            wait(fiq0);@(negedge clk);records++;
            cursor=memory['h1c8/4][15:0];
            if(ring_byte(cursor,1)=='h80 && ring_byte(cursor,12)==addr && ring_byte(cursor,13)==ctrl && ring_byte(cursor,14)==1)begin
                memory['h1c8/4][15:0]=memory['h1c8/4][31:16];return;
            end
            memory['h1c8/4][15:0]=memory['h1c8/4][31:16];
        end
        $fatal(1,"RR not received %h %h",addr,ctrl);
    endtask
    initial begin
        for(integer i=0;i<128;i++)memory[i]=0;
        memory['h1c8/4]=32'h00800080;
        memory[0]=32'h0c020000;memory[1]=0;memory[2]=32'h01008000;memory[3]=32'h024a0000;
        repeat(4)@(negedge clk);reset=0;doorbell('h100a4,7);
        wait(fiq0);@(negedge clk);memory['h1c8/4][15:0]=memory['h1c8/4][31:16];
        input_frame={23{8'h2b}};input_frame[183:160]=24'h030053;
        for(integer i=0;i<20;i++)input_frame[159-i*8-:8]=8'(i);
        submit();receive_rr('h01,'h21);
        if(dut.network.rx_message_valid)$fatal(1,"partial frame delivered as L3");
        input_frame[183:160]=24'h03120d;input_frame[159:136]=24'haabbcc;
        submit();receive_rr('h01,'h51);
        if(!dut.network.rx_message_valid || dut.network.rx_message_length!=23)$fatal(1,"assembled L3 missing");
        for(integer i=0;i<23;i++)
            if(dut.network.receiver.storage[i]!==8'(i<20 ? i : 170+(i-20)*17))$fatal(1,"DSP reassembly data %0d",i);
        // Lost acknowledgement: duplicate is re-ACKed despite retained L3 data.
        submit();receive_rr('h01,'h51);
        if(dut.network.rx_message_length!=23)$fatal(1,"duplicate changed retained message");
        $display("PASS DSP RX: segmented SEND_BLOCK, scheduled RR/PF, retained L3 and duplicate re-ACK");$finish;
    end
    initial begin #250000;$fatal(1,"DSP RX timeout");end
endmodule
