`timescale 1ns/1ps
module arm_bus_tb;
    reg clk=0,reset=1,valid=0,write=0;
    reg [31:0] address=0,wdata=0;
    reg [3:0] be=15;
    wire ready,error,lp_req,lp_we;
    wire [31:0] rdata,lp_wdata;
    wire [20:0] lp_addr;
    wire [3:0] lp_be;
    reg lp_ack=0,lp_rvalid=0;
    reg [31:0] lp_rdata=0;
    integer busy=0,accepted=0;
    reg reading=0;
    always #5 clk=~clk;
    arm_sdram_bus dut(.*);
    always @(posedge clk) begin
        lp_ack<=0;lp_rvalid<=0;
        if(busy!=0) begin
            busy<=busy-1;
            if(busy==1 && reading) lp_rvalid<=1;
        end else if(lp_req && !lp_ack) begin
            lp_ack<=1;busy<=3;accepted<=accepted+1;reading<=!lp_we;
            lp_rdata<=32'ha5000000|lp_addr;
            if(lp_we && (lp_wdata!==32'h12345678 || lp_be!==4'hc)) $fatal(1,"write lane payload");
        end
    end
    task access(input [31:0] a,input bit wr,input [31:0] expected,input bit err);
        @(negedge clk);valid=1;address=a;write=wr;wdata=32'h12345678;be=wr?4'hc:4'hf;
        wait(ready);#1;
        if(error!==err || (!wr && rdata!==expected)) $fatal(1,"bus addr=%h result=%h error=%b",a,rdata,error);
        @(negedge clk);valid=0;repeat(4) @(negedge clk);
    endtask
    initial begin
        repeat(3) @(negedge clk);reset=0;
        access(0,0,32'he51ff004,0);access(4,0,32'h00200040,0);
        access(32'h200040,0,32'ha5080010,0);
        access(0,0,32'ha5000000,0); // trampoline removed
        access(32'h100020,1,0,0);
        access(32'h400000,0,0,1);
        if(accepted!=3) $fatal(1,"duplicate/missing transactions: %0d",accepted);
        $display("PASS ARM SDRAM bridge: reset vector overlay, delayed reads/writes, BE strobes, abort");$finish;
    end
    initial begin #20000;$fatal(1,"timeout");end
endmodule
