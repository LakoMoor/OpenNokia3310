// SPDX-License-Identifier: GPL-3.0-or-later
// PlayStation digital/analog pad polling on the open-pocket-gbc adapter pins.
// Mode 3, LSB first, 125 kHz; publish both button bytes atomically.
module ds2_pad #(parameter CLK_HZ=27_000_000) (
    input logic clk, reset, miso,
    output logic sck, cs_n, mosi,
    output logic [7:0] buttons0, buttons1
);
    localparam HALF = CLK_HZ/250_000;
    localparam GAP = CLK_HZ/60;
    // Match the conservative open-pocket adapter timing: 100 us select setup,
    // then 192 us with SCK high between bytes (including controller ACK time).
    localparam BYTE_GAP = CLK_HZ*24/125_000;
    localparam SELECT_SETUP = CLK_HZ/10_000;
    logic [$clog2(BYTE_GAP+1)-1:0] byte_wait;
    logic miso_meta, miso_sync;
    logic [$clog2(GAP)-1:0] gap;
    logic [$clog2(HALF)-1:0] half_count;
    logic [3:0] byte_index;
    logic [2:0] bit_index;
    logic [7:0] rx, id, magic, saved0, saved1;
    wire [7:0] tx = byte_index == 0 ? 8'h01 : byte_index == 1 ? 8'h42 : 8'h00;
    wire [7:0] received = {miso_sync,rx[6:0]};
    always_ff @(posedge clk) begin
        miso_meta <= miso; miso_sync <= miso_meta;
        if (cs_n) begin
            if (gap == 0) begin
                cs_n <= 0; byte_index <= 0; bit_index <= 0; rx <= 0;
                half_count <= HALF-1; sck <= 1; byte_wait<=SELECT_SETUP;
            end else gap <= gap - 1'b1;
        end else if(byte_wait!=0) byte_wait<=byte_wait-1'b1;
        else if (half_count != 0) half_count <= half_count - 1'b1;
        else begin
            half_count <= HALF-1;
            sck <= ~sck;
            if (sck) mosi <= tx[bit_index];
            else begin
                rx[bit_index] <= miso_sync;
                if (bit_index == 7) begin
                    bit_index <= 0;
                    byte_index <= byte_index + 1'b1;
                    byte_wait <= BYTE_GAP;
                    case (byte_index)
                        1: id <= received;
                        2: magic <= received;
                        3: saved0 <= received;
                        4: saved1 <= received;
                        8: begin
                            cs_n <= 1; gap <= GAP-1; mosi <= 1;
                            if ((id == 8'h41 || id == 8'h73 || id == 8'h79) && magic == 8'h5a) begin
                                buttons0 <= saved0; buttons1 <= saved1;
                            end else begin buttons0 <= 8'hff; buttons1 <= 8'hff; end
                        end
                        default: ;
                    endcase
                end else bit_index <= bit_index + 1'b1;
            end
        end
        if (reset) begin
            miso_meta <= 1; miso_sync <= 1; gap <= GAP-1; half_count <= 0;
            byte_index <= 0; bit_index <= 0; rx <= 0; id <= 0; magic <= 0;
            saved0 <= 8'hff; saved1 <= 8'hff; buttons0 <= 8'hff; buttons1 <= 8'hff;
            sck <= 1; cs_n <= 1; mosi <= 1;
            byte_wait<=0;
        end
    end
endmodule
