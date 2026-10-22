`timescale 1ns/1ps
module status_tb;
    reg clk=0,reset=1;
    reg [7:0] flags=8'h53;
    reg [31:0] address=32'h00200040;
    reg [15:0] lcd_count=16'h1234;
    wire tx;
    localparam DIV=10;
    reg [7:0] data[0:9];
    reg [7:0] checksum;
    uart_status #(.CLK_HZ(4000),.BAUD(400)) dut(.*);
    always #5 clk=~clk;
    task byte_rx(output reg [7:0] value);
        @(negedge tx);repeat(DIV/2) @(posedge clk);#1;
        if(tx) $fatal(1,"UART status start");
        for(integer j=0;j<8;j=j+1) begin repeat(DIV) @(posedge clk);#1;value[j]=tx;end
        repeat(DIV) @(posedge clk);#1;if(!tx) $fatal(1,"UART status stop");
    endtask
    initial begin
        repeat(4) @(negedge clk);reset=0;
        for(integer i=0;i<10;i=i+1) byte_rx(data[i]);
        if({data[0],data[1],data[2],data[3],data[4],data[5],data[6],data[7],data[8]}!==72'h4e3353002000401234)
            $fatal(1,"status snapshot / endian");
        checksum=0;for(integer i=0;i<10;i=i+1) checksum^=data[i];
        if(checksum!=0) $fatal(1,"status checksum");
        $display("PASS status: UART bit timing, packet snapshot, big-endian values, checksum");$finish;
    end
    initial begin #100000;$fatal(1,"status timeout");end
endmodule
