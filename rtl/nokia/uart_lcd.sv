// SPDX-License-Identifier: GPL-3.0-or-later
// Diagnostic transport: A5 opcode payload; 0=LCD command, 1=LCD data.
// Opcode 2/3/4 update remote keys 7:0 / 15:8 / 16. 115200 8N1.
module uart_lcd #(
    parameter CLK_HZ=27_000_000, BAUD=115200
) (
    input logic clk, reset, rx,
    output logic wr, dc,
    output logic [7:0] data,
    output logic [16:0] keys,
    output logic control_wr,
    output logic [7:0] control_opcode,control_data
);
    localparam DIV = (CLK_HZ + BAUD/2)/BAUD;
    logic rx_meta, rx_sync;
    logic [$clog2(DIV)-1:0] timer;
    logic [3:0] bit_number;
    logic [7:0] shift, opcode;
    logic busy;
    logic [1:0] state;
    logic [25:0] idle_count;
    always_ff @(posedge clk) begin
        rx_meta <= rx; rx_sync <= rx_meta;
        wr <= 0;
        control_wr<=0;
        if (idle_count < CLK_HZ) idle_count <= idle_count + 1'b1;
        else begin keys <= 0; state <= 0; end
        if (!busy) begin
            if (!rx_sync) begin busy <= 1; timer <= DIV/2-1; bit_number <= 0; end
        end else if (timer != 0) timer <= timer - 1'b1;
        else begin
            timer <= DIV-1; bit_number <= bit_number + 1'b1;
            if (bit_number == 0) begin
                if (rx_sync) busy <= 0;
            end else if (bit_number == 9) begin
                busy <= 0;
                if (rx_sync) begin
                    idle_count <= 0;
                    case (state)
                        0: if (shift == 8'ha5) state <= 1;
                        1: begin opcode <= shift; state <= 2; end
                        2: begin
                            state <= 0;
                            case (opcode)
                                0,1: begin wr <= 1; dc <= opcode[0]; data <= shift; end
                                2: keys[7:0] <= shift;
                                3: keys[15:8] <= shift;
                                4: keys[16] <= shift[0];
                                5,6,7,8:begin control_wr<=1;control_opcode<=opcode;control_data<=shift;end
                                default: ;
                            endcase
                        end
                        default: state <= 0;
                    endcase
                end else state <= 0;
            end else shift <= {rx_sync,shift[7:1]};
        end
        if (reset) begin
            rx_meta <= 1; rx_sync <= 1; timer <= 0; bit_number <= 0;
            shift <= 0; opcode <= 0; busy <= 0; state <= 0;
            wr <= 0; dc <= 0; data <= 0; keys <= 0; idle_count <= 0;
            control_wr<=0;control_opcode<=0;control_data<=0;
        end
    end
endmodule
