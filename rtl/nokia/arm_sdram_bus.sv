// SPDX-License-Identifier: GPL-3.0-or-later
// Single-outstanding ARM valid/ready -> upstream SDRAM low-priority port.
// The boot trampoline is removed after the first fetch at 0x200040.
module arm_sdram_bus (
    input logic clk,reset,
    input logic valid,write,
    input logic [31:0] address,wdata,
    input logic [3:0] be,
    output logic ready,error,
    output logic [31:0] rdata,
    output logic lp_req,lp_we,
    output logic [20:0] lp_addr,
    output logic [31:0] lp_wdata,
    output logic [3:0] lp_be,
    input logic lp_ack,lp_rvalid,
    input logic [31:0] lp_rdata
);
    typedef enum logic [1:0] {IDLE,REQUEST,READ_WAIT,RESPONSE} state_t;
    state_t state;
    logic overlay;
    assign ready=state==RESPONSE;
    assign lp_req=state==REQUEST;
    always_ff @(posedge clk) begin
        case(state)
            IDLE: if(valid) begin
                error<=address>=32'h00400000;
                if(address>=32'h00400000) begin rdata<=0;state<=RESPONSE;end
                else if(overlay && !write && address<8) begin
                    rdata<=address[2] ? 32'h00200040 : 32'he51ff004;
                    state<=RESPONSE;
                end else begin
                    lp_we<=write;lp_addr<=address[22:2];lp_wdata<=wdata;lp_be<=be;state<=REQUEST;
                    if(address==32'h00200040 && !write) overlay<=0;
                end
            end
            REQUEST: if(lp_ack) state<=lp_we ? RESPONSE : READ_WAIT;
            READ_WAIT: if(lp_rvalid) begin rdata<=lp_rdata;state<=RESPONSE;end
            RESPONSE: state<=IDLE;
        endcase
        if(reset) begin state<=IDLE;overlay<=1;error<=0;rdata<=0;lp_we<=0;lp_addr<=0;lp_wdata<=0;lp_be<=0;end
    end
endmodule
