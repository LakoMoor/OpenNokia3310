// SPDX-License-Identifier: GPL-3.0-or-later
// One outstanding network I-frame per link. Payload segmentation belongs to
// the L3 sender; instantiate independently for SAPI 0 and SAPI 3.
module lapdm_tx #(parameter SAPI=0,INITIAL_NS=0,RETRY_CYCLES=27000000,MAX_RETRIES=3) (
    input logic clk,reset,request_valid,
    output wire request_ready,
    input logic [159:0] request_data,
    input logic [4:0] request_length,
    input logic request_more,
    input logic [2:0] receive_nr,
    output logic request_error,acknowledged,failed,
    output wire downlink_valid,
    input logic downlink_ready,
    output logic [183:0] downlink_frame,
    input logic uplink_valid,
    input logic [183:0] uplink_frame,
    input logic [4:0] uplink_length
);
    typedef enum logic [1:0] {IDLE,OFFER,WAIT_ACK,FAILED} state_t;
    state_t state;
    localparam TIMER_BITS=RETRY_CYCLES<2 ? 1 : $clog2(RETRY_CYCLES);
    localparam RETRY_BITS=MAX_RETRIES<1 ? 1 : $clog2(MAX_RETRIES+1);
    logic [TIMER_BITS-1:0] timer;
    logic [RETRY_BITS-1:0] retries;
    logic [2:0] ns;
    wire [7:0] address=uplink_frame[183:176],control=uplink_frame[175:168],li=uplink_frame[167:160];
    wire valid_frame=uplink_valid && uplink_length>=3 && uplink_length<=23 &&
        address[7:5]==0 && address[4:2]==3'(SAPI) && address[0];
    wire rr=valid_frame && control[3:0]==1 && li==1;
    wire iframe=valid_frame && !control[0] && li[0] && li[7:2]<=20 &&
        (!li[1] || li[7:2]!=0) && {1'b0,uplink_length}>={1'b0,li[7:2]}+7'd3;
    wire ack=(rr || iframe) && control[7:5]==3'(ns+1'b1);
    assign request_ready=state==IDLE;
    assign downlink_valid=state==OFFER;
    always_ff @(posedge clk)begin
        request_error<=0;acknowledged<=0;
        case(state)
            IDLE:if(request_valid)begin
                if(request_length>20 || (request_more && request_length==0))request_error<=1;
                else begin
                    downlink_frame<={23{8'h2b}};
                    downlink_frame[183:176]<=8'((SAPI<<2)|3);
                    downlink_frame[175:168]<={receive_nr,1'b0,ns,1'b0};
                    downlink_frame[167:160]<={1'b0,request_length,request_more,1'b1};
                    for(integer i=0;i<20;i++)
                        if(i<request_length)downlink_frame[159-i*8-:8]<=request_data[159-i*8-:8];
                    retries<=0;timer<=0;state<=OFFER;
                end
            end
            OFFER:if(retries!=0 && ack)begin ns<=ns+1'b1;acknowledged<=1;state<=IDLE;timer<=0;end
                else if(downlink_ready)begin timer<=0;state<=WAIT_ACK;end
            WAIT_ACK:if(ack)begin ns<=ns+1'b1;acknowledged<=1;state<=IDLE;timer<=0;end
                else if(timer==RETRY_CYCLES-1)begin
                    timer<=0;
                    if(retries==MAX_RETRIES)begin failed<=1;state<=FAILED;end
                    else begin retries<=retries+1'b1;state<=OFFER;end
                end else timer<=timer+1'b1;
            default:;
        endcase
        if(reset)begin
            state<=IDLE;ns<=3'(INITIAL_NS);timer<=0;retries<=0;
            request_error<=0;acknowledged<=0;failed<=0;downlink_frame<=0;
        end
    end
endmodule
