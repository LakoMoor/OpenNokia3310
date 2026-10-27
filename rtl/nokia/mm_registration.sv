// SPDX-License-Identifier: GPL-3.0-or-later
// Minimal virtual MM location-update peer for an already established SAPI-0
// link. Caller must send UA before accepting the first pending I-frame.
// No authentication, retransmission, I-frame reassembly or call/SMS service.
module mm_registration (
    input logic clk,reset,uplink_valid,
    input logic [183:0] uplink_frame,
    input logic [4:0] uplink_length,
    input logic [23:0] plmn,
    input logic [15:0] lac,
    input logic downlink_ready,
    output logic downlink_valid,
    output logic [183:0] downlink_frame,
    output logic registered
);
    typedef enum logic [2:0] {IDLE,ACCEPT_OUT,ACCEPT_ACK,RELEASE_OUT,RELEASE_ACK,COMPLETE} state_t;
    state_t state;
    logic [23:0] plmn_q;
    logic [15:0] lac_q;
    wire [7:0] addr=uplink_frame[183:176],ctrl=uplink_frame[175:168],li=uplink_frame[167:160];
    wire sapi0=addr[7:2]==0 && addr[0];
    wire valid_length=uplink_length>=3 && uplink_length<=23;
    wire rr=uplink_valid && valid_length && sapi0 && ctrl[3:0]==1 && li==1;
    wire lu_sabm=uplink_valid && valid_length && sapi0 && (ctrl & 8'hef)==8'h2f &&
        li[1:0]==1 && li[7:2]>=2 && li[7:2]<=20 &&
        {1'b0,uplink_length}>={1'b0,li[7:2]}+7'd3 &&
        uplink_frame[155:152]==5 && uplink_frame[151:144]==8;
    always_comb begin
        registered=state==COMPLETE;
        downlink_valid=state==ACCEPT_OUT || state==RELEASE_OUT;
        downlink_frame={23{8'h2b}};
        if(state==ACCEPT_OUT)begin
            downlink_frame[183:160]=24'h03001d; // N(S)=0, N(R)=0, seven L3 bytes
            downlink_frame[159:144]=16'h0502;
            downlink_frame[143:120]=plmn_q;
            downlink_frame[119:104]=lac_q;
        end else if(state==RELEASE_OUT)begin
            downlink_frame[183:136]=48'h03020d060d00; // N(S)=1, CHANNEL RELEASE
        end
    end
    always_ff @(posedge clk)begin
        case(state)
            IDLE:if(lu_sabm)begin plmn_q<=plmn;lac_q<=lac;state<=ACCEPT_OUT;end
            ACCEPT_OUT:if(downlink_ready)state<=ACCEPT_ACK;
            ACCEPT_ACK:if(rr && ctrl[7:5]==1)state<=RELEASE_OUT;
            RELEASE_OUT:if(downlink_ready)state<=RELEASE_ACK;
            RELEASE_ACK:if(rr && ctrl[7:5]==2)state<=COMPLETE;
            default:;
        endcase
        if(reset)begin state<=IDLE;plmn_q<=0;lac_q<=0;end
    end
endmodule
