// SPDX-License-Identifier: GPL-3.0-or-later
// Standalone volatile SDRAM qualification; never accesses SPI flash.
module nokia_memtest (
    input logic sys_clk,
    output wire uart_tx,
    output wire O_sdram_clk,O_sdram_cke,O_sdram_cs_n,O_sdram_cas_n,O_sdram_ras_n,O_sdram_wen_n,
    output wire [3:0] O_sdram_dqm,
    output wire [10:0] O_sdram_addr,
    output wire [1:0] O_sdram_ba,
    inout wire [31:0] IO_sdram_dq
);
    wire clk_sys,clk_sys_p,locked,ready,ack,rvalid;
    wire [31:0] rdata;
    logic [7:0] por=0;
    pll_nokia u_pll_b_sys(.clock_in(sys_clk),.clk_sys(clk_sys),.clk_sys_p(clk_sys_p),.locked(locked));
    always_ff @(posedge clk_sys)if(!locked)por<=0;else if(por!=255)por<=por+1'b1;
    wire reset=por!=255;
    logic [20:0] index;
    logic [2:0] state;
    logic [15:0] errors;
    logic [31:0] last_bad;
    wire [31:0] pattern=32'ha5c35a69^{index,11'b0}^{11'b0,index};
    always_ff @(posedge clk_sys)begin
        case(state)
            0:if(ready)state<=1;
            1:if(ack)begin if(index==21'h1fffff)begin index<=0;state<=2;end else index<=index+1'b1;end
            2:state<=3;
            3:if(ack)state<=4;
            4:if(rvalid)begin
                if(rdata!=pattern)begin if(errors!=65535)errors<=errors+1'b1;last_bad<=rdata;end
                if(index==21'h1fffff)state<=5;
                else begin index<=index+1'b1;state<=3;end
            end
            default:;
        endcase
        if(reset)begin index<=0;state<=0;errors<=0;last_bad<=0;end
    end
    sdram_ctrl #(.INIT_WAIT(3500),.REFRESH_INTERVAL(125)) u_sdram (
        .clk(clk_sys),.resetn(!reset),.ready(ready),
        .cart_rd_strobe(1'b0),.cart_wr_strobe(1'b0),.cart_addr(23'd0),.cart_din(8'd0),.cart_dout(),
        .lp_block(1'b0),.pd_en(1'b0),.sr_req(1'b0),.lp_req(state==1 || state==3),.lp_ack(ack),
        .lp_we(state==1),.lp_addr(index),.lp_wdata(pattern),.lp_be(4'hf),.lp_rdata(rdata),.lp_rvalid(rvalid),
        .O_sdram_clk(O_sdram_clk),.O_sdram_cke(O_sdram_cke),.O_sdram_cs_n(O_sdram_cs_n),
        .O_sdram_cas_n(O_sdram_cas_n),.O_sdram_ras_n(O_sdram_ras_n),.O_sdram_wen_n(O_sdram_wen_n),
        .O_sdram_dqm(O_sdram_dqm),.O_sdram_addr(O_sdram_addr),.O_sdram_ba(O_sdram_ba),
        .IO_sdram_dq(IO_sdram_dq),.clk_sdram_p(clk_sys_p));
    uart_status #(.CLK_HZ(16875000)) u_status(.clk(clk_sys),.reset(reset),
        .flags({5'b0,errors!=0,state==5,ready}),.address(last_bad),.lcd_count(errors),.tx(uart_tx));
endmodule
