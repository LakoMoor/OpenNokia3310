// SPDX-License-Identifier: GPL-3.0-or-later
// Synthetic SIM CHV1/CHV2 state. ETSI TS 151 011 8.9-8.13 / 9.2.9-9.2.13.
// PIN/retry state survives card resets, as real SIM nonvolatile state does.
// FPGA reconfiguration restores this test card's default credentials.
module sim_chv (
    input logic clk,reset,start,
    input logic [7:0] instruction,p1,p2,length,
    input logic [63:0] presented,replacement,
    output logic done,
    output logic [15:0] status_word,
    output logic pin1_enabled,
    output logic [1:0] verified,
    output wire [7:0] pin1_status,pin2_status,puk1_status,puk2_status
);
    logic [63:0] pins[0:1];
    logic [1:0] attempts[0:1];
    logic [3:0] puk_attempts[0:1];
    wire which=p2==2;
    wire is_unblock=instruction==8'h2c;
    wire is_change=instruction==8'h24;
    wire is_disable=instruction==8'h26;
    wire is_enable=instruction==8'h28;
    assign pin1_status={6'b100000,attempts[0]};
    assign pin2_status={6'b100000,attempts[1]};
    assign puk1_status={4'b1000,puk_attempts[0]};
    assign puk2_status={4'b1000,puk_attempts[1]};
    initial begin
        pins[0]=64'h31323334ffffffff; // PIN1 1234
        pins[1]=64'h35363738ffffffff; // PIN2 5678
        attempts[0]=3;attempts[1]=3;puk_attempts[0]=10;puk_attempts[1]=10;
        pin1_enabled=0;
    end
    always_ff @(posedge clk)begin
        done<=0;
        if(start)begin
            done<=1;status_word<=16'h9000;
            if(p1!=0 || (p2!=1 && p2!=2) || ((is_enable || is_disable) && p2!=1))status_word<=16'h6b00;
            else if(length!=((is_change || is_unblock) ? 16 : 8))status_word<=16'h6700;
            else if(!(instruction==8'h20 || is_change || is_unblock || is_enable || is_disable))status_word<=16'h6d00;
            else if(is_unblock)begin
                if(puk_attempts[which]==0)status_word<=16'h9840;
                else if(presented!=64'h3132333435363738)begin // test PUK 12345678
                    puk_attempts[which]<=puk_attempts[which]-1'b1;
                    status_word<=puk_attempts[which]==1 ? 16'h9840 : 16'h9804;
                end else begin
                    pins[which]<=replacement;attempts[which]<=3;puk_attempts[which]<=10;verified[which]<=1;
                    if(!which)pin1_enabled<=1;
                end
            end else if(attempts[which]==0)status_word<=16'h9840;
            else if((!which && instruction==8'h20 && !pin1_enabled) ||
                    (is_enable && pin1_enabled) || (is_disable && !pin1_enabled))status_word<=16'h9808;
            else if(presented!=pins[which])begin
                attempts[which]<=attempts[which]-1'b1;verified[which]<=0;
                status_word<=attempts[which]==1 ? 16'h9840 : 16'h9804;
            end else begin
                attempts[which]<=3;verified[which]<=1;
                if(is_change)pins[which]<=replacement;
                if(is_enable)pin1_enabled<=1;
                if(is_disable)pin1_enabled<=0;
            end
        end
        if(reset)begin done<=0;status_word<=16'h9000;verified<=0;end
    end
endmodule
