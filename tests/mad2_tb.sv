`timescale 1ns/1ps
module mad2_tb;
    reg clk=0,reset=1,valid=0,write=0;
    reg [7:0] address=0;
    reg [31:0] wdata=0;
    reg [3:0] byte_enable=8;
    reg [16:0] keys=0;
    reg dsp_fiq0=0,dsp_irq4=0;
    wire ready,irq,fiq,lcd_wr,lcd_dc,unsupported;
    wire [31:0] rdata;
    wire [31:0] sim_commands;
    wire [7:0] sim_last_ins;
    wire [7:0] lcd_data;
    always #5 clk=~clk;
    mad2_mmio #(.CLK_HZ(132220)) dut(.*);
    task wb(input [7:0] a,v);
        @(negedge clk); valid=1; write=1; address=a;
        byte_enable=4'b1000>>a[1:0]; wdata={24'b0,v}<<((3-a[1:0])*8);
        @(negedge clk); valid=0; write=0;
    endtask
    task rb(input [7:0] a,v);
        @(negedge clk); valid=1;write=0;address=a;byte_enable=4'b1000>>a[1:0];
        #1; if(((rdata>>((3-a[1:0])*8))&255)!==v) $fatal(1,"read %h expected %h got %h",a,v,rdata);
        @(negedge clk);valid=0;
    endtask
    initial begin
        repeat(3) @(negedge clk);reset=0;wait(ready);
        rb(1,1);rb(2,0);rb(3,0);rb(8'h80,0);
        // Exercise the shared shadow RAM port and its special read masks.
        for(integer a=128;a<160;a++)wb(8'(a),8'(a^8'h5a));
        for(integer a=128;a<160;a++)rb(8'(a),8'(a^8'h5a));
        wb(1,8'h93);rb(1,8'h93);wb(3,8'h62);rb(3,8'h62);
        wb(2,8'h10);rb(2,0);wb(2,1);rb(2,8'h53);
        wb(8'h18,8'h80);rb(8'h18,0);
        rb(0,8'ha1);rb(8'h6d,7);
        wb(8'h6e,8'h20);
        if(!lcd_wr || lcd_dc || lcd_data!==8'h20) $fatal(1,"LCD command byte lane");
        wb(8'h2e,8'ha5);
        if(!lcd_wr || !lcd_dc || lcd_data!==8'ha5) $fatal(1,"LCD data byte lane");
        wb(8'h28,8'hfe);keys=1;rb(8'h2a,8'h1b);
        wb(8'h0b,8'hfe); #1;if(!irq) $fatal(1,"key IRQ");
        wb(8'h09,1); #1;if(irq) $fatal(1,"IRQ ack");
        wb(8'h2d,8'h25);wb(8'h2c,8'h18);rb(8'h6c,8'hb2);
        wb(8'h2d,8'h25);wb(8'h2c,8'h00);wb(8'h2c,8'h38);
        wb(8'h2d,8'h25);wb(8'h2c,8'h10);rb(8'h6c,8'h26);
        // The high-byte selector immediately follows a read, without START.
        wb(8'h2c,8'h18);rb(8'h6c,8'hb0);
        // 16-bit native-endian read response uses the requested halfword lanes.
        @(negedge clk);address=8'h10;byte_enable=4'hc;valid=1;
        #1;if(rdata[31:16]!==dut.timer0 || rdata[15:0]!==0) $fatal(1,"halfword lane");
        @(negedge clk);valid=0;
        wb(8'h0f,8'hff);wb(8'h10,0);wb(8'h11,8'h34);rb(8'h11,8'h34);
        wb(8'h12,8'h12);wb(8'h13,8'h34);rb(8'h12,8'h12);rb(8'h13,8'h34);
        wb(8'h16,1);repeat(1400) @(negedge clk);
        if(!fiq) $fatal(1,"centisecond FIQ");
        wb(8'h16,3);#1;if(fiq) $fatal(1,"FIQ8 W1C");
        address=8'h36;valid=1;#1;if(unsupported) $fatal(1,"SIM transport must be implemented");
        address=8'h22;#1;if(!unsupported) $fatal(1,"unknown MMIO must be reported");
        $display("PASS MAD2: BE byte/halfword lanes, LCD, key IRQ, CCONT ADC, FIQ8, unsupported status");$finish;
    end
    initial begin #100000; $fatal(1,"timeout");end
endmodule
