// SPDX-License-Identifier: GPL-3.0-or-later
// Verify the real SPI -> boot DMA -> SDRAM path using CRC32 of all 2 MiB.
module nokia_romtest (
    input logic sys_clk,flash_miso,uart_rx,
    output wire uart_tx,flash_cs_n,flash_clk,flash_mosi,
    output wire O_sdram_clk,O_sdram_cke,O_sdram_cs_n,O_sdram_cas_n,O_sdram_ras_n,O_sdram_wen_n,
    output wire [3:0] O_sdram_dqm,
    output wire [10:0] O_sdram_addr,
    output wire [1:0] O_sdram_ba,
    inout wire [31:0] IO_sdram_dq
);
    wire clk_sys,clk_sys_p,locked,ready,ack,rvalid,loaded,boot_req;
    wire [31:0] rdata,boot_data,first_word;
    wire [20:0] boot_addr;
    logic [7:0] por=0;
    pll_nokia u_pll_b_sys(.clock_in(sys_clk),.clk_sys(clk_sys),.clk_sys_p(clk_sys_p),.locked(locked));
    always_ff @(posedge clk_sys)if(!locked)por<=0;else if(por!=255)por<=por+1'b1;
    wire reset=por!=255;
    logic [18:0] index;
    logic [1:0] state;
    logic [31:0] crc;
    wire [16:0] probe_select;
    logic [31:0] boot_words[0:63];
    logic [31:0] probe_word;
    uart_lcd #(.CLK_HZ(16875000)) u_probe(.clk(clk_sys),.reset(reset),.rx(uart_rx),
        .keys(probe_select),.wr(),.dc(),.data(),.control_wr(),.control_opcode(),.control_data());
    always_ff @(posedge clk_sys)begin
        if(state==2 && rvalid && index<64)boot_words[index[5:0]]<=rdata;
        probe_word<=boot_words[probe_select[5:0]];
    end
    function automatic [31:0] crc_word(input [31:0] prior,word_data);
        reg [31:0] value;
        begin
            value=prior;
            for(int byte_index=0;byte_index<4;byte_index++)begin
                value=value^{24'b0,word_data[31-byte_index*8-:8]};
                for(int bit_index=0;bit_index<8;bit_index++)value=value[0] ? (value>>1)^32'hedb88320 : value>>1;
            end
            crc_word=value;
        end
    endfunction
    always_ff @(posedge clk_sys)begin
        case(state)
            0:if(loaded)state<=1;
            1:if(ack)state<=2;
            2:if(rvalid)begin
                crc<=crc_word(crc,rdata);
                if(index==19'h7ffff)state<=3;
                else begin index<=index+1'b1;state<=1;end
            end
            default:;
        endcase
        if(reset)begin index<=0;state<=0;crc<=32'hffffffff;end
    end
    flash_boot u_boot(.clk(clk_sys),.reset(reset),.mem_ready(ready),.done(loaded),.req(boot_req),
        .ack(ack && !loaded),.addr(boot_addr),.wdata(boot_data),.first_word(first_word),
        .flash_cs_n(flash_cs_n),.flash_clk(flash_clk),.flash_mosi(flash_mosi),.flash_miso(flash_miso));
    sdram_ctrl #(.INIT_WAIT(3500),.REFRESH_INTERVAL(125)) u_sdram (
        .clk(clk_sys),.resetn(!reset),.ready(ready),
        .cart_rd_strobe(1'b0),.cart_wr_strobe(1'b0),.cart_addr(23'd0),.cart_din(8'd0),.cart_dout(),
        .lp_block(1'b0),.pd_en(1'b0),.sr_req(1'b0),.lp_req(loaded ? state==1 : boot_req),.lp_ack(ack),
        .lp_we(!loaded),.lp_addr(loaded ? 21'h80000+{2'b0,index} : boot_addr),.lp_wdata(boot_data),.lp_be(4'hf),.lp_rdata(rdata),.lp_rvalid(rvalid),
        .O_sdram_clk(O_sdram_clk),.O_sdram_cke(O_sdram_cke),.O_sdram_cs_n(O_sdram_cs_n),
        .O_sdram_cas_n(O_sdram_cas_n),.O_sdram_ras_n(O_sdram_ras_n),.O_sdram_wen_n(O_sdram_wen_n),
        .O_sdram_dqm(O_sdram_dqm),.O_sdram_addr(O_sdram_addr),.O_sdram_ba(O_sdram_ba),
        .IO_sdram_dq(IO_sdram_dq),.clk_sdram_p(clk_sys_p));
    uart_status #(.CLK_HZ(16875000)) u_status(.clk(clk_sys),.reset(reset),
        .flags({6'b0,state==3,ready}),.address(state==3 && probe_select[16] ? probe_word : ~crc),
        .lcd_count(state==3 && probe_select[16] ? {10'b0,probe_select[5:0]} : index[15:0]),.tx(uart_tx));
endmodule
