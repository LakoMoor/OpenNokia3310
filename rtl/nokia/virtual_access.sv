// SPDX-License-Identifier: GPL-3.0-or-later
// Experimental device-side RACH report / network Immediate Assignment builder.
// Both records must use the same actual transmitted RA and request FN.
// No firmware state is edited. Scheduler and request decoding are separate.
module virtual_access (
    input logic clk,reset,start,grant,
    input logic [7:0] ra,
    input logic [21:0] request_fn,
    input logic [9:0] arfcn,
    input logic [5:0] bsic,
    input logic ready,
    output logic valid,busy,done,last,
    output logic [7:0] data
);
    logic grant_q;
    logic [7:0] ra_q;
    logic [21:0] fn_q;
    logic [9:0] arfcn_q;
    logic [5:0] bsic_q;
    wire [2:0] tsc_q=bsic_q[2:0];
    logic [5:0] index;
    wire [4:0] t1=5'(fn_q/1326);
    wire [5:0] t3=6'(fn_q%51);
    wire [4:0] t2=5'(fn_q%26);
    assign valid=busy;
    assign last=busy && index==(grant_q ? 34 : 9);
    always_comb begin
        data=0;
        if(!grant_q)begin
            case(index)
                0:data=8;
                1:data=8'h84;
                2:data=ra_q;
                3:data={2'd0,fn_q[21:16]};
                4:data=fn_q[15:8];5:data=fn_q[7:0];
                default:;
            endcase
        end else begin
            // MDI RECEIVED_BLOCK on CCCH; ten-byte radio prefix + 23-byte L2.
            case(index)
                0:data=33;
                1:data=8'h80;
                2:data=8'h60;
                3:data={2'd0,bsic_q};
                5:data={2'd0,fn_q[21:16]};6:data=fn_q[15:8];7:data=fn_q[7:0];
                8:data={6'd0,arfcn_q[9:8]};9:data=arfcn_q[7:0];
                12:data=8'h2d;13:data=6;14:data=8'h3f;
                16:data=8'h41; // SDCCH/8 subchannel 0, timeslot 1
                17:data={tsc_q,3'd0,arfcn_q[9:8]};18:data=arfcn_q[7:0];
                19:data=ra_q;
                20:data={t1,t3[5:3]};21:data={t3[2:0],t2};
                default:if(index>=24)data=8'h2b;
            endcase
        end
    end
    always_ff @(posedge clk)begin
        done<=0;
        if(start && !busy)begin
            busy<=1;index<=0;grant_q<=grant;ra_q<=ra;fn_q<=request_fn;
            arfcn_q<=arfcn;bsic_q<=bsic;
        end else if(busy && ready)begin
            if(last)begin busy<=0;done<=1;end
            else index<=index+1'b1;
        end
        if(reset)begin busy<=0;done<=0;index<=0;grant_q<=0;ra_q<=0;fn_q<=0;arfcn_q<=0;bsic_q<=0;end
    end
endmodule
