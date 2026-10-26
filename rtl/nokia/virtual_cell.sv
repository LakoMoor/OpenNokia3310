// SPDX-License-Identifier: GPL-3.0-or-later
// Device-side MDI record builder for an experimental virtual GSM cell.
// Enabled only in the optional DSP network wrapper; not yet qualified on Tang.
// DCT3 envelope studied in djr-747/nokia-dct3-emulator mdi_gsm.c; SI3 layout
// follows ETSI TS 144 018 9.1.35. No firmware RAM state or UI is patched.
module virtual_cell (
    input logic clk,reset,start,
    input logic bcch,
    input logic [1:0] si_kind, // 0=SI3, 1=SI2, 2=SI4
    input logic [23:0] plmn,
    input logic [15:0] lac,cell_id,
    input logic [9:0] arfcn,
    input logic [5:0] bsic,
    input logic [21:0] frame_number,
    input logic ready,
    output logic valid,busy,done,
    output logic [7:0] data,
    output logic last
);
    logic bcch_q;
    logic [1:0] si_q;
    logic [23:0] plmn_q;
    logic [15:0] lac_q,cell_q;
    logic [9:0] arfcn_q;
    logic [5:0] bsic_q,index;
    logic [21:0] frame_q;
    assign valid=busy;
    assign last=busy && index==(bcch_q ? 34 : 11);
    always_comb begin
        data=0;
        case(index)
            0:data=bcch_q ? 8'd33 : 8'd10; // MDI body length
            1:data=8'h80;                 // RECEIVED_BLOCK
            2:data=bcch_q ? 8'h50 : 8'h40;
            3:data={2'b0,bsic_q};
            4:data=0;                     // successfully decoded block
            5:data={2'b0,frame_q[21:16]};
            6:data=frame_q[15:8];7:data=frame_q[7:0];
            8:data={6'b0,arfcn_q[9:8]};9:data=arfcn_q[7:0];
            10,11:data=0;
            // 23-byte SI3 L2 payload begins after the ten-byte DSP prefix.
            12:data=8'h49;                // pseudo length 18
            13:data=8'h06;14:data=8'h1b;   // RR / SYSTEM INFORMATION TYPE 3
            15:data=cell_q[15:8];16:data=cell_q[7:0];
            17:data=plmn_q[23:16];18:data=plmn_q[15:8];19:data=plmn_q[7:0];
            20:data=lac_q[15:8];21:data=lac_q[7:0];
            31,32,33,34:data=8'h2b;        // four SI3 rest octets
            default:data=0;
        endcase
        if(bcch_q && index>=12 && si_q==1)begin
            data=0;
            case(index)
                12:data=8'h59; // 22 mandatory octets
                13:data=8'h06;
                14:data=8'h1a;
                31:data=8'hff; // all NCCs permitted; empty neighbour bitmap
                default:;
            endcase
        end
        if(bcch_q && index>=12 && si_q==2)begin
            // No optional CBCH IEs: 12 mandatory octets, ten rest octets.
            data=index>=25 ? 8'h2b : 0;
            case(index)
                12:data=8'h31;
                13:data=8'h06;
                14:data=8'h1c;
                15:data=plmn_q[23:16];16:data=plmn_q[15:8];17:data=plmn_q[7:0];
                18:data=lac_q[15:8];19:data=lac_q[7:0];
                default:;
            endcase
        end
    end
    always_ff @(posedge clk)begin
        done<=0;
        if(start && !busy)begin
            busy<=1;index<=0;bcch_q<=bcch;si_q<=si_kind;plmn_q<=plmn;lac_q<=lac;
            cell_q<=cell_id;arfcn_q<=arfcn;bsic_q<=bsic;frame_q<=frame_number;
        end else if(busy && ready)begin
            if(last)begin busy<=0;done<=1;end
            else index<=index+1'b1;
        end
        if(reset)begin busy<=0;done<=0;index<=0;bcch_q<=0;si_q<=0;plmn_q<=0;lac_q<=0;cell_q<=0;
            arfcn_q<=0;bsic_q<=0;frame_q<=0;end
    end
endmodule
