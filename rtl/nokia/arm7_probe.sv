// SPDX-License-Identifier: GPL-3.0-or-later
// Standalone area qualification. Not a Nokia machine.
module arm7_probe (
    input logic clk, resetn, ready, irq, fiq,
    input logic [31:0] rdata,
    output logic valid, wr,
    output logic [31:0] addr, wdata,
    output logic [3:0] be
);
    arm7tdmi_mister #(.BIG_ENDIAN(1'b1)) u_cpu (
        .CLK(clk), .RESET_N(resetn), .CPU_CE(1'b1),
        .IRQ_ASYNC(irq), .FIQ_ASYNC(fiq),
        .MEM_VALID(valid), .MEM_READY(ready), .MEM_ADDR(addr),
        .MEM_WRITE(wr), .MEM_WDATA(wdata), .MEM_BYTE_ENABLE(be),
        .MEM_RDATA(rdata), .MEM_ERROR(1'b0),
        .MEM_CODE(), .MEM_PRIVILEGED(), .MEM_LOCK(), .MEM_SEQUENTIAL(), .MEM_MORE(),
        .CPA(1'b1), .CPB(1'b1), .CPnMREQ(), .CPSEQ(), .CPnTRANS(), .CPnOPC(), .CPTBIT(), .CPnI(),
        .DEBUG_ENABLE_ASYNC(1'b0), .DBGRQ_ASYNC(1'b0), .DBGBREAK_ASYNC(1'b0), .DBGEXT_ASYNC(2'b0),
        .DBG_STEP_VALID(1'b0), .DBG_STEP_READY(), .DBG_STEP_TMS(1'b1), .DBG_STEP_TDI(1'b0),
        .DBG_STEP_RSP_VALID(), .DBG_STEP_RSP_READY(1'b1), .DBG_STEP_TDO(), .DBG_STEP_TDO_OE(),
        .DBGACK(), .DBGnEXEC(), .DBGINSTRVALID(), .DBGRNG(), .DBGCOMMTX(), .DBGCOMMRX()
    );
endmodule
