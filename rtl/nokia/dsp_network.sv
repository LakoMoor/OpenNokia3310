// SPDX-License-Identifier: GPL-3.0-or-later
// DSP transport with optional virtual-cell search response. Experimental:
// SCH/SI3 delivery is not full registration or a GSM call/SMS implementation.
module dsp_network #(parameter CLK_HZ=27000000,ENABLE_NETWORK=0) (
    input logic clk,reset,event_valid,
    input logic [31:0] event_address,
    input logic [15:0] event_value,
    output wire busy,fiq0,irq4,m_valid,m_write,
    output wire [31:0] m_address,m_wdata,
    output wire [3:0] m_be,
    input logic m_ready,
    input logic [31:0] m_rdata,
    output wire [7:0] last_opcode,last_sub,
    output wire [31:0] messages,network_packets
);
    wire service_busy,service_fiq,service_valid,service_write;
    wire [31:0] service_address,service_data;
    wire [3:0] service_be;
    wire net_lock,net_valid,net_write,net_fiq;
    wire [31:0] net_address,net_data;
    wire [3:0] net_be;
    dsp_service #(.CLK_HZ(CLK_HZ)) service(.clk(clk),.reset(reset),.event_valid(event_valid && !net_lock),
        .event_address(event_address),.event_value(event_value),.busy(service_busy),.fiq0(service_fiq),.irq4(irq4),
        .m_valid(service_valid),.m_write(service_write),.m_address(service_address),.m_wdata(service_data),
        .m_be(service_be),.m_ready(m_ready && !net_lock),.m_rdata(m_rdata),
        .last_opcode(last_opcode),.last_sub(last_sub),.messages(messages));
    assign busy=service_busy || net_lock;
    assign fiq0=service_fiq || net_fiq;
    assign m_valid=net_lock ? net_valid : service_valid;
    assign m_write=net_lock ? net_write : service_write;
    assign m_address=net_lock ? net_address : service_address;
    assign m_wdata=net_lock ? net_data : service_data;
    assign m_be=net_lock ? net_be : service_be;
    generate if(ENABLE_NETWORK)begin: network
        logic lock,start,pending,bcch;
        logic [1:0] si_kind;
        logic [31:0] seen_messages;
        logic [31:0] packets;
        assign network_packets=packets;
        logic [25:0] delay_count;
        logic [21:0] frame_number;
        logic [31:0] frame_phase;
        wire byte_valid,byte_last,byte_ready,packet_done,packet_error;
        wire [7:0] byte_data;
        assign net_lock=lock;
        virtual_cell cell_source(.clk(clk),.reset(reset),.start(start),.bcch(bcch),.si_kind(si_kind),.plmn(24'h00f110),
            .lac(16'h0001),.cell_id(16'h0001),.arfcn(10'd586),.bsic(6'd0),.frame_number(frame_number),
            .ready(byte_ready),.valid(byte_valid),.last(byte_last),.data(byte_data),.busy(),.done());
        mdi_injector injector(.clk(clk),.reset(reset),.in_valid(byte_valid),.in_last(byte_last),.in_data(byte_data),
            .in_ready(byte_ready),.busy(),.done(packet_done),.error(packet_error),.fiq0(net_fiq),
            .m_valid(net_valid),.m_write(net_write),.m_address(net_address),.m_wdata(net_data),.m_be(net_be),
            .m_ready(m_ready && lock),.m_rdata(m_rdata));
        always_ff @(posedge clk)begin
            start<=0;
            // One GSM TDMA frame = 60/13000 seconds; preserve fractional clocks.
            if(frame_phase+13000>=CLK_HZ*60)begin
                frame_phase<=frame_phase+13000-CLK_HZ*60;
                frame_number<=frame_number==2715647 ? 22'd0 : frame_number+1'b1;
            end else frame_phase<=frame_phase+13000;
            if(messages!=seen_messages)begin
                seen_messages<=messages;
                if(last_opcode==8'h56)begin pending<=1;bcch<=0;si_kind<=0;delay_count<=0;end
            end
            if(delay_count!=0)begin
                delay_count<=delay_count-1'b1;
                if(delay_count==1)pending<=1;
            end
            if(pending && !lock && !service_busy && !event_valid)begin lock<=1;pending<=0;start<=1;end
            if(packet_done || packet_error)begin
                lock<=0;
                if(!packet_error)begin bcch<=1;if(bcch)si_kind<=si_kind==2 ? 2'd0 : si_kind+1'b1;delay_count<=CLK_HZ/4;packets<=packets+1'b1;end
            end
            if(reset)begin lock<=0;start<=0;pending<=0;bcch<=0;si_kind<=0;seen_messages<=0;delay_count<=0;frame_phase<=0;frame_number<=0;packets<=0;end
        end
    end else begin: disabled
        assign net_lock=0;assign net_valid=0;assign net_write=0;assign net_fiq=0;
        assign net_address=0;assign net_data=0;assign net_be=0;
        assign network_packets=0;
    end endgenerate
endmodule
