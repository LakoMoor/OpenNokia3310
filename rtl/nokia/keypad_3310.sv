// SPDX-License-Identifier: GPL-3.0-or-later
// Matrix from djr-747/nokia-dct3-emulator model_3310 (Family B).
// keys[0..9]=digits, 10=*, 11=#, 12=Menu, 13=C, 14=up, 15=down, 16=power.
module keypad_3310 (
    input logic [16:0] keys,
    input logic [7:0] row_signal, row_direction,
    output logic [7:0] columns
);
    logic [4:0] rows [0:4];
    logic [4:0] pressed;
    always_comb begin
        rows[0] = {keys[13],1'b0,keys[0],keys[14],1'b0};
        rows[1] = {1'b0,keys[2],keys[1],keys[15],1'b0};
        rows[2] = {keys[4],keys[5],keys[6],2'b0};
        rows[3] = {keys[7],keys[8],keys[9],2'b0};
        rows[4] = {keys[10],keys[12],keys[11],keys[3],1'b0};
        pressed = 0;
        for (int r=0; r<5; r=r+1)
            if (!row_signal[r]) pressed = pressed | rows[r];
        if (row_direction == 8'he0) pressed = {3'b0,keys[16],1'b0};
        columns = {3'b0,~pressed};
    end
endmodule
