// SPDX-License-Identifier: GPL-3.0-or-later
// DualShock digital bytes, active low. Hold L1 for numeric layer.
module pad_3310 (
    input logic [7:0] buttons0, buttons1,
    output logic [16:0] keys
);
    logic [7:0] a,b;
    always_comb begin
        a = ~buttons0; b = ~buttons1;
        keys = 0;
        if (b[2]) begin
            keys[2]=a[4]; keys[8]=a[6]; keys[4]=a[7]; keys[6]=a[5];
            keys[1]=b[4]; keys[3]=b[5]; keys[5]=b[6]; keys[0]=b[7];
            keys[7]=b[0]; keys[9]=b[1]; keys[10]=a[0]; keys[11]=a[3];
        end else begin
            keys[14]=a[4]; keys[15]=a[6];
            keys[4]=a[7]; keys[6]=a[5];
            keys[12]=b[5]; keys[13]=b[6];
            keys[2]=b[4]; keys[8]=b[7]; keys[16]=a[3];
        end
    end
endmodule
