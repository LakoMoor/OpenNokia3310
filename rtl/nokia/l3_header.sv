// SPDX-License-Identifier: GPL-3.0-or-later
// Inspect a retained LAPDm message using its synchronous byte read port.
// Ownership stays with LAPDm until a downstream consumer accepts the header.
module l3_header (
    input logic clk,reset,message_valid,message_sapi3,
    input logic [8:0] message_length,
    output wire message_ready,
    output wire [7:0] read_address,
    input logic [7:0] read_data,
    output wire header_valid,
    input logic header_ready,
    output logic sapi3,has_header,
    output logic [8:0] length,
    output logic [7:0] discriminator,message_type
);
    typedef enum logic [2:0] {IDLE,WAIT_PD,GET_PD,WAIT_TYPE,GET_TYPE,OFFER,RELEASE} state_t;
    state_t state;
    assign read_address=(state==WAIT_TYPE || state==GET_TYPE) ? 8'd1 : 8'd0;
    assign header_valid=state==OFFER;
    assign message_ready=state==RELEASE;
    always_ff @(posedge clk)begin
        case(state)
            IDLE:if(message_valid)begin
                sapi3<=message_sapi3;length<=message_length;has_header<=message_length>=2;
                discriminator<=0;message_type<=0;
                state<=message_length>=2 ? WAIT_PD : OFFER;
            end
            WAIT_PD:state<=GET_PD;
            GET_PD:begin discriminator<=read_data;state<=WAIT_TYPE;end
            WAIT_TYPE:state<=GET_TYPE;
            GET_TYPE:begin message_type<=read_data;state<=OFFER;end
            OFFER:if(header_ready)state<=RELEASE;
            RELEASE:state<=IDLE;
            default:state<=IDLE;
        endcase
        if(reset)begin state<=IDLE;sapi3<=0;length<=0;has_header<=0;discriminator<=0;message_type<=0;end
    end
endmodule
