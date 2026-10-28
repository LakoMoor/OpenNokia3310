`timescale 1ns/1ps
module dsp_tb;
    reg clk=0,reset=1,event_valid=0;
    reg [31:0] event_address=0;
    reg [15:0] event_value=0;
    wire busy,fiq0,irq4,m_valid,m_write;
    wire [31:0] m_address,m_wdata,messages;
    wire [3:0] m_be;
    wire [7:0] last_opcode,last_sub;
    wire channel_valid,rach_valid,uplink_valid,message_valid;
    wire [4:0] uplink_length;
    wire [7:0] uplink_logch;
    wire [183:0] uplink_frame;
    wire [47:0] rach_payload;
    wire [7:0] channel_token,channel_logch;
    reg [31:0] memory[0:127];
    reg [3:0] ticks=0;
    wire m_ready=ticks[1:0]==2;
    wire [31:0] m_rdata=memory[m_address[8:2]];
    integer interrupts=0;
    reg [31:0] observed_messages=0;
    always #5 clk=~clk;
    dsp_service #(.CLK_HZ(1000)) dut(.*);
    always @(posedge clk) begin
        if (reset) observed_messages<=0;
        else begin
            if (message_valid !== (messages != observed_messages))
                $fatal(1,"DSP message pulse differs from counter change");
            observed_messages<=messages;
        end
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
    task put_byte(input integer address,input [7:0] value);
        memory[address/4][(3-(address%4))*8+:8]=value;
    endtask
    function automatic [7:0] get_byte(input integer address);
        return memory[address/4][(3-(address%4))*8+:8];
    endfunction
    initial begin
        for(integer i=0;i<128;i=i+1) memory[i]=0;
        // Start at the last D2M slot: the two-word response must wrap.
        memory['h1c8/4]=32'h01e301e3;
        memory[0]=32'h02700d00; // len=2, local command 0D self-test
        repeat(4) @(negedge clk);reset=0;
        fork
            doorbell('h100a4,2);
            begin
                wait(dut.state==dut.RING_ISSUE);
                repeat(40) @(negedge clk);
                if(memory['h1c8/4]!==32'h01e301e3 || interrupts!=0 || memory['h1c4/4]!=0)
                    $fatal(1,"out-of-range producer was truncated into a valid ring slot");
                memory['h1c8/4]=32'h00e300e3;
            end
        join
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
        // One producer notification covers two descriptors. Neither may vanish.
        memory[5][15:0]=16'h0055;
        memory[6]=32'h02560305;
        doorbell('h100a4,14);
        if(messages!=4 || last_opcode!='h56 || last_sub!=3 || memory['ha4/4][15:0]!=14)
            $fatal(1,"batched M2D descriptors were skipped");
        memory[7]=32'h0155aa00; // odd payload plus halfword padding
        memory[8]=32'h00560000;
        doorbell('h100a4,17);
        if(messages!=6 || last_opcode!='h56 || last_sub!=0 || memory['ha4/4][15:0]!=17)
            $fatal(1,"odd descriptor padding or zero-length stale payload");
        // Security command 16 returns a fixed unlocked record and echoes 24
        // seed bytes. Check the whole long response, not just its header.
        memory['h1c8/4]=32'h008a008a;
        put_byte(34,26);put_byte(35,'h70);put_byte(36,'h16);
        for(integer i=1;i<26;i=i+1) put_byte(36+i,8'(i+8'h40));
        doorbell('h100a4,31);
        if(messages!=7 || memory['h1c8/4][31:16]!==16'h00a5 ||
           get_byte('h114)!==8'h34 || get_byte('h115)!==8'h74)
            $fatal(1,"long security reply header or cursor");
        for(integer i=0;i<52;i=i+1) begin
            logic [191:0] record_data;
            logic [7:0] expected_byte;
            record_data=192'hffffffffff0f0000009800000000000000000000087c0000;
            expected_byte=0;
            if(i==0)expected_byte='h35;
            else if(i==1)expected_byte='h32;
            else if(i==2)expected_byte=1;
            else if(i>=4 && i<28)expected_byte=record_data[191-(i-4)*8-:8];
            else if(i>=28)expected_byte=8'(i-26+8'h40);
            if(get_byte('h116+i)!==expected_byte)
                $fatal(1,"long security reply byte %0d",i);
        end
        // The heartbeat must saturate while its outgoing ring is blocked,
        // then resume only after the MCU releases the ring.
        wait(dut.heartbeat==4000);
        repeat(100) @(negedge clk);
        if(dut.heartbeat!==4000 || !busy) $fatal(1,"heartbeat must remain at deadline while ring is occupied");
        memory['h1c8/4]=32'h00a500a5;
        wait(!busy);
        if(dut.heartbeat==4000) $fatal(1,"heartbeat did not clear after reply");
        $display("PASS DSP: wait-state transport, M2D parse, D2M wrap, cursor ownership, MSID seed");$finish;
    end
    initial begin #100000;$fatal(1,"DSP timeout");end
endmodule
