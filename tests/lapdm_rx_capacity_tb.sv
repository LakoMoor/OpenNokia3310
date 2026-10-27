`timescale 1ns/1ps
module lapdm_rx_capacity_tb;
    reg clk=0,reset=1,link_reset=0,link_sapi3=0,frame_valid=0,message_ready=0;
    reg [183:0] frame={23{8'h2b}};
    reg [4:0] frame_length=23;
    reg [7:0] read_address=0;
    wire frame_ready,ack_valid,ack_sapi3,ack_final,error,message_valid,message_sapi3;
    wire [2:0] ack_nr;
    wire [8:0] message_length;
    wire [7:0] read_data;
    lapdm_rx dut(.*);
    always #5 clk=~clk;
    task segment(input integer seq,input integer base,input integer count,input bit more);
        @(negedge clk);frame={23{8'h2b}};
        frame[183:160]={8'h03,8'((seq%8)<<1),8'((count<<2)|(more ? 3 : 1))};
        for(integer i=0;i<count;i++)frame[159-i*8-:8]=8'(base+i);
        if(!frame_ready)$fatal(1,"receiver unexpectedly busy");
        frame_valid=1;@(negedge clk);frame_valid=0;
        if(frame_ready)$fatal(1,"receiver released frame before serial copy");
        while(!ack_valid && !error)@(negedge clk);
        if(error || ack_nr!==3'((seq+1)%8))$fatal(1,"segment ACK/sequence");
    endtask
    initial begin
        repeat(4)@(negedge clk);reset=0;
        for(integer i=0;i<12;i++)segment(i,i*20,20,1);
        segment(12,240,16,0);
        if(!message_valid || message_sapi3 || message_length!=256)$fatal(1,"full-length message");
        for(integer i=0;i<256;i++)begin
            read_address=8'(i);@(negedge clk);
            if(read_data!==8'(i))$fatal(1,"full-length byte %0d",i);
        end
        message_ready=1;@(negedge clk);message_ready=0;
        for(integer i=0;i<12;i++)segment(i+13,i*20,20,1);
        segment(25,240,16,1);
        // The next byte exceeds 256 and must be rejected without ACK.
        @(negedge clk);frame={23{8'h2b}};frame[183:152]=32'h030405aa;frame_valid=1;
        @(negedge clk);frame_valid=0;
        if(!error || ack_valid || message_valid)$fatal(1,"overflow must not commit");
        $display("PASS LAPDm RX: 256-byte reassembly, sequence wrap and overflow rejection");$finish;
    end
    initial begin #100000;$fatal(1,"capacity timeout");end
endmodule
