`timescale 1ns/1ps
module lapdm_tx_case #(parameter SAPI=0)(output reg done=0);
    reg clk=0,reset=1,request_valid=0,request_more=0,downlink_ready=0,uplink_valid=0;
    reg [159:0] request_data=160'h0305040360a1805e04812143f52b2b2b2b2b2b2b2b;
    reg [4:0] request_length=13,uplink_length=23;
    reg [2:0] receive_nr=3;
    reg [183:0] uplink_frame={23{8'h2b}};
    wire request_ready,request_error,acknowledged,failed,downlink_valid;
    wire [183:0] downlink_frame;
    lapdm_tx #(.SAPI(SAPI),.INITIAL_NS(1),.RETRY_CYCLES(8),.MAX_RETRIES(1)) dut(.*);
    always #5 clk=~clk;
    task request;
        @(negedge clk);request_valid=1;@(negedge clk);request_valid=0;
    endtask
    task sent;
        @(negedge clk);downlink_ready=1;@(negedge clk);downlink_ready=0;
    endtask
    task ack(input [2:0] nr,input bit piggyback=0,input bit wrong_sapi=0);
        @(negedge clk);uplink_frame={23{8'h2b}};
        uplink_frame[183:176]=8'(((wrong_sapi ? (SAPI==0 ? 3 : 0) : SAPI)<<2)|1);
        uplink_frame[175:168]={nr,4'b0000,!piggyback};
        uplink_frame[167:160]=piggyback ? 9 : 1;
        uplink_frame[159:144]=16'h0632;uplink_valid=1;
        @(negedge clk);uplink_valid=0;
    endtask
    reg [183:0] original;
    initial begin
        repeat(3)@(negedge clk);reset=0;
        request_length=21;request();if(!request_error || downlink_valid)$fatal(1,"oversize payload accepted");
        request_length=0;request_more=1;request();if(!request_error)$fatal(1,"zero-byte continuation");
        request_length=13;request_more=0;request();original=downlink_frame;
        if(!downlink_valid || downlink_frame[183:176]!=8'((SAPI<<2)|3) ||
           downlink_frame[175:160]!==16'h6235 || downlink_frame[159:56]!==request_data[159:56] ||
           downlink_frame[55:0]!=={7{8'h2b}})$fatal(1,"I-frame construction/padding");
        receive_nr=7;request_data=0;repeat(12)@(negedge clk);
        if(!downlink_valid || failed || downlink_frame!==original)$fatal(1,"output stall changed frame or timed out");
        ack(2);if(!downlink_valid || acknowledged)$fatal(1,"unsent frame acknowledged");
        sent();ack(2,0,1);if(acknowledged)$fatal(1,"other SAPI acknowledged frame");
        uplink_length=4;ack(2,1);
        if(acknowledged)$fatal(1,"truncated piggyback I-frame acknowledged output");
        uplink_length=23;
        wait(downlink_valid);@(negedge clk);
        if(downlink_frame!==original)$fatal(1,"retry changed sequence/NR/data");
        ack(2,1);if(!acknowledged || !request_ready || failed)$fatal(1,"late piggyback ACK failed");
        // Exercise sequence wrap and reject the last transaction's duplicate ACK.
        for(integer i=2;i<10;i++)begin
            request();if(downlink_frame[171:169]!==3'(i))$fatal(1,"N(S) wrap");
            sent();ack(3'(i));if(acknowledged)$fatal(1,"duplicate N(R) acknowledged new frame");
            ack(3'(i+1));if(!acknowledged || !request_ready)$fatal(1,"correct RR acknowledgement");
        end
        request();sent();wait(downlink_valid);sent();wait(failed);@(negedge clk);
        if(downlink_valid || request_ready || acknowledged)$fatal(1,"retry exhaustion reported success");
        reset=1;@(negedge clk);reset=0;
        if(failed || !request_ready)$fatal(1,"link reset did not recover");
        done=1;
    end
endmodule
module lapdm_tx_tb;
    wire a,b;
    lapdm_tx_case #(.SAPI(0)) sapi0(a);
    lapdm_tx_case #(.SAPI(3)) sapi3(b);
    initial begin wait(a && b);$display("PASS LAPDm TX: SAPI 0/3 framing, stalls/retry, ACK validation, wrap, failure/reset");$finish;end
    initial begin #20000;$fatal(1,"TX timeout");end
endmodule
