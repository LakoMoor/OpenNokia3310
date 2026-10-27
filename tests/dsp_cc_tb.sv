`timescale 1ns/1ps
module dsp_cc_tb;
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
    task receive_frame(input [7:0] addr,ctrl,pd,kind);
        records=0;
        while(records<16)begin
            wait(fiq0);@(negedge clk);records++;
            cursor=memory['h1c8/4][15:0];
            if(ring_byte(cursor,1)=='h80 && ring_byte(cursor,12)==addr && ring_byte(cursor,13)==ctrl &&
               ring_byte(cursor,15)==pd && ring_byte(cursor,16)==kind)begin
                memory['h1c8/4][15:0]=memory['h1c8/4][31:16];return;
            end
            memory['h1c8/4][15:0]=memory['h1c8/4][31:16];
        end
        $fatal(1,"CC frame not received %h %h %h %h",addr,ctrl,pd,kind);
    endtask
    task rr(input [7:0] ctrl);
        input_frame={23{8'h2b}};input_frame[183:160]={8'h01,ctrl,8'h01};submit();
    endtask
    initial begin
        for(integer i=0;i<128;i++)memory[i]=0;
        memory['h1c8/4]=32'h00800080;
        memory[0]=32'h0c020000;memory[1]=0;memory[2]=32'h01008000;memory[3]=32'h024a0000;
        repeat(4)@(negedge clk);reset=0;doorbell('h100a4,7);
        wait(fiq0);@(negedge clk);memory['h1c8/4][15:0]=memory['h1c8/4][31:16];
        input_frame={24'h013f41,128'h05247103301881080910103254769810,32'h2b2b2b2b};submit();
        receive_frame(1,'h73,5,'h24); // echo UA before cipher command
        receive_frame(3,0,6,'h35);
        input_frame={23{8'h2b}};input_frame[183:144]=40'h0120090632;submit();
        repeat(300)@(negedge clk);
        if(!dut.network.cm_active || dut.network.rx_message_valid)$fatal(1,"CM mode-complete ownership");
        input_frame={24'h012249,144'h03450404600200815e04812143f5a1150101,16'h2b2b};submit();
        receive_frame(3,'h42,'h83,2);
        if(dut.network.cc_peer.called_number!==160'h12345 || dut.network.cc_peer.called_digits!=5)
            $fatal(1,"DSP SETUP number decoding");
        rr('h41);receive_frame(3,'h44,'h83,1);
        rr('h61);receive_frame(3,'h46,'h83,7);
        if(dut.network.cc_peer.call_active)$fatal(1,"CC connected before phone acknowledgement");
        input_frame={23{8'h2b}};input_frame[183:144]=40'h018409030f;submit();
        repeat(500)@(negedge clk);
        if(!dut.network.cc_peer.call_active || dut.network.rx_message_valid || dut.network.cc_peer.failed)
            $fatal(1,"CONNECT ACK/piggyback L2 ACK did not establish virtual CC state");
        input_frame={23{8'h2b}};input_frame[183:120]=64'h018615036502e090;submit();
        receive_frame(3,'h88,'h83,'h2d);
        if(dut.network.cc_peer.call_active || dut.network.cc_peer.call_cleared)
            $fatal(1,"DISCONNECT must start clearing without prematurely finishing it");
        input_frame={23{8'h2b}};input_frame[183:144]=40'h01a809032a;submit();
        receive_frame(3,'haa,6,'h0d);
        if(dut.network.cc_peer.call_cleared)$fatal(1,"unacknowledged RR channel release cleared call");
        rr('hc1);repeat(300)@(negedge clk);
        if(!dut.network.cc_peer.call_cleared || dut.network.rx_message_valid || dut.network.cc_peer.failed)
            $fatal(1,"RELEASE COMPLETE and RR channel-release acknowledgement failed");
        input_frame={23{8'h2b}};input_frame[183:160]=24'h015301;submit();
        receive_frame(1,'h73,'h2b,'h2b);repeat(5)@(negedge clk);
        if(dut.network.cc_peer.call_active || dut.network.dedicated_enabled)
            $fatal(1,"released link retained active call");
        @(negedge clk);reset=1;repeat(3)@(negedge clk);
        if(dut.network.cc_peer.call_active)$fatal(1,"reset retained active call");
        $display("PASS DSP CC: CM/SETUP/connect/phone ACK -> DISCONNECT/RELEASE/COMPLETE/channel release/DISC");$finish;
    end
    initial begin #600000;$fatal(1,"DSP CC timeout");end
endmodule
