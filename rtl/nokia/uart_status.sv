// SPDX-License-Identifier: GPL-3.0-or-later
// Development telemetry: N3, flags, address (BE32), LCD count (BE16), XOR.
module uart_status #(parameter CLK_HZ=16_875_000,parameter BAUD=115200) (
    input logic clk,reset,
    input logic [7:0] flags,
    input logic [31:0] address,
    input logic [15:0] lcd_count,
    output logic tx
);
    localparam DIV=CLK_HZ/BAUD;
    typedef enum logic [2:0] {IDLE,START,DATA,STOP,GAP} state_t;
    state_t state;
    logic [25:0] period;
    logic [15:0] baud_count;
    logic [79:0] packet;
    logic [3:0] byte_index;
    logic [2:0] bit_index;
    wire [7:0] checksum=8'h4e^8'h33^flags^address[31:24]^address[23:16]^
        address[15:8]^address[7:0]^lcd_count[15:8]^lcd_count[7:0];
    always_ff @(posedge clk) begin
        if(baud_count!=0) baud_count<=baud_count-1'b1;
        case(state)
            IDLE:begin
                tx<=1;
                if(period==CLK_HZ/4-1) begin
                    period<=0;packet<={8'h4e,8'h33,flags,address,lcd_count,checksum};
                    byte_index<=0;state<=START;
                end else period<=period+1'b1;
            end
            START:begin tx<=0;baud_count<=DIV-1;bit_index<=0;state<=DATA;end
            DATA:if(baud_count==0) begin
                tx<=packet[72+bit_index];baud_count<=DIV-1;bit_index<=bit_index+1'b1;
                if(bit_index==7) state<=STOP;
            end
            STOP:if(baud_count==0) begin tx<=1;baud_count<=DIV-1;state<=GAP;end
            GAP:if(baud_count==0) begin
                packet<=packet<<8;
                if(byte_index==9) state<=IDLE;
                else begin byte_index<=byte_index+1'b1;state<=START;end
            end
            default:state<=IDLE;
        endcase
        if(reset) begin
            state<=IDLE;period<=0;baud_count<=0;packet<=0;byte_index<=0;bit_index<=0;tx<=1;
        end
    end
endmodule
