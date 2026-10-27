// SPDX-License-Identifier: GPL-3.0-or-later
// Device-side SDCCH idle fill and uplink block request. Not an L3 network.
module virtual_dedicated (
    input logic clk,reset,start,request_block,
    input logic [21:0] frame_number,
    input logic [9:0] arfcn,
    input logic [5:0] bsic,
    input logic ready,
    output logic valid,busy,done,last,
    output logic [7:0] data
);
    logic request_q;
    logic [21:0] fn_q;
    logic [9:0] arfcn_q;
    logic [5:0] bsic_q,index;
    assign valid=busy;
    assign last=busy && index==(request_q ? 2 : 34);
    always_comb begin
        data=0;
        if(request_q)begin
            case(index)
                0:data=1;1:data=8'h86;2:data=8'h80;
                default:;
            endcase
        end else begin
            case(index)
                0:data=33;1:data=8'h80;2:data=8'h80;3:data={2'd0,bsic_q};
                5:data={2'd0,fn_q[21:16]};6:data=fn_q[15:8];7:data=fn_q[7:0];
                8:data={6'd0,arfcn_q[9:8]};9:data=arfcn_q[7:0];
                12,13:data=3;14:data=1; // LAPDm idle UI, empty information field
                default:if(index>=15)data=8'h2b;
            endcase
        end
    end
    always_ff @(posedge clk)begin
        done<=0;
        if(start && !busy)begin
            busy<=1;index<=0;request_q<=request_block;fn_q<=frame_number;arfcn_q<=arfcn;bsic_q<=bsic;
        end else if(busy && ready)begin
            if(last)begin busy<=0;done<=1;end
            else index<=index+1'b1;
        end
        if(reset)begin busy<=0;done<=0;index<=0;request_q<=0;fn_q<=0;arfcn_q<=0;bsic_q<=0;end
    end
endmodule
