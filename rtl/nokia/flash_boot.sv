// SPDX-License-Identifier: GPL-3.0-or-later
// Power-up DMA: clear ARM RAM, then stream the Nokia image from W25Q SPI
// flash into SDRAM. SPI 03, mode 0, MSB first; pause SCK between DMA words.
module flash_boot #(
    parameter [23:0] FLASH_BASE=24'h200000,
    parameter [20:0] DEST_BASE=21'h080000,
    parameter WORDS=524288, CLEAR_WORDS=524288
) (
    input logic clk,reset,mem_ready,
    output logic done,
    output logic req,
    input logic ack,
    output logic [20:0] addr,
    output logic [31:0] wdata,
    output logic [31:0] first_word,
    output logic flash_cs_n,flash_clk,flash_mosi,
    input logic flash_miso
);
    typedef enum logic [2:0] {WAIT_MEM,CLEAR,CMD,READ,HOLD,DONE} state_t;
    state_t state;
    logic [20:0] index;
    logic [31:0] shift,word_data;
    logic [4:0] bit_index;
    always_comb begin
        done=state==DONE;
        req=state==CLEAR || state==HOLD;
        addr=state==CLEAR ? index : DEST_BASE+index;
        wdata=state==CLEAR ? 32'd0 : word_data;
        // Chip select is registered below. Decoding multiple FSM states here
        // can produce a short physical CS pulse at READ/HOLD boundaries and
        // terminate the flash transaction after its first word.
        flash_mosi=state==CMD ? shift[31] : 1'b0;
    end
    always_ff @(posedge clk) begin
        case(state)
            WAIT_MEM: if(mem_ready) begin state<=CLEAR;index<=0;end
            CLEAR: if(ack) begin
                if(index==CLEAR_WORDS-1) begin
                    flash_cs_n<=0;
                    index<=0;shift<={8'h03,FLASH_BASE};bit_index<=31;state<=CMD;
                end else index<=index+1'b1;
            end
            CMD: begin
                flash_clk<=~flash_clk;
                if(flash_clk) begin
                    shift<={shift[30:0],1'b0};
                    if(bit_index==0) begin bit_index<=31;shift<=0;state<=READ;end
                    else bit_index<=bit_index-1'b1;
                end
            end
            READ: begin
                flash_clk<=~flash_clk;
                if(!flash_clk) begin
                    shift<={shift[30:0],flash_miso};
                    if(bit_index==0) begin
                        word_data<={shift[30:0],flash_miso};state<=HOLD;
                        if(index==0) first_word<={shift[30:0],flash_miso};
                    end
                    else bit_index<=bit_index-1'b1;
                end
            end
            HOLD: begin
                flash_clk<=0;
                if(ack) begin
                    if(index==WORDS-1) begin state<=DONE;flash_cs_n<=1;end
                    else begin index<=index+1'b1;bit_index<=31;shift<=0;state<=READ;end
                end
            end
            default: flash_clk<=0;
        endcase
        if(reset) begin state<=WAIT_MEM;index<=0;shift<=0;word_data<=0;first_word<=0;bit_index<=31;flash_clk<=0;flash_cs_n<=1;end
    end
endmodule
