// SPDX-License-Identifier: GPL-3.0-or-later
// Experimental MO speech call over an established virtual SAPI-0 CM link.
// Parse bounded SETUP IEs and BCD digits, then reliably send the CC handshake.
// No incoming call, speech bearer/audio, release or SMS implementation here.
module cc_voice #(parameter RETRY_CYCLES=27000000,MAX_RETRIES=3) (
    input logic clk,reset,header_valid,header_sapi3,header_complete,
    input logic [8:0] header_length,
    input logic [7:0] header_pd,header_type,
    output wire header_ready,
    output wire [7:0] read_address,
    input logic [7:0] read_data,
    input logic [2:0] receive_nr,
    input logic uplink_valid,
    input logic [183:0] uplink_frame,
    input logic [4:0] uplink_length,
    output wire downlink_valid,
    input logic downlink_ready,
    output wire [183:0] downlink_frame,
    output wire call_active,failed,
    output logic [159:0] called_number,
    output logic [5:0] called_digits,
    output logic [7:0] called_type
);
    typedef enum logic [3:0] {IDLE,SCAN,READ_WAIT,READ_VALUE,ACCEPT,
        PROCEED_REQ,PROCEED_ACK,ALERT_REQ,ALERT_ACK,CONNECT_REQ,CONNECT_ACK,
        WAIT_PHONE,ACTIVE,REJECTED} state_t;
    state_t state;
    typedef enum logic [1:0] {TAG,LENGTH,BODY} phase_t;
    phase_t phase;
    logic [8:0] index,length;
    logic [7:0] ie,remaining,body_index,ti;
    logic bearer_seen,number_seen;
    wire tx_ready,tx_ack,tx_failed,tx_error;
    wire request_valid=state==PROCEED_REQ || state==ALERT_REQ || state==CONNECT_REQ;
    wire [7:0] cc_type=state==PROCEED_REQ ? 8'h02 : state==ALERT_REQ ? 8'h01 : 8'h07;
    wire phone_connect_ack=header_valid && header_complete && !header_sapi3 &&
        header_length==2 && header_pd==ti && (header_type & 8'hbf)==8'h0f;
    assign header_ready=state==ACCEPT || (state==WAIT_PHONE && phone_connect_ack);
    assign read_address=index[7:0];
    assign call_active=state==ACTIVE;
    assign failed=state==REJECTED || tx_failed || tx_error;
    lapdm_tx #(.SAPI(0),.INITIAL_NS(1),.RETRY_CYCLES(RETRY_CYCLES),.MAX_RETRIES(MAX_RETRIES)) tx(
        .clk(clk),.reset(reset),.request_valid(request_valid),.request_ready(tx_ready),
        .request_data({ti ^ 8'h80,cc_type,144'd0}),.request_length(5'd2),.request_more(1'b0),
        .receive_nr(receive_nr),.request_error(tx_error),.acknowledged(tx_ack),.failed(tx_failed),
        .downlink_valid(downlink_valid),.downlink_ready(downlink_ready),.downlink_frame(downlink_frame),
        .uplink_valid(uplink_valid),.uplink_frame(uplink_frame),.uplink_length(uplink_length));
    always_ff @(posedge clk)begin
        case(state)
            IDLE:if(header_valid && header_complete && !header_sapi3 && !header_pd[7] &&
                    header_pd[6:4]!=7 && header_pd[3:0]==3 &&
                    (header_type & 8'hbf)==5)begin
                ti<=header_pd;length<=header_length;index<=2;phase<=TAG;
                bearer_seen<=0;number_seen<=0;called_number<=0;called_digits<=0;
                state<=header_length>256 || header_length<2 ? REJECTED : SCAN;
            end
            SCAN:if(index>=length)begin
                if(index==length && phase==TAG && bearer_seen && number_seen && called_digits!=0)state<=ACCEPT;
                else state<=REJECTED;
            end else state<=READ_WAIT;
            READ_WAIT:state<=READ_VALUE;
            READ_VALUE:begin
                index<=index+1'b1;state<=SCAN;
                case(phase)
                    TAG:begin ie<=read_data;if(!read_data[7])phase<=LENGTH;end
                    LENGTH:begin
                        remaining<=read_data;body_index<=0;
                        phase<=read_data==0 ? TAG : BODY;
                        if({1'b0,index}+10'd1+{2'd0,read_data}>{1'b0,length} ||
                           (ie==4 && (bearer_seen || read_data==0)) ||
                           (ie==8'h5e && (number_seen || read_data<2 || read_data>21)))state<=REJECTED;
                    end
                    BODY:begin
                        remaining<=remaining-1'b1;body_index<=body_index+1'b1;
                        if(remaining==1)phase<=TAG;
                        if(ie==4 && body_index==0)begin
                            bearer_seen<=1;
                            if(read_data[2:0]!=0)state<=REJECTED; // speech only
                        end
                        if(ie==8'h5e)begin
                            if(body_index==0)begin
                                number_seen<=1;called_type<=read_data;
                                if(!read_data[7])state<=REJECTED; // extended address unsupported
                            end else if(read_data[3:0]>11 ||
                                (read_data[7:4]>11 && !(read_data[7:4]==15 && remaining==1)))state<=REJECTED;
                            else if(read_data[7:4]==15)begin
                                called_number<={called_number[155:0],read_data[3:0]};called_digits<=called_digits+1'b1;
                            end else begin
                                called_number<={called_number[151:0],read_data[3:0],read_data[7:4]};called_digits<=called_digits+6'd2;
                            end
                        end
                    end
                    default:state<=REJECTED;
                endcase
            end
            ACCEPT:state<=PROCEED_REQ;
            PROCEED_REQ:if(tx_ready)state<=PROCEED_ACK;
            PROCEED_ACK:if(tx_ack)state<=ALERT_REQ;
            ALERT_REQ:if(tx_ready)state<=ALERT_ACK;
            ALERT_ACK:if(tx_ack)state<=CONNECT_REQ;
            CONNECT_REQ:if(tx_ready)state<=CONNECT_ACK;
            CONNECT_ACK:if(tx_ack)state<=WAIT_PHONE;
            WAIT_PHONE:if(phone_connect_ack)state<=ACTIVE;
            default:;
        endcase
        if(reset)begin
            state<=IDLE;phase<=TAG;index<=0;length<=0;ie<=0;remaining<=0;body_index<=0;ti<=0;
            bearer_seen<=0;number_seen<=0;called_number<=0;called_digits<=0;called_type<=0;
        end
    end
endmodule
