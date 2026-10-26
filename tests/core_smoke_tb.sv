`timescale 1ns/1ps
module core_smoke_tb;
    reg clk=0,resetn=0;
    reg [16:0] keys=0;
    wire mem_valid,mem_write,mem_code,mem_error=0,lcd_wr,lcd_dc,unsupported_mmio;
    wire [31:0] mem_addr,mem_wdata;
    reg [31:0] mem_rdata;
    wire [3:0] mem_be;
    wire [7:0] lcd_data;
    wire [72:0] audio_control;
    wire [31:0] debug_pc;
    reg [3:0] cycle=0;
    wire mem_ready=cycle[2:0]==5;
    integer writes=0;
    reg [31:0] held_addr;
    reg held=0;
    always #5 clk=~clk;
    nokia_core dut(.*);
    always_comb case(mem_addr & 32'hfffffffc)
        0: mem_rdata=32'he59f0028; // LDR r0,[pc,#0x28] : 0x2006e
        4: mem_rdata=32'he3a01020; // MOV r1,#0x20
        8: mem_rdata=32'he5c01000; // STRB r1,[r0]
        12:mem_rdata=32'he3a0100c;
        16:mem_rdata=32'he5c01000;
        20:mem_rdata=32'he2400040; // SUB r0,r0,#0x40 : LCD data port
        24:mem_rdata=32'he3a010a5;
        28:mem_rdata=32'he5c01000;
        32:mem_rdata=32'he3a03041;
        36:mem_rdata=32'he12fff13; // BX r3, enter Thumb at 0x40
        48:mem_rdata=32'h0002006e;
        64:mem_rdata=32'h215a7001; // Thumb MOV r1,#0x5a ; STRB r1,[r0]
        68:mem_rdata=32'he7fe46c0; // Thumb B . ; NOP
        default:mem_rdata=32'heafffffe;
    endcase
    always @(posedge clk) begin
        cycle<=cycle+1'b1;
        if(resetn) begin
            if(held && (!mem_valid || mem_addr!==held_addr)) $fatal(1,"memory request changed while stalled");
            held<=mem_valid && !mem_ready;
            held_addr<=mem_addr;
            if(unsupported_mmio) $fatal(1,"unexpected MMIO");
            if(lcd_wr) begin
                case(writes)
                    0: if(lcd_dc || lcd_data!==8'h20) $fatal(1,"ARM command 1");
                    1: if(lcd_dc || lcd_data!==8'h0c) $fatal(1,"ARM command 2");
                    2: if(!lcd_dc || lcd_data!==8'ha5) $fatal(1,"ARM byte data");
                    3: if(!lcd_dc || lcd_data!==8'h5a) $fatal(1,"Thumb byte data");
                    default:$fatal(1,"duplicate LCD write");
                endcase
                writes<=writes+1;
            end
        end
    end
    initial begin
        repeat(5) @(negedge clk);resetn=1;
        wait(writes==4); repeat(100) @(negedge clk);
        $display("PASS ARM/MAD2: BE ARM->Thumb interworking, wait states, exactly four LCD writes");$finish;
    end
    initial begin #100000; $fatal(1,"CPU timeout, writes=%0d",writes);end
endmodule
