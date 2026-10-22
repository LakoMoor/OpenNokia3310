// SPDX-License-Identifier: GPL-3.0-or-later
// Tang Nano 20K board integration: original ARM ROM -> SDRAM -> MAD2 -> both displays.
// Device-model completeness is tracked separately from FPGA board integration.
module nokia_top (
    input logic sys_clk,s1,uart_rx,ds_miso,flash_miso,
    output logic uart_tx,
    output logic [1:0] led,
    output logic tmds_clk_p,tmds_clk_n,
    output logic [2:0] tmds_d_p,tmds_d_n,
    output logic ds_clk,ds_cs,ds_mosi,
    output logic lcd_scl,lcd_sda,lcd_cs,lcd_dc,lcd_rst,lcd_bl,
    output logic flash_cs_n,flash_clk,flash_mosi,
    output logic O_sdram_clk,O_sdram_cke,O_sdram_cs_n,O_sdram_cas_n,O_sdram_ras_n,O_sdram_wen_n,
    output logic [3:0] O_sdram_dqm,
    output logic [10:0] O_sdram_addr,
    output logic [1:0] O_sdram_ba,
    inout wire [31:0] IO_sdram_dq
);
    localparam CLK_HZ=16_875_000;
    wire clk_p5,clk_p,hdmi_lock,clk_sys,clk_sys_p,sys_lock;
    pll_hdmi480 u_pll_a_hdmi (.clock_in(sys_clk),.pwrdn(1'b0),.clock_out(clk_p5),.locked(hdmi_lock));
    pll_nokia u_pll_b_sys (.clock_in(sys_clk),.clk_sys(clk_sys),.clk_sys_p(clk_sys_p),.locked(sys_lock));
    CLKDIV #(.DIV_MODE("5")) u_div5 (.CLKOUT(clk_p),.HCLKIN(clk_p5),.RESETN(hdmi_lock),.CALIB(1'b0));
    logic [7:0] por=0,hpor=0;
    logic s1_meta=0,s1_sync=0,reset_meta=1,reset_video=1;
    always_ff @(posedge clk_sys) begin
        s1_meta<=s1;s1_sync<=s1_meta;
        if(!sys_lock || !hdmi_lock || s1_sync) por<=0;
        else if(por!=255) por<=por+1'b1;
    end
    wire reset=por!=255;
    always_ff @(posedge clk_p) begin
        reset_meta<=reset;reset_video<=reset_meta;
        if(!hdmi_lock || reset_video) hpor<=0;
        else if(hpor!=255) hpor<=hpor+1'b1;
    end
    wire hreset=hpor!=255;
    wire [7:0] ds0,ds1;
    wire [16:0] pad_keys,remote_keys;
    ds2_pad u_pad (.clk(clk_p),.reset(hreset),.miso(ds_miso),.sck(ds_clk),.cs_n(ds_cs),.mosi(ds_mosi),.buttons0(ds0),.buttons1(ds1));
    pad_3310 u_keys (.buttons0(ds0),.buttons1(ds1),.keys(pad_keys));
    uart_lcd u_remote (.clk(clk_p),.reset(hreset),.rx(uart_rx),.keys(remote_keys),.wr(),.dc(),.data());
    logic [16:0] key_meta,key_sync;
    always_ff @(posedge clk_sys) begin key_meta<=pad_keys|remote_keys;key_sync<=key_meta;end
    wire boot_done,sdram_ready;
    logic [27:0] power_hold;
    always_ff @(posedge clk_sys) begin
        if(reset || !boot_done) power_hold<=0;
        else if(power_hold<10*CLK_HZ) power_hold<=power_hold+1'b1;
    end
    wire [16:0] keys=key_sync|{power_hold<10*CLK_HZ,16'b0};
    wire valid,write,code,ready,error,lcd_wr_cpu,lcd_dc_cpu,unsupported;
    wire [31:0] address,wdata,rdata;
    wire [3:0] be;
    wire [7:0] lcd_data_cpu;
    nokia_core #(.CLK_HZ(CLK_HZ)) u_phone (
        .clk(clk_sys),.resetn(!reset && boot_done),.keys(keys),
        .mem_valid(valid),.mem_write(write),.mem_code(code),.mem_addr(address),.mem_wdata(wdata),.mem_be(be),
        .mem_ready(ready),.mem_error(error),.mem_rdata(rdata),
        .lcd_wr(lcd_wr_cpu),.lcd_dc(lcd_dc_cpu),.lcd_data(lcd_data_cpu),.unsupported_mmio(unsupported)
    );
    wire loader_req,lp_ack,lp_rvalid,cpu_req,cpu_we;
    wire [20:0] loader_addr,cpu_addr;
    wire [31:0] loader_data,cpu_data,lp_rdata,rom_first_word;
    wire [3:0] cpu_be;
    flash_boot u_boot (.clk(clk_sys),.reset(reset),.mem_ready(sdram_ready),.done(boot_done),
        .req(loader_req),.ack(lp_ack && !boot_done),.addr(loader_addr),.wdata(loader_data),.first_word(rom_first_word),
        .flash_cs_n(flash_cs_n),.flash_clk(flash_clk),.flash_mosi(flash_mosi),.flash_miso(flash_miso));
    arm_sdram_bus u_bus (.clk(clk_sys),.reset(reset || !boot_done),.valid(valid),.write(write),
        .address(address),.wdata(wdata),.be(be),.ready(ready),.error(error),.rdata(rdata),
        .lp_req(cpu_req),.lp_we(cpu_we),.lp_addr(cpu_addr),.lp_wdata(cpu_data),.lp_be(cpu_be),
        .lp_ack(lp_ack && boot_done),.lp_rvalid(lp_rvalid),.lp_rdata(lp_rdata));
    sdram_ctrl #(.INIT_WAIT(3500),.REFRESH_INTERVAL(125)) u_sdram (.clk(clk_sys),.resetn(!reset),.ready(sdram_ready),
        .cart_rd_strobe(1'b0),.cart_wr_strobe(1'b0),.cart_addr(23'd0),.cart_din(8'd0),.cart_dout(),
        .lp_block(1'b0),.pd_en(1'b0),.sr_req(1'b0),
        .lp_req(boot_done ? cpu_req : loader_req),.lp_ack(lp_ack),.lp_we(boot_done ? cpu_we : 1'b1),
        .lp_addr(boot_done ? cpu_addr : loader_addr),.lp_wdata(boot_done ? cpu_data : loader_data),
        .lp_be(boot_done ? cpu_be : 4'hf),.lp_rdata(lp_rdata),.lp_rvalid(lp_rvalid),
        .O_sdram_clk(O_sdram_clk),.O_sdram_cke(O_sdram_cke),.O_sdram_cs_n(O_sdram_cs_n),
        .O_sdram_cas_n(O_sdram_cas_n),.O_sdram_ras_n(O_sdram_ras_n),.O_sdram_wen_n(O_sdram_wen_n),
        .O_sdram_dqm(O_sdram_dqm),.O_sdram_addr(O_sdram_addr),.O_sdram_ba(O_sdram_ba),.IO_sdram_dq(IO_sdram_dq),.clk_sdram_p(clk_sys_p));
    wire fifo_ready,fifo_valid,video_ready;
    wire [8:0] fifo_data;
    async_lcd_fifo u_cdc (.wclk(clk_sys),.wrst(reset),.wvalid(lcd_wr_cpu),.wdata({lcd_dc_cpu,lcd_data_cpu}),.wready(fifo_ready),
        .rclk(clk_p),.rrst(hreset),.rready(video_ready),.rvalid(fifo_valid),.rdata(fifo_data));
    wire [9:0] cx,cy;
    wire [23:0] rgb;
    nokia_video u_video (.clk(clk_p),.reset(hreset),.lcd_wr(fifo_valid && video_ready),.lcd_dc(fifo_data[8]),.lcd_data(fifo_data[7:0]),.ready(video_ready),
        .hdmi_x(cx),.hdmi_y(cy),.rgb(rgb),.lcd_scl(lcd_scl),.lcd_sda(lcd_sda),.lcd_cs(lcd_cs),.lcd_dc_out(lcd_dc),.lcd_rst(lcd_rst),.lcd_bl(lcd_bl));
    wire [2:0] tmds;
    wire tmds_clock;
    wire [15:0] silence [1:0];
    assign silence[0]=0;assign silence[1]=0;
    hdmi #(.VIDEO_ID_CODE(2),.DVI_OUTPUT(1)) u_hdmi (.clk_pixel_x5(clk_p5),.clk_pixel(clk_p),.clk_audio(1'b0),.reset(hreset),
        .rgb(rgb),.audio_sample_word(silence),.tmds(tmds),.tmds_clock(tmds_clock),.cx(cx),.cy(cy),
        .frame_width(),.frame_height(),.screen_width(),.screen_height());
    TLVDS_OBUF u_obuf [3:0] (.I({tmds_clock,tmds}),.O({tmds_clk_p,tmds_d_p}),.OB({tmds_clk_n,tmds_d_n}));
    logic overflow;
    always_ff @(posedge clk_sys) begin
        if(reset) overflow<=0;
        else if(lcd_wr_cpu && !fifo_ready) overflow<=1;
    end
    assign led={~overflow,~boot_done};
    logic [15:0] lcd_count;
    logic bus_fault;
    always_ff @(posedge clk_sys) begin
        if(reset) begin lcd_count<=0;bus_fault<=0;end
        else begin
            if(lcd_wr_cpu) lcd_count<=lcd_count+1'b1;
            if(valid && ready && error) bus_fault<=1;
        end
    end
    uart_status #(.CLK_HZ(CLK_HZ)) u_status (.clk(clk_sys),.reset(reset),
        .flags({bus_fault,valid,!flash_cs_n,sys_lock,overflow,error,boot_done,sdram_ready}),
        .address(boot_done ? (lcd_count==0 ? rom_first_word : address) : {11'b0,loader_addr}),.lcd_count(lcd_count),.tx(uart_tx));
endmodule
