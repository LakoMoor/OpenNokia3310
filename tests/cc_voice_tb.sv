`timescale 1ns/1ps
module cc_voice_tb;
    reg clk=0,reset=1,header_valid=0,header_sapi3=0,header_complete=1,downlink_ready=0,uplink_valid=0;
    reg [8:0] header_length=18;
    reg [7:0] header_pd=3,header_type='h45,read_data=0;
    reg [2:0] receive_nr=2;
    reg [183:0] uplink_frame={23{8'h2b}};
    reg [4:0] uplink_length=23;
    wire header_ready,downlink_valid,call_active,call_cleared,failed;
    wire [7:0] read_address,called_type;
    wire [183:0] downlink_frame;
    wire [159:0] called_number;
    wire [5:0] called_digits;
    reg [7:0] memory[0:255];
    reg [143:0] setup_data=144'h03450404600200815e04812143f5a1150101;
    cc_voice #(.RETRY_CYCLES(16),.MAX_RETRIES(1)) dut(.*);
    always #5 clk=~clk;
    always @(posedge clk)begin
        read_data<=memory[read_address];
        if(header_ready)header_valid<=0;
    end
    task fresh;
        @(negedge clk);reset=1;header_valid=0;uplink_valid=0;downlink_ready=0;
        repeat(3)@(negedge clk);reset=0;
        header_length=18;header_pd=3;header_type='h45;header_sapi3=0;
        for(integer i=0;i<256;i++)memory[i]='h80;
        for(integer i=0;i<18;i++)memory[i]=setup_data[143-i*8-:8];
    endtask
    task offer;
        @(negedge clk);header_valid=1;
    endtask
    task ack(input [2:0] nr);
        @(negedge clk);uplink_frame={23{8'h2b}};
        uplink_frame[183:160]={8'h01,nr,4'b0000,1'b1,8'h01};uplink_valid=1;
        @(negedge clk);uplink_valid=0;
    endtask
    task response(input [2:0] ns,input [7:0] kind);
        wait(downlink_valid);@(negedge clk);
        if(downlink_frame[183:176]!=3 || downlink_frame[175:168]!={receive_nr,1'b0,ns,1'b0} ||
           downlink_frame[167:144]!=={8'h09,8'h83,kind})$fatal(1,"CC frame sequence/TI/type");
        downlink_ready=1;@(negedge clk);downlink_ready=0;ack(3'(ns+1'b1));
    endtask
    task rejected;
        offer();wait(failed);@(negedge clk);
        if(header_ready || !header_valid || downlink_valid || call_active)$fatal(1,"invalid SETUP consumed/connected");
    endtask
    task established;
        fresh();receive_nr=2;offer();response(1,2);response(2,1);response(3,7);
        header_length=2;header_type='h0f;offer();wait(call_active);@(negedge clk);
        header_type='h65;header_length=5;memory[2]=2;memory[3]='he0;memory[4]='h90;receive_nr=4;
    endtask
    reg [183:0] held;
    initial begin
        fresh();offer();wait(downlink_valid);@(negedge clk);held=downlink_frame;
        if(called_number!==160'h12345 || called_digits!=5 || called_type!='h81)
            $fatal(1,"original v6.39 number decoding");
        repeat(25)@(negedge clk);
        if(downlink_frame!==held || failed || call_active)$fatal(1,"stalled CC output mutated/timed out");
        ack(2);if(!downlink_valid)$fatal(1,"unsent CC response acknowledged");
        response(1,2);response(2,1);response(3,7);
        repeat(5)@(negedge clk);
        if(call_active || failed)$fatal(1,"LAPDm ACK alone established call");
        header_length=2;header_pd='h13;header_type='h4f;offer();repeat(5)@(negedge clk);
        if(header_ready || call_active)$fatal(1,"wrong TI CONNECT ACK accepted");
        @(negedge clk);header_pd=3;
        wait(call_active);@(negedge clk);
        if(header_valid || failed)$fatal(1,"CONNECT ACK ownership/active state");
        header_length=5;header_type='h65;memory[2]=2;memory[3]='he0;memory[4]='h90;receive_nr=4;offer();
        response(4,'h2d);repeat(5)@(negedge clk);
        if(call_active || call_cleared || failed)$fatal(1,"RELEASE ACK alone cleared call");
        header_length=2;header_type='h2a;header_pd='h13;offer();repeat(5)@(negedge clk);
        if(header_ready || downlink_valid)$fatal(1,"wrong TI RELEASE COMPLETE accepted");
        @(negedge clk);header_pd=3;receive_nr=5;
        wait(downlink_valid);@(negedge clk);
        if(downlink_frame[183:136]!==48'h03aa0d060d00 || call_cleared)
            $fatal(1,"channel release framing/sequence/order");
        downlink_ready=1;@(negedge clk);downlink_ready=0;
        ack(5);if(call_cleared)$fatal(1,"wrong channel-release ACK cleared call");
        ack(6);repeat(3)@(negedge clk);
        if(!call_cleared || call_active || failed || header_valid)$fatal(1,"clearing did not complete");
        established();header_length=4;rejected();
        established();memory[2]=3;rejected();
        established();memory[3]='h60;rejected();
        established();header_length=7;memory[5]='h15;memory[6]=3;rejected();
        fresh();header_length=13;rejected(); // TLV runs past message end
        fresh();memory[13]='hee;rejected(); // invalid BCD
        fresh();memory[11]='hf1;rejected(); // filler before final octet
        fresh();memory[4]='h61;rejected(); // unsupported data bearer
        fresh();memory[10]=1;rejected(); // extended address not implemented
        fresh();memory[2]=5;rejected(); // no mandatory bearer capability
        fresh();header_length=257;rejected(); // read-address wrap forbidden
        fresh();header_length=23;memory[18]='h5e;memory[19]=3;memory[20]='h81;memory[21]='h21;memory[22]='h43;rejected();
        fresh();header_length=256;offer();wait(downlink_valid);@(negedge clk);
        if(failed || called_number!==160'h12345)$fatal(1,"bounded 256-byte SETUP scan");
        // Dropped CC acknowledgement must eventually fail without connecting.
        downlink_ready=1;@(negedge clk);downlink_ready=0;
        wait(downlink_valid);@(negedge clk);downlink_ready=1;@(negedge clk);downlink_ready=0;
        wait(failed);if(call_active)$fatal(1,"failed link established call");
        $display("PASS CC voice: original SETUP/BCD, reliable handshake, TI/CONNECT ACK, invalid/bounds/failure");$finish;
    end
    initial begin #200000;$fatal(1,"CC timeout");end
endmodule
