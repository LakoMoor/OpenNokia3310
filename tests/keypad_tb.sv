`timescale 1ns/1ps
module keypad_tb;
    reg [16:0] keys=0;
    reg [7:0] row_signal=255,row_direction=31;
    wire [7:0] columns;
    reg [7:0] b0=255,b1=255;
    wire [16:0] padkeys;
    keypad_3310 dut(.*);
    pad_3310 pad(.buttons0(b0),.buttons1(b1),.keys(padkeys));
    integer rows[0:15]='{0,1,1,4,2,2,2,3,3,3,4,4,4,0,0,1};
    integer cols[0:15]='{2,2,3,1,4,3,2,4,3,2,4,2,3,4,1,1};
    // Physical DS2 bits: Select,L3,R3,Start,Up,Right,Down,Left,
    // L2,R2,L1,R1,Triangle,Circle,Cross,Square.
    integer normal_key[0:15]='{-1,-1,-1,16,14,6,15,4,-1,-1,-1,-1,2,12,13,8};
    integer number_key[0:15]='{10,-1,-1,11,2,6,8,4,7,9,-1,-1,1,3,5,0};
    initial begin
        #1; if(columns!==31) $fatal(1,"idle");
        for(integer k=0;k<16;k=k+1) begin
            keys=17'b1<<k;
            for(integer r=0;r<5;r=r+1) begin
                row_signal=~(1<<r); #1;
                if(columns !== (r==rows[k] ? (31 & ~(1<<cols[k])) : 31)) $fatal(1,"key %0d row %0d",k,r);
            end
        end
        keys=17'h10000; row_direction=8'he0; #1;
        if(columns!==29) $fatal(1,"power special scan");
        keys=1; #1; if(columns!==31) $fatal(1,"normal key in power scan");
        b0=8'hef; #1; if(padkeys!==17'h04000) $fatal(1,"up");
        b1=8'hfb; #1; if(padkeys!==17'h00004) $fatal(1,"numeric 2");
        b0=8'hff; b1=8'hdf; #1; if(padkeys!==17'h01000) $fatal(1,"menu");
        b1=8'hbf; #1; if(padkeys!==17'h02000) $fatal(1,"clear");
        b1=255; #1; if(padkeys!==0) $fatal(1,"pad idle");
        for(integer layer=0;layer<2;layer=layer+1) begin
            for(integer button=0;button<16;button=button+1) begin
                b0=255; b1=layer ? 8'hfb : 8'hff;
                if(button<8) b0[button]=0; else b1[button-8]=0;
                #1;
                // L1 itself selects the layer; it has no Nokia key.
                if(padkeys !== ((layer ? number_key[button] : normal_key[button])<0 ?
                    17'b0 : 17'b1<<(layer ? number_key[button] : normal_key[button])))
                    $fatal(1,"pad button %0d layer %0d: %h",button,layer,padkeys);
            end
        end
        b0=8'hcf; b1=8'h9f; #1;
        if(padkeys!==(17'h4000|17'h0040|17'h1000|17'h2000)) $fatal(1,"simultaneous menu keys");
        $display("PASS keypad: every key/row, power, pad navigation and numeric layer"); $finish;
    end
endmodule
