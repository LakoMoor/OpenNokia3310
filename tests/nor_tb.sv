`timescale 1ns/1ps
module nor_tb;
    reg clk=0,reset=1,valid=0,write=0,code=0;
    reg [31:0] address=0,wdata=0;
    reg [3:0] be=15;
    wire ready,error,m_valid,m_write,m_code;
    wire [31:0] rdata,m_address,m_wdata;
    wire [3:0] m_be;
    reg [31:0] memory[0:16383];
    reg [3:0] ticks=0;
    wire m_ready=ticks[1:0]==2;
    wire m_error=0;
    wire [31:0] m_rdata=memory[m_address[15:2]];
    integer writes=0;
    always #5 clk=~clk;
    nor_bus dut(.*);
    always @(posedge clk) begin
        ticks<=ticks+1'b1;
        if(m_valid && m_ready && m_write) begin
            for(integer i=0;i<4;i=i+1) if(m_be[i]) memory[m_address[15:2]][i*8+:8]<=m_wdata[i*8+:8];
            writes<=writes+1;
        end
    end
    task transfer(input [31:0] a,input bit wr,input bit opcode,input [3:0] lanes,input [31:0] d,input [31:0] expected);
        @(negedge clk);valid=1;address=a;write=wr;code=opcode;be=lanes;wdata=d;
        wait(ready);#1;
        if(error || (!wr && rdata!==expected)) $fatal(1,"NOR addr=%h read=%h expected=%h",a,rdata,expected);
        @(negedge clk);valid=0;repeat(2) @(negedge clk);
    endtask
    task command(input [7:0] cmd);
        transfer(32'h3f2000,1,0,4'hc,{8'b0,cmd,16'b0},0);
    endtask
    initial begin
        for(integer i=0;i<16384;i=i+1) memory[i]=32'h12345678;
        memory[0]=32'haabbccdd;memory[2048]=32'hffffffff;
        repeat(4) @(negedge clk);reset=0;
        command(8'h90);
        transfer(32'h200000,0,0,4'hc,0,32'h00890000);
        transfer(32'h200002,0,0,4'h3,0,32'h00008890);
        transfer(32'h200000,0,1,4'hf,0,32'haabbccdd); // fetch bypasses ID
        command(8'hff);command(8'h40);
        transfer(32'h3f2000,1,0,4'hc,32'habcd0000,0);
        repeat(2) transfer(32'h3f2000,0,0,4'hf,0,0);
        transfer(32'h3f2000,0,0,4'hf,0,32'h80808080);
        command(8'hff);transfer(32'h3f2000,0,0,4'hf,0,32'habcdffff);
        command(8'h40);transfer(32'h3f2000,1,0,4'hc,32'hffff0000,0);
        command(8'hff);transfer(32'h3f2000,0,0,4'hf,0,32'habcdffff); // cannot set 0->1
        command(8'h40);transfer(32'h3f2002,1,0,4'h3,32'h00001234,0);
        command(8'hff);transfer(32'h3f2000,0,0,4'hf,0,32'habcd1234);
        command(8'h40);transfer(32'h3f2003,1,0,4'h1,32'h000000a5,0);
        command(8'hff);transfer(32'h3f2000,0,0,4'hf,0,32'habcd1224);
        command(8'h20);command(8'hd0);command(8'hff);
        transfer(32'h3f2000,0,0,4'hf,0,32'hffffffff);
        transfer(32'h3f3ffc,0,0,4'hf,0,32'hffffffff);
        transfer(32'h3f4000,0,0,4'hf,0,32'h12345678);
        if(writes!=2052) $fatal(1,"duplicate program/erase writes %0d",writes);
        $display("PASS NOR: ID, opcode bypass, busy/status, BE byte/halfword AND program, isolated 8 KiB erase");$finish;
    end
    initial begin #200000;$fatal(1,"NOR timeout");end
endmodule
