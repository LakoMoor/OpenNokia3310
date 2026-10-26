// SPDX-License-Identifier: GPL-3.0-or-later
// ARM + implemented MAD2 peripherals. External memory must supply boot vectors,
// RAM and flash at the phone byte addresses. No boot-ROM/SDRAM loader is implied.
module nokia_core #(parameter CLK_HZ=27_000_000,VIRTUAL_NETWORK=0) (
    input logic clk, resetn,
    input logic [16:0] keys,
    output logic mem_valid, mem_write, mem_code,
    output logic [31:0] mem_addr, mem_wdata,
    output logic [3:0] mem_be,
    input logic mem_ready, mem_error,
    input logic [31:0] mem_rdata,
    output logic lcd_wr, lcd_dc,
    output logic [7:0] lcd_data,
    output logic unsupported_mmio,
    output wire [72:0] audio_control,
    output wire [31:0] debug_pc
`ifdef NOKIA_TRACE
    ,output wire [31:0] trace_pc, trace_cpsr,
    output wire [31:0] trace_regs [0:30]
    ,output wire [31:0] trace_address,trace_wdata,trace_dsp_messages,
    output wire [3:0] trace_be,
    output wire trace_write,trace_valid,trace_ready,
    output wire [7:0] trace_dsp_op,trace_dsp_sub,
    output wire [7:0] trace_dsp_length,
    output wire [95:0] trace_dsp_payload,
    output wire trace_exec,trace_exception,trace_rf_we,trace_user_bank,
    output wire [4:0] trace_rf_mode,
    output wire [3:0] trace_rf_addr,
    output wire [31:0] trace_rdata,trace_sim_commands,
    output wire [7:0] trace_sim_ins,
    output wire [31:0] trace_rf_data
    ,output wire [31:0] trace_network_packets
`endif
);
    wire valid,write,ready,irq,fiq,code;
    assign debug_pc=u_cpu.u_core.u_core.de_q.pc;
    nokia_audio_regs u_audio_regs (.clk(clk),.reset(!resetn),.write(valid && ready && write),
        .address(address),.wdata(wdata),.be(be),.control(audio_control));
    wire [31:0] address,wdata,rdata,io_rdata;
    wire [3:0] be;
    wire io_ready;
    wire nor_ready,nor_error;
    wire [31:0] nor_rdata;
    wire service_busy,dsp_fiq0,dsp_irq4;
    wire event_target=write && (address==32'h100a4 || address==32'h100e4 || address==32'h30000 || address==32'h30001);
    wire event_stall=event_target && service_busy;
    wire n_valid,n_write,n_code,n_ready;
    wire [31:0] n_address,n_wdata;
    wire [3:0] n_be;
    wire d_valid,d_write,d_ready;
    wire [31:0] d_address,d_wdata;
    wire [3:0] d_be;
    wire [31:0] dsp_messages;
    wire [7:0] dsp_last_op,dsp_last_sub;
    logic [1:0] owner;
    wire io_select=address[31:8]==24'h000200;
    // ROM-6 boot block transport. After the MCU initializes the MDI receive
    // ring, 0x10100 becomes ordinary shared RAM rather than a boot mailbox.
    logic [15:0] dsp_ack0,dsp_ack1;
    logic dsp_queue_started;
    wire dsp_mbox0=address==32'h000100fe;
    wire dsp_mbox1=address==32'h00010100 && !dsp_queue_started;
    wire dsp_status=address==32'h00010002 && !dsp_queue_started && !write;
    wire dsp_select=dsp_mbox0 || dsp_mbox1 || dsp_status;
    wire [15:0] dsp_value=be==4'hc ? wdata[31:16] : wdata[15:0];
    wire [15:0] dsp_result=dsp_mbox0 ? dsp_ack0 : dsp_mbox1 ? dsp_ack1 : 16'd0;
    wire [31:0] dsp_rdata=be==4'hc ? {dsp_result,16'b0} : {16'b0,dsp_result};
    always_ff @(posedge clk) begin
        if(!resetn) begin dsp_ack0<=0;dsp_ack1<=0;dsp_queue_started<=0; end
        else begin
            if(valid && !write && dsp_mbox0) dsp_ack0<=0;
            if(valid && !write && dsp_mbox1) dsp_ack1<=0;
            if(valid && write && dsp_mbox0) dsp_ack1<=dsp_value==0 ? 16'd1 : dsp_value;
            if(valid && write && dsp_mbox1) dsp_ack0<=dsp_value==0 ? 16'd1 : dsp_value;
            if(valid && ready && write && address==32'h000101ca && dsp_value!=0) dsp_queue_started<=1;
        end
    end
    arm7tdmi_mister #(.BIG_ENDIAN(1'b1)) u_cpu (
        .CLK(clk),.RESET_N(resetn),.CPU_CE(1'b1),.IRQ_ASYNC(irq),.FIQ_ASYNC(fiq),
        .MEM_VALID(valid),.MEM_READY(ready),.MEM_ADDR(address),.MEM_WRITE(write),
        .MEM_WDATA(wdata),.MEM_BYTE_ENABLE(be),.MEM_RDATA(rdata),
        .MEM_ERROR(!io_select && !dsp_select && nor_error),
        .MEM_CODE(code),.MEM_PRIVILEGED(),.MEM_LOCK(),.MEM_SEQUENTIAL(),.MEM_MORE(),
        .CPA(1'b1),.CPB(1'b1),.CPnMREQ(),.CPSEQ(),.CPnTRANS(),.CPnOPC(),.CPTBIT(),.CPnI(),
        .DEBUG_ENABLE_ASYNC(1'b0),.DBGRQ_ASYNC(1'b0),.DBGBREAK_ASYNC(1'b0),.DBGEXT_ASYNC(2'b0),
        .DBG_STEP_VALID(1'b0),.DBG_STEP_READY(),.DBG_STEP_TMS(1'b1),.DBG_STEP_TDI(1'b0),
        .DBG_STEP_RSP_VALID(),.DBG_STEP_RSP_READY(1'b1),.DBG_STEP_TDO(),.DBG_STEP_TDO_OE(),
        .DBGACK(),.DBGnEXEC(),.DBGINSTRVALID(),.DBGRNG(),.DBGCOMMTX(),.DBGCOMMRX()
    );
    mad2_mmio #(.CLK_HZ(CLK_HZ)) u_mmio (.clk(clk),.reset(!resetn),.valid(valid && io_select),.write(write),
        .address(address[7:0]),.wdata(wdata),.byte_enable(be),.ready(io_ready),.rdata(io_rdata),
        .keys(keys),.dsp_fiq0(dsp_fiq0),.dsp_irq4(dsp_irq4),.irq(irq),.fiq(fiq),.lcd_wr(lcd_wr),.lcd_dc(lcd_dc),.lcd_data(lcd_data),.unsupported(unsupported_mmio));
    nor_bus u_nor (.clk(clk),.reset(!resetn),.valid(valid && !io_select && !dsp_select && !event_stall),.write(write),.code(code),
        .address(address),.wdata(wdata),.be(be),.ready(nor_ready),.error(nor_error),.rdata(nor_rdata),
        .m_valid(n_valid),.m_write(n_write),.m_code(n_code),.m_address(n_address),.m_wdata(n_wdata),.m_be(n_be),
        .m_ready(n_ready),.m_error(mem_error),.m_rdata(mem_rdata));
    dsp_network #(.CLK_HZ(CLK_HZ),.ENABLE_NETWORK(VIRTUAL_NETWORK)) u_dsp (.clk(clk),.reset(!resetn),
        .event_valid(valid && ready && event_target),.event_address(address),.event_value(dsp_value),
        .busy(service_busy),.fiq0(dsp_fiq0),.irq4(dsp_irq4),.m_valid(d_valid),.m_write(d_write),.m_address(d_address),
        .m_wdata(d_wdata),.m_be(d_be),.m_ready(d_ready),.m_rdata(mem_rdata),
        .messages(dsp_messages),.last_opcode(dsp_last_op),.last_sub(dsp_last_sub));
    always_ff @(posedge clk) begin
        if(!resetn) owner<=0;
        else if(owner==0) begin
            if(d_valid) owner<=2;
            else if(n_valid) owner<=1;
        end else if(mem_valid && mem_ready) owner<=0;
    end
    assign mem_valid=owner==1 ? n_valid : owner==2 ? d_valid : 1'b0;
    assign mem_write=owner==2 ? d_write : n_write;
    assign mem_code=owner==1 && n_code;
    assign mem_addr=owner==2 ? d_address : n_address;
    assign mem_wdata=owner==2 ? d_wdata : n_wdata;
    assign mem_be=owner==2 ? d_be : n_be;
    assign n_ready=owner==1 && mem_ready;
    assign d_ready=owner==2 && mem_ready;
    assign ready=io_select ? io_ready : dsp_select ? 1'b1 : !event_stall && nor_ready;
    assign rdata=io_select ? io_rdata : dsp_select ? dsp_rdata : nor_rdata;
`ifdef NOKIA_TRACE
    assign trace_network_packets=u_dsp.network_packets;
    assign trace_rdata=rdata;
    assign trace_exec=u_cpu.u_core.u_core.executing && u_cpu.u_core.u_core.CLKEN && u_cpu.u_core.u_core.condition_pass;
    assign trace_sim_commands=u_mmio.u_sim.commands;
    assign trace_sim_ins=u_mmio.u_sim.last_ins;
    assign trace_exception=u_cpu.u_core.u_core.any_exc_fires;
    assign trace_rf_we=u_cpu.u_core.u_core.rf_write_en;
    assign trace_user_bank=u_cpu.u_core.u_core.force_user_bank_eff;
    assign trace_rf_mode=u_cpu.u_core.u_core.regfile_mode_eff;
    assign trace_rf_addr=u_cpu.u_core.u_core.rf_write_addr;
    assign trace_rf_data=u_cpu.u_core.u_core.rf_write_data;
    assign trace_pc=u_cpu.u_core.u_core.de_q.pc;
    assign trace_cpsr=u_cpu.u_core.u_core.cpsr;
    assign trace_address=address;assign trace_wdata=wdata;assign trace_be=be;
    assign trace_write=write;assign trace_valid=valid;assign trace_ready=ready;
    assign trace_dsp_messages=dsp_messages;assign trace_dsp_op=dsp_last_op;assign trace_dsp_sub=dsp_last_sub;
    assign trace_dsp_length=u_dsp.service.tx_length;
    for(genvar b=0;b<12;b=b+1)
        assign trace_dsp_payload[95-b*8-:8]=u_dsp.service.payload[b];
    for(genvar i=0;i<31;i=i+1) assign trace_regs[i]=u_cpu.u_core.u_core.u_regfile.regs[i];
`endif
endmodule
