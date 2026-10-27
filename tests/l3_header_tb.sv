`timescale 1ns/1ps
module l3_header_tb;
    reg clk=0,reset=1,message_valid=0,message_sapi3=0,header_ready=0;
    reg [8:0] message_length=2;
    reg [7:0] read_data=0;
    wire message_ready,header_valid,sapi3,has_header;
    wire [7:0] read_address,discriminator,message_type;
    wire [8:0] length;
    reg [7:0] memory[0:255];
    integer releases=0;
    l3_header dut(.*);
    always #5 clk=~clk;
    always @(posedge clk)begin
        read_data<=memory[read_address];
        if(message_valid && message_ready)begin message_valid<=0;releases<=releases+1;end
    end
    initial begin
        memory[0]=6;memory[1]='h32;
        repeat(3)@(negedge clk);reset=0;message_valid=1;
        wait(header_valid);@(negedge clk);
        if(!has_header || discriminator!=6 || message_type!='h32 || sapi3 || length!=2)
            $fatal(1,"synchronous header read/metadata");
        repeat(8)@(negedge clk);
        if(!header_valid || message_ready || releases!=0)$fatal(1,"unaccepted message released");
        header_ready=1;repeat(3)@(negedge clk);header_ready=0;
        if(releases!=1 || header_valid)$fatal(1,"release handshake repeated/lost");
        message_sapi3=1;message_length=256;memory[0]=9;memory[1]=1;message_valid=1;
        wait(header_valid);@(negedge clk);
        if(!has_header || !sapi3 || length!=256 || discriminator!=9 || message_type!=1)
            $fatal(1,"SAPI/256-byte length or stale header");
        reset=1;@(negedge clk);message_valid=0;reset=0;
        if(header_valid || message_ready)$fatal(1,"reset retained old ownership");
        message_length=1;message_valid=1;
        wait(header_valid);@(negedge clk);
        if(has_header || discriminator!=0 || message_type!=0 || length!=1)
            $fatal(1,"short L3 message interpreted as header");
        header_ready=1;repeat(3)@(negedge clk);
        if(releases!=2)$fatal(1,"short message release");
        $display("PASS L3 header: synchronous reads, ownership/backpressure, SAPI/length, short/reset");$finish;
    end
    initial begin #10000;$fatal(1,"header timeout");end
endmodule
