`timescale 1ns/1ps
module cdc_fifo_tb;
    reg wclk=0,rclk=0,wrst=1,rrst=1,wvalid=0,rready=0;
    reg [8:0] wdata=0;
    wire wready,rvalid;
    wire [8:0] rdata;
    integer received=0;
    always #7 wclk=~wclk;
    always #11 rclk=~rclk;
    async_lcd_fifo dut(.*);
    always @(posedge rclk) if(!rrst && rvalid && rready) begin
        if(rdata!==received[8:0]) $fatal(1,"FIFO order: got %h expected %0d",rdata,received);
        received<=received+1;
    end
    initial begin
        repeat(5) @(negedge wclk);wrst=0;rrst=0;
        for(integer i=0;i<128;i=i+1) begin
            @(negedge wclk);wvalid=1;wdata=i;
            do @(posedge wclk); while(!wready);
            @(negedge wclk);wvalid=0;
        end
        wait(received==128);repeat(4) @(negedge rclk);
        if(rvalid) $fatal(1,"FIFO did not empty");
        $display("PASS LCD CDC FIFO: asynchronous clocks, full stall, wraparound, ordered delivery");$finish;
    end
    initial begin #1000;rready=1;end
    initial begin #15000;$fatal(1,"timeout received=%0d",received);end
endmodule
