`timescale 1ns/1ps
module flash_boot_tb;
    reg clk=0,reset=1,mem_ready=0,flash_miso=0;
    wire done,req,flash_cs_n,flash_clk,flash_mosi;
    wire [20:0] addr;
    wire [31:0] wdata;
    wire [31:0] first_word;
    reg [3:0] clocks=0;
    wire ack=req && clocks[2:0]==3;
    integer count=0,bits=0;
    integer selections=0,deselections=0;
    always @(negedge flash_cs_n)if(!reset)selections++;
    always @(posedge flash_cs_n)if(!reset)begin
        deselections++;
        if(count!=8)$fatal(1,"CS must stay asserted through every inter-word DMA stall");
    end
    reg [31:0] command=0,payload;
    always #5 clk=~clk;
    flash_boot #(.WORDS(5),.CLEAR_WORDS(3),.DEST_BASE(21'd16)) dut(.*);
    always @(posedge clk) begin
        clocks<=clocks+1'b1;
        if(req && ack) begin
            if(count<3) begin
                if(addr!==count || wdata!==0) $fatal(1,"RAM clear");
            end else if(addr!==(16+count-3) || wdata!==(32'h10203040+count-3))
                $fatal(1,"DMA word %0d address=%h data=%h",count,addr,wdata);
            count<=count+1;
        end
    end
    always @(posedge flash_clk) if(!flash_cs_n) begin
        if(bits<32) begin
            command={command[30:0],flash_mosi};
            if(bits==31 && command!==32'h03200000) $fatal(1,"SPI command/address %h",command);
        end
        bits=bits+1;
    end
    always @(negedge flash_clk) if(!flash_cs_n && bits>=32) begin
        payload=32'h10203040+(bits-32)/32;
        flash_miso=payload[31-(bits-32)%32];
    end
    initial begin
        repeat(4) @(negedge clk);reset=0;
        repeat(10) @(negedge clk);if(req || done) $fatal(1,"must wait for SDRAM init");
        mem_ready=1;wait(done);@(negedge clk);
        if(count!=8 || !flash_cs_n || req || flash_clk) $fatal(1,"completion");
        if(first_word!==32'h10203040) $fatal(1,"first ROM word diagnostic");
        if(selections!=1 || deselections!=1)$fatal(1,"one continuous SPI transaction required");
        $display("PASS flash DMA: clear, SPI 03/address, big-endian words, backpressure, completion");$finish;
    end
    initial begin #20000;$fatal(1,"timeout");end
endmodule
