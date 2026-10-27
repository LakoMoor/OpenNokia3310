`timescale 1ns/1ps
module lapdm_rx_tb;
    reg clk=0,reset=1,link_reset=0,link_sapi3=0,frame_valid=0,message_ready=0;
    reg [183:0] frame={23{8'h2b}};
    reg [4:0] frame_length=23;
    reg [7:0] read_address=0;
    wire frame_ready,ack_valid,ack_sapi3,error,message_valid,message_sapi3;
    wire [2:0] ack_nr;
    wire [8:0] message_length;
    wire [7:0] read_data;
    lapdm_rx #(.MAX_L3(32)) dut(.*);
    always #5 clk=~clk;
    task send(input [23:0] header);
        @(negedge clk);frame[183:160]=header;frame_valid=1;
        @(negedge clk);frame_valid=0;
    endtask
    task consume;
        @(negedge clk);message_ready=1;@(negedge clk);message_ready=0;
    endtask
    initial begin
        repeat(4)@(negedge clk);reset=0;
        for(integer i=0;i<20;i++)frame[159-i*8-:8]=8'(i);
        send(24'h030053);
        if(!ack_valid || ack_nr!=1 || message_valid)$fatal(1,"first segment");
        send(24'h030053);if(!ack_valid || ack_nr!=1 || message_valid)$fatal(1,"duplicate segment");
        send(24'h030453);if(!error || ack_valid)$fatal(1,"out of sequence accepted");
        frame[159:144]=16'haabb;send(24'h0f0009);
        if(!message_valid || !message_sapi3 || message_length!=2 || ack_nr!=1)$fatal(1,"SAPI3 independent sequence");
        read_address=1;@(negedge clk);if(read_data!='hbb)$fatal(1,"SAPI3 data");
        send(24'h03020d);if(ack_valid || frame_ready)$fatal(1,"message backpressure");
        consume();frame[159:136]=24'hfafbfc;send(24'h03020d);
        if(!message_valid || message_sapi3 || message_length!=23 || ack_nr!=2)$fatal(1,"reassembled message");
        for(integer i=0;i<23;i++)begin
            read_address=8'(i);@(negedge clk);
            if(read_data!==8'(i<20 ? i : 250+i-20))$fatal(1,"reassembly byte %0d",i);
        end
        consume();send(24'h030253);if(!ack_valid || message_valid)$fatal(1,"final-segment duplicate");
        send(24'h030453);if(!ack_valid || error)$fatal(1,"new fragmented message");
        send(24'h030653);if(!error || ack_valid)$fatal(1,"reassembly overflow acknowledged");
        link_reset=1;@(negedge clk);link_reset=0;
        send(24'h030e01);if(!error || ack_valid)$fatal(1,"unseen pre-reset sequence treated as duplicate");
        frame_length=3;send(24'h030005);if(!error)$fatal(1,"truncated frame");
        frame_length=23;send(24'h070001);if(!error)$fatal(1,"unsupported SAPI");
        send(24'h030003);if(!error)$fatal(1,"empty nonfinal segment");
        for(integer i=0;i<9;i++)begin
            send({8'h03,8'((i%8)<<1),8'h01});
            if(!message_valid || !ack_valid || ack_nr!==3'((i+1)%8))$fatal(1,"N(S) modulo wrap %0d",i);
            consume();
        end
        $display("PASS LAPDm RX: independent SAPI reassembly, duplicates, ordering, overflow, backpressure/reset");$finish;
    end
    initial begin #20000;$fatal(1,"RX timeout");end
endmodule
