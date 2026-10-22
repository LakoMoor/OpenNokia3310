`timescale 1ns/1ps
module uart_tb;
    reg clk=0,reset=1,rx=1;
    wire wr,dc;
    wire [7:0] data;
    wire [16:0] keys;
    integer writes=0;
    always #5 clk=~clk;
    uart_lcd #(.CLK_HZ(1_152_000)) dut(.*);
    task byte_send(input [7:0] b,input bit stopbit);
        @(negedge clk);rx=0;repeat(10) @(negedge clk);
        for(integer i=0;i<8;i=i+1) begin rx=b[i];repeat(10) @(negedge clk);end
        rx=stopbit;repeat(10) @(negedge clk);rx=1;repeat(12) @(negedge clk);
    endtask
    task packet(input [7:0] op,b);
        byte_send(8'ha5,1);byte_send(op,1);byte_send(b,1);
    endtask
    always @(posedge clk) if(wr) begin
        if(writes==0 && (dc || data!==8'h20)) $fatal(1,"command");
        if(writes==1 && (!dc || data!==8'ha5)) $fatal(1,"data magic must not resync payload");
        if(writes>1) $fatal(1,"unexpected UART write");
        writes<=writes+1;
    end
    initial begin
        repeat(5) @(negedge clk);reset=0;
        byte_send(8'h22,1);packet(0,8'h20);packet(1,8'ha5);
        packet(2,8'h42);packet(3,8'h18);packet(4,1);
        if(keys!==17'h11842 || writes!=2) $fatal(1,"remote state");
        packet(8'hff,0);
        byte_send(8'ha5,0);byte_send(0,1);byte_send(8'hff,1);
        repeat(1152100) @(negedge clk);
        if(keys!==0 || writes!=2) $fatal(1,"framing or timeout release");
        $display("PASS UART: commands, payload magic, keys, invalid opcode/stop bit, timeout");$finish;
    end
endmodule
