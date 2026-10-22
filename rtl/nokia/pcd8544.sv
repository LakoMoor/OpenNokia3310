// SPDX-License-Identifier: GPL-3.0-or-later
// Nokia LCD DDRAM and command interface. Two synchronous scan ports.
module pcd8544 (
    input logic clk, reset,
    input logic wr, dc,
    input logic [7:0] data,
    output logic ready,
    input logic [6:0] x0, x1,
    input logic [5:0] y0, y1,
    output logic pixel0, pixel1
);
    logic [7:0] ram [0:503];
    logic [8:0] clear_addr;
    logic [6:0] column;
    logic [2:0] bank;
    logic extended, vertical, powerdown;
    logic [1:0] mode;
    logic [7:0] q0, q1;
    logic [2:0] bit0, bit1;
    logic valid0, valid1;
    logic [1:0] mode_q;
    wire [8:0] write_addr = {bank,6'b0} + {bank,4'b0} + {bank,2'b0} + column;
    wire [8:0] addr0 = {y0[5:3],6'b0} + {y0[5:3],4'b0} + {y0[5:3],2'b0} + x0;
    wire [8:0] addr1 = {y1[5:3],6'b0} + {y1[5:3],4'b0} + {y1[5:3],2'b0} + x1;
    // RAM clearing is a serial write, not a reset on every storage bit.
    always_ff @(posedge clk) begin
        if (!ready) ram[clear_addr] <= 0;
        else if (wr && dc) ram[write_addr] <= data;
        q0 <= ram[addr0 < 504 ? addr0 : 9'd0];
        q1 <= ram[addr1 < 504 ? addr1 : 9'd0];
        bit0 <= y0[2:0]; bit1 <= y1[2:0];
        valid0 <= ready && x0 < 84 && y0 < 48;
        valid1 <= ready && x1 < 84 && y1 < 48;
        mode_q <= powerdown ? 2'd0 : mode;
    end
    always_comb begin
        pixel0 = 0; pixel1 = 0;
        if (valid0) case (mode_q)
            1: pixel0 = 1;
            2: pixel0 = q0[bit0];
            3: pixel0 = ~q0[bit0];
            default: pixel0 = 0;
        endcase
        if (valid1) case (mode_q)
            1: pixel1 = 1;
            2: pixel1 = q1[bit1];
            3: pixel1 = ~q1[bit1];
            default: pixel1 = 0;
        endcase
    end
    always_ff @(posedge clk) begin
        if (reset) begin
            ready <= 0; clear_addr <= 0;
            column <= 0; bank <= 0; extended <= 0;
            vertical <= 0; powerdown <= 1; mode <= 0;
        end else if (!ready) begin
            if (clear_addr == 503) ready <= 1;
            else clear_addr <= clear_addr + 1'b1;
        end else if (wr) begin
            if (dc) begin
                if (vertical) begin
                    if (bank == 5) begin
                        bank <= 0;
                        column <= column == 83 ? 7'd0 : column + 1'b1;
                    end else bank <= bank + 1'b1;
                end else begin
                    if (column == 83) begin
                        column <= 0;
                        bank <= bank == 5 ? 3'd0 : bank + 1'b1;
                    end else column <= column + 1'b1;
                end
            end else if ((data & 8'hf8) == 8'h20) begin
                extended <= data[0]; vertical <= data[1]; powerdown <= data[2];
            end else if (!extended) begin
                if ((data & 8'hf8) == 8'h08) mode <= {data[2], data[0]};
                else if (data[7]) column <= data[6:0] < 84 ? data[6:0] : 7'd83;
                else if ((data & 8'hf8) == 8'h40) bank <= data[2:0] < 6 ? data[2:0] : 3'd5;
            end
        end
    end
endmodule
