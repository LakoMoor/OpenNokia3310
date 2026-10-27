// SPDX-License-Identifier: GPL-3.0-or-later
// Network-side LAPDm UA for SABM/DISC. Does not perform MM registration.
module lapdm_ua (
    input logic clk,reset,start,
    input logic [183:0] frame,
    input logic [4:0] frame_length,
    output logic done,accepted,
    output logic [183:0] response,
    output logic [4:0] information_length
);
    wire [7:0] address=frame[183:176],control=frame[175:168],li=frame[167:160];
    wire sabm=(control & 8'hef)==8'h2f;
    wire disc=(control & 8'hef)==8'h43;
    wire [5:0] count=li[7:2];
    always_ff @(posedge clk)begin
        done<=0;accepted<=0;
        if(start)begin
            done<=1;information_length<=0;
            response<={23{8'h2b}};
            // Reject truncated information, invalid EA/EL, segmentation and
            // oversized frames instead of acknowledging a different message.
            if(frame_length>=3 && frame_length<=23 && address[0] && address[7:5]==0 &&
               li[0] && !li[1] && count<=20 && {1'b0,frame_length}>=count+6'd3 &&
               (sabm || (disc && count==0)))begin
                accepted<=1;information_length<=5'(count);
                response[183:176]<={3'd0,address[4:2],2'b01};
                response[175:168]<=8'h63 | (control & 8'h10);
                response[167:160]<=li;
                for(integer i=0;i<20;i++)
                    if(i<count)response[159-i*8-:8]<=frame[159-i*8-:8];
            end
        end
        if(reset)begin done<=0;accepted<=0;response<=0;information_length<=0;end
    end
endmodule
