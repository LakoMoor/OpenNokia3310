`timescale 1ns/1ps
// ARM software reads the SIMI UART through the full MAD2 bus.
module core_sim_tb;
    reg clk=0,resetn=0;
    reg [16:0] keys=0;
    wire mem_valid,mem_write,mem_code,mem_error=0,lcd_wr,lcd_dc,unsupported_mmio;
    wire [31:0] mem_addr,mem_wdata;
    reg [31:0] mem_rdata;
    wire [3:0] mem_be;
    wire [7:0] lcd_data;
    wire [72:0] audio_control;
    wire [31:0] debug_pc,debug_sim_commands;
    wire [7:0] debug_sim_ins;
    reg [3:0] cycle=0;
    wire mem_ready=cycle[2:0]==5;
    integer writes=0;
    always #5 clk=~clk;
    nokia_core #(.CLK_HZ(16875000)) dut(.*);
    always_comb case(mem_addr & 32'hfffffffc)
        0:mem_rdata=32'he59f0048; // r0 = SIM control register
        4:mem_rdata=32'he3a010b2;
        8:mem_rdata=32'he5c01000; // STRB r1,[r0]
        12:mem_rdata=32'he2800003; // r0 = available-byte count
        16:mem_rdata=32'he5d01000;
        20:mem_rdata=32'he3510004;
        24:mem_rdata=32'h1afffffc; // wait until all four ATR bytes are buffered
        28:mem_rdata=32'he2400005; // r0 = receive register
        32:mem_rdata=32'he59f502c; // r5 = destination RAM
        36,44,52,60:mem_rdata=32'he5d01000;
        40,48,56,64:mem_rdata=32'he4851004;
        68:mem_rdata=32'heafffffe;
        80:mem_rdata=32'h00020039;
        84:mem_rdata=32'h00100000;
        default:mem_rdata=32'heafffffe;
    endcase
    always @(posedge clk) begin
        cycle<=cycle+1'b1;
        if(resetn) begin
            if(unsupported_mmio)$fatal(1,"unexpected MMIO during ARM SIM read");
            if(mem_valid && mem_ready && mem_write) begin
                if(mem_addr!==32'h100000+4*writes || mem_be!==4'hf)$fatal(1,"ATR destination address/lanes");
                case(writes)
                    0:if(mem_wdata!==32'h3b)$fatal(1,"ATR convention byte");
                    1:if(mem_wdata!==32'h60)$fatal(1,"ATR interface byte");
                    2,3:if(mem_wdata!==0)$fatal(1,"ATR trailing byte");
                    default:$fatal(1,"duplicate ATR store");
                endcase
                writes<=writes+1;
            end
        end
    end
    initial begin
        repeat(5)@(negedge clk);resetn=1;
        wait(writes==4);repeat(100)@(negedge clk);
        $display("PASS ARM SIMI: software activation, paced FIFO backlog, ATR reads and RAM stores");$finish;
    end
    initial begin #2000000;$fatal(1,"ARM SIM UART timeout, writes=%0d pc=%h",writes,debug_pc);end
endmodule
