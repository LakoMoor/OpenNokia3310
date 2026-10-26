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
    // Numeric CHVs use four bits per digit; F represents trailing FF padding.
    // Validate ASCII before comparing, so e.g. F1 cannot alias ASCII '1'.
    logic [31:0] pins[0:1];
    function automatic [31:0] packed_pin(input [63:0] value);
        for(integer i=0;i<8;i++)packed_pin[31-i*4-:4]=value[59-i*8-:4];
    endfunction
    function automatic bit pin_format(input [63:0] value);
        reg padding;
        reg [7:0] octet;
        begin
            pin_format=1;padding=0;
            for(integer i=0;i<8;i++)begin
                octet=value[63-i*8-:8];
                if(octet==8'hff)begin padding=1;if(i<4)pin_format=0;end
                else if(padding || octet<8'h30 || octet>8'h39)pin_format=0;
            end
        end
    endfunction
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
        pins[0]=32'h1234ffff; // PIN1 1234
        pins[1]=32'h5678ffff; // PIN2 5678
        attempts[0]=3;attempts[1]=3;puk_attempts[0]=10;puk_attempts[1]=10;
        pin1_enabled=0;
    end
    always_ff @(posedge clk)begin
        done<=0;
        if(start)begin
            done<=1;status_word<=16'h9000;
            if(p1!=0 || (p2!=1 && p2!=2) || ((is_enable || is_disable) && p2!=1))status_word<=16'h6b00;
            else if(length!=((is_change || is_unblock) ? 16 : 8))status_word<=16'h6700;
            else if((is_change || is_unblock) && !pin_format(replacement))status_word<=16'h6b00;
            else if(!(instruction==8'h20 || is_change || is_unblock || is_enable || is_disable))status_word<=16'h6d00;
            else if(is_unblock)begin
                if(puk_attempts[which]==0)status_word<=16'h9840;
                else if(presented!=64'h3132333435363738)begin // test PUK 12345678
                    puk_attempts[which]<=puk_attempts[which]-1'b1;
                    status_word<=puk_attempts[which]==1 ? 16'h9840 : 16'h9804;
                end else begin
                    pins[which]<=packed_pin(replacement);attempts[which]<=3;puk_attempts[which]<=10;verified[which]<=1;
                    if(!which)pin1_enabled<=1;
                end
            end else if(attempts[which]==0)status_word<=16'h9840;
            else if((!which && instruction==8'h20 && !pin1_enabled) ||
                    (is_enable && pin1_enabled) || (is_disable && !pin1_enabled))status_word<=16'h9808;
            else if(!pin_format(presented) || packed_pin(presented)!=pins[which])begin
                attempts[which]<=attempts[which]-1'b1;verified[which]<=0;
                status_word<=attempts[which]==1 ? 16'h9840 : 16'h9804;
            end else begin
                attempts[which]<=3;verified[which]<=1;
                if(is_change)pins[which]<=packed_pin(replacement);
                if(is_enable)pin1_enabled<=1;
                if(is_disable)pin1_enabled<=0;
            end
        end
        if(reset)begin done<=0;status_word<=16'h9000;verified<=0;end
    end
endmodule
