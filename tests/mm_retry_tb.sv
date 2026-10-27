`timescale 1ns/1ps
module mm_retry_tb;
    reg clk=0,reset=1,uplink_valid=0,downlink_ready=0;
    reg [183:0] uplink_frame={24'h033f49,144'h05087000f110ffff33080910103254769810,16'h2b2b};
    reg [4:0] uplink_length=23;
    reg [23:0] plmn=24'h00f110;
    reg [15:0] lac=1;
    wire downlink_valid,registered,failed,cm_active;
    wire [183:0] downlink_frame;
    mm_registration #(.RETRY_CYCLES(8),.MAX_RETRIES(2)) dut(.*);
    always #5 clk=~clk;
    task uplink(input [23:0] header);
        @(negedge clk);uplink_frame[183:160]=header;uplink_valid=1;
        @(negedge clk);uplink_valid=0;
    endtask
    task sent;
        @(negedge clk);downlink_ready=1;@(negedge clk);downlink_ready=0;
    endtask
    reg [183:0] original;
    initial begin
        repeat(4)@(negedge clk);reset=0;
        uplink_frame[159:144]=16'h0508;uplink(24'h033f49);
        original=downlink_frame;
        repeat(30)@(negedge clk);
        if(failed || !downlink_valid || downlink_frame!==original)$fatal(1,"output stalls must not start ACK timeout");
        sent();wait(downlink_valid);@(negedge clk);
        if(failed || registered || downlink_frame!==original)$fatal(1,"first retransmission changed payload/sequence");
        sent();wait(downlink_valid);@(negedge clk);
        if(downlink_frame!==original)$fatal(1,"second retransmission changed frame");
        sent();wait(failed);@(negedge clk);
        if(registered || downlink_valid)$fatal(1,"retry exhaustion claimed completion");
        reset=1;@(negedge clk);reset=0;
        uplink(24'h033f49);sent();wait(downlink_valid);@(negedge clk);
        // Delayed ACK cancels a queued retry without waiting for another slot.
        uplink(24'h032101);
        if(!downlink_valid || downlink_frame[175:168]!=2)$fatal(1,"recovery after dropped ACK");
        sent();wait(downlink_valid);@(negedge clk);
        if(downlink_frame[175:168]!=2)$fatal(1,"release retry sequence changed");
        uplink(24'h034101);
        if(!registered || failed)$fatal(1,"release ACK after retry");
        reset=1;@(negedge clk);reset=0;
        uplink_frame={24'h033f41,128'h05247103301881081910103254769810,32'h2b2b2b2b};
        uplink(24'h033f41);original=downlink_frame;
        sent();wait(downlink_valid);@(negedge clk);
        if(downlink_frame!==original || downlink_frame[183:136]!==48'h03000d063501)
            $fatal(1,"CM cipher retry changed frame");
        // Cipher complete may acknowledge the queued retransmission itself.
        uplink_frame[159:144]=16'h0632;uplink(24'h032009);
        if(downlink_valid || failed || registered || dut.state!=dut.CM_ACTIVE)
            $fatal(1,"piggyback mode-complete ACK failed after retry");
        $display("PASS MM retry: output stalls, identical retransmission, bounded failure, recovery");$finish;
    end
    initial begin #10000;$fatal(1,"retry timeout");end
endmodule
