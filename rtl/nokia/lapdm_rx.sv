// SPDX-License-Identifier: GPL-3.0-or-later
// Receive-side I-frame sequencing/reassembly for independent SAPI 0 and 3 links.
// Caller supplies only uplink commands and sends RR/REJ from ack/error events.
module lapdm_rx #(parameter MAX_L3=256) (
    input logic clk,reset,link_reset,link_sapi3,
    input logic frame_valid,
    output wire frame_ready,
    input logic [183:0] frame,
    input logic [4:0] frame_length,
    output logic ack_valid,ack_sapi3,ack_final,error,
    output logic [2:0] ack_nr,
    output logic message_valid,message_sapi3,
    output logic [8:0] message_length,
    input logic message_ready,
    input logic [7:0] read_address,
    output logic [7:0] read_data
);
    logic [7:0] storage[0:511];
    logic [2:0] expected[0:1];
    logic [8:0] used[0:1];
    logic received[0:1];
    wire [7:0] addr=frame[183:176],control=frame[175:168],li=frame[167:160];
    wire sapi3=addr[4:2]==3;
    wire [2:0] ns=control[3:1];
    wire [5:0] count=li[7:2];
    wire [9:0] total={1'b0,used[sapi3]}+{4'd0,count};
    // A full L3 output blocks new data, but a retransmitted I-frame must still
    // get its RR again if the previous acknowledgement was lost.
    assign frame_ready=!message_valid || (received[sapi3] && ns==3'(expected[sapi3]-1'b1));
    always_ff @(posedge clk)begin
        read_data<=storage[{message_sapi3,read_address}];
        ack_valid<=0;error<=0;
        if(message_valid && message_ready)message_valid<=0;
        if(frame_valid && frame_ready)begin
            if(frame_length<3 || frame_length>23 || addr[7:5]!=0 || !addr[0] ||
               (addr[4:2]!=0 && addr[4:2]!=3) || control[0] || !li[0] ||
               count>20 || {1'b0,frame_length}<{1'b0,count}+7'd3 || (li[1] && count==0))error<=1;
            else begin
                ack_sapi3<=sapi3;ack_final<=control[4];ack_nr<=expected[sapi3];
                if(ns==expected[sapi3])begin
                    if(total>MAX_L3 || total>256)error<=1;
                    else begin
                        for(integer i=0;i<20;i++)
                            if(i<count)storage[{sapi3,8'(used[sapi3]+i)}]<=frame[159-i*8-:8];
                        expected[sapi3]<=expected[sapi3]+1'b1;
                        received[sapi3]<=1;
                        ack_valid<=1;ack_nr<=expected[sapi3]+1'b1;
                        if(li[1])used[sapi3]<=9'(total);
                        else begin
                            used[sapi3]<=0;message_valid<=1;message_sapi3<=sapi3;message_length<=9'(total);
                        end
                    end
                end else if(received[sapi3] && ns==3'(expected[sapi3]-1'b1))ack_valid<=1; // duplicate: re-ACK only
                else error<=1;
            end
        end
        if(link_reset)begin
            expected[link_sapi3]<=0;used[link_sapi3]<=0;received[link_sapi3]<=0;
            if(message_valid && message_sapi3==link_sapi3)message_valid<=0;
            ack_valid<=0;error<=0;
        end
        if(reset)begin
            expected[0]<=0;expected[1]<=0;used[0]<=0;used[1]<=0;
            received[0]<=0;received[1]<=0;
            ack_valid<=0;ack_sapi3<=0;ack_final<=0;ack_nr<=0;error<=0;
            message_valid<=0;message_sapi3<=0;message_length<=0;read_data<=0;
        end
    end
endmodule
