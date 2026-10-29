`timescale 1ns/1ps
module sim_pace_tb;
    localparam integer RELOAD=16875000/960;
    reg clk=0,reset=1,valid=0,write=0;
    reg [7:0] address=0,wdata=0;
    wire [7:0] rdata,last_ins;
    wire fiq;
    wire [31:0] commands;
    sim_card #(.CLK_HZ(16875000)) dut(.*);
    always #5 clk=~clk;
    initial begin
        repeat(4) @(negedge clk);reset=0;
        valid=1;write=1;address='h39;wdata='hb2;
        @(negedge clk);valid=0;write=0;
        if(dut.pace !== RELOAD) $fatal(1,"activation reload: %0d",dut.pace);
        repeat(RELOAD) @(negedge clk);
        if(dut.visible_ptr!==0 || dut.pace!==0) $fatal(1,"first byte visible too early");
        @(negedge clk);
        if(dut.visible_ptr!==1 || dut.pace!==RELOAD-1) $fatal(1,"first byte timing");
        valid=1;write=0;address='h37;
        @(negedge clk);valid=0;
        repeat(RELOAD-2) @(negedge clk);
        if(dut.visible_ptr!==1 || dut.pace!==0) $fatal(1,"second byte visible too early");
        @(negedge clk);
        if(dut.visible_ptr!==2 || dut.pace!==RELOAD-1) $fatal(1,"second byte timing");
        // UART reception must continue while the MCU has not read byte two.
        repeat(RELOAD) @(negedge clk);
        if(dut.visible_ptr!==3 || dut.visible_count!==2)$fatal(1,"SIM UART must buffer bytes independently of MCU reads");
        address='h37;valid=1;#1;if(rdata!==8'h60)$fatal(1,"queued ATR byte two");
        @(negedge clk);#1;if(rdata!==0)$fatal(1,"back-to-back SIM FIFO read must prefetch next byte");
        @(negedge clk);valid=0;
        $display("PASS SIM pace: exact activation and successive ATR byte intervals at Tang clock");$finish;
    end
    initial begin #1000000;$fatal(1,"SIM pace timeout");end
endmodule
