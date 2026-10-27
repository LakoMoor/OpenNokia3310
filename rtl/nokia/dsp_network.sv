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
    wire channel_valid,rach_valid,uplink_valid;
    wire [4:0] uplink_length;
    wire [7:0] uplink_logch;
    wire [183:0] uplink_frame;
    wire [47:0] rach_payload;
    wire [7:0] channel_token,channel_logch;
    wire net_lock,net_valid,net_write,net_fiq;
    wire [31:0] net_address,net_data;
    wire [3:0] net_be;
    dsp_service #(.CLK_HZ(CLK_HZ)) service(.clk(clk),.reset(reset),.event_valid(event_valid && !net_lock),
        .event_address(event_address),.event_value(event_value),.busy(service_busy),.fiq0(service_fiq),.irq4(irq4),
        .m_valid(service_valid),.m_write(service_write),.m_address(service_address),.m_wdata(service_data),
        .m_be(service_be),.m_ready(m_ready && !net_lock),.m_rdata(m_rdata),
        .last_opcode(last_opcode),.last_sub(last_sub),.messages(messages),
        .channel_valid(channel_valid),.channel_token(channel_token),.channel_logch(channel_logch),.rach_valid(rach_valid),.rach_payload(rach_payload),.uplink_valid(uplink_valid),.uplink_length(uplink_length),.uplink_logch(uplink_logch),.uplink_frame(uplink_frame));
    assign busy=service_busy || net_lock;
    assign fiq0=service_fiq || net_fiq;
    assign m_valid=net_lock ? net_valid : service_valid;
    assign m_write=net_lock ? net_write : service_write;
    assign m_address=net_lock ? net_address : service_address;
    assign m_wdata=net_lock ? net_data : service_data;
    assign m_be=net_lock ? net_be : service_be;
    generate if(ENABLE_NETWORK)begin: network
        logic lock,start,pending,bcch;
        logic dedicated_enabled,fill_pending,block_pending,dedicated_packet,block_packet;
        logic dedicated_has_fill;
        logic ua_pending,ua_packet,mm_packet,mm_allowed;
        wire mm_valid,mm_ready;
        wire [183:0] mm_frame;
        assign mm_ready=start && dedicated_packet && mm_packet;
        mm_registration mm_peer(.clk(clk),.reset(reset || (messages!=seen_messages && channel_valid && channel_logch==8'h80)),
            .uplink_valid(messages!=seen_messages && uplink_valid && uplink_logch==8'h80 && dedicated_enabled),
            .uplink_frame(uplink_frame),.uplink_length(uplink_length),.plmn(24'h00f110),.lac(16'd1),
            .downlink_ready(mm_ready),.downlink_valid(mm_valid),.downlink_frame(mm_frame),.registered());
        logic [183:0] ua_frame;
        logic [7:0] ua_channel;
        wire ua_done,ua_accepted;
        wire [183:0] ua_response;
        lapdm_ua ua_builder(.clk(clk),.reset(reset),.start(messages!=seen_messages && uplink_valid && uplink_logch==8'h80),
            .frame(uplink_frame),.frame_length(uplink_length),.done(ua_done),.accepted(ua_accepted),.response(ua_response),.information_length());
        logic [21:0] fill_fn;
        logic access_pending,grant_pending,access_packet,grant_packet,rach_active;
        logic [7:0] access_ra;
        logic [21:0] access_fn;
        logic [25:0] grant_delay;
        logic confirm_pending,confirm_packet,rssi_pending,rssi_packet;
        logic [7:0] confirm_token;
        logic psw_pending,psw_packet,psw_sent;
        logic [1:0] si_kind;
        logic [31:0] seen_messages;
        logic [31:0] packets;
        assign network_packets=packets;
        logic [25:0] delay_count;
        logic [21:0] frame_number;
        logic [31:0] frame_phase;
        function automatic [21:0] next_ccch(input [21:0] fn);
            reg [5:0] t3;
            reg [5:0] offset;
            reg [22:0] candidate;
            begin
                t3=6'(fn%51);
                if(t3<=6)offset=6;else if(t3<=12)offset=12;
                else if(t3<=16)offset=16;else if(t3<=22)offset=22;
                else if(t3<=26)offset=26;else if(t3<=32)offset=32;
                else if(t3<=36)offset=36;else if(t3<=42)offset=42;
                else if(t3<=46)offset=46;else offset=57;
                candidate={1'b0,fn}-{17'd0,t3}+{17'd0,offset};
                next_ccch=22'(candidate>=2715648 ? candidate-2715648 : candidate);
            end
        endfunction
        wire byte_valid,byte_last,byte_ready,packet_done,packet_error;
        wire cell_valid,cell_last,access_valid,access_last,ded_valid,ded_last;
        wire [7:0] cell_data,access_data,ded_data;
        assign byte_valid=dedicated_packet ? ded_valid : access_packet ? access_valid : cell_valid;
        assign byte_last=dedicated_packet ? ded_last : access_packet ? access_last : cell_last;
        assign byte_data=dedicated_packet ? ded_data : access_packet ? access_data : cell_data;
        virtual_dedicated dedicated_source(.clk(clk),.reset(reset),.start(start && dedicated_packet),
            .request_block(block_packet),.custom_frame(ua_packet || mm_packet),.frame(mm_packet ? mm_frame : ua_frame),.logch(mm_packet ? 8'h80 : ua_channel),.frame_number(fill_fn),.arfcn(10'd586),.bsic(6'd0),
            .ready(byte_ready && dedicated_packet),.valid(ded_valid),.last(ded_last),.data(ded_data),.busy(),.done());
        virtual_access access_source(.clk(clk),.reset(reset),.start(start && access_packet),.grant(grant_packet),
            .ra(access_ra),.request_fn(access_fn),.block_fn(next_ccch(frame_number)),.arfcn(10'd586),.bsic(6'd0),
            .ready(byte_ready && access_packet),.valid(access_valid),.last(access_last),.data(access_data),.busy(),.done());
        wire [7:0] byte_data;
        assign net_lock=lock;
        virtual_cell cell_source(.clk(clk),.reset(reset),.start(start && !access_packet && !dedicated_packet),.bcch(bcch),.channel_confirm(confirm_packet),.confirm_token(confirm_token),.all_rssi(rssi_packet),.no_psw(psw_packet),.si_kind(si_kind),.plmn(24'h00f110),
            .lac(16'h0001),.cell_id(16'h0001),.arfcn(10'd586),.bsic(6'd0),.frame_number(frame_number),
            .ready(byte_ready && !access_packet && !dedicated_packet),.valid(cell_valid),.last(cell_last),.data(cell_data),.busy(),.done());
        mdi_injector injector(.clk(clk),.reset(reset),.in_valid(byte_valid),.in_last(byte_last),.in_data(byte_data),
            .in_ready(byte_ready),.busy(),.done(packet_done),.error(packet_error),.fiq0(net_fiq),
            .m_valid(net_valid),.m_write(net_write),.m_address(net_address),.m_wdata(net_data),.m_be(net_be),
            .m_ready(m_ready && lock),.m_rdata(m_rdata));
        always_ff @(posedge clk)begin
            start<=0;
            if(ua_done && ua_accepted)begin ua_frame<=ua_response;ua_channel<=uplink_logch;ua_pending<=1;mm_allowed<=0;end
            // One GSM TDMA frame = 60/13000 seconds; preserve fractional clocks.
            if(frame_phase+13000>=CLK_HZ*60)begin
                frame_phase<=frame_phase+13000-CLK_HZ*60;
                if(dedicated_enabled)begin
                    if(frame_number%51==50)begin fill_pending<=1;fill_fn<=frame_number==2715647 ? 22'd0 : frame_number+1'b1;end
                    if(frame_number%51==14 && dedicated_has_fill)block_pending<=1;
                end
                frame_number<=frame_number==2715647 ? 22'd0 : frame_number+1'b1;
            end else frame_phase<=frame_phase+13000;
            if(messages!=seen_messages)begin
                seen_messages<=messages;
                if(last_opcode==8'h56)begin pending<=1;bcch<=0;si_kind<=0;delay_count<=0;psw_sent<=0;end
                if(last_opcode==8'h55)rssi_pending<=1;
                if(rach_valid)begin
                    rach_active<=1;access_pending<=1;access_ra<=rach_payload[31:24];
                    // A later RACH report may carry the actual transmitted FN.
                    // Cancel an unsent grant and report the updated reference.
                    grant_pending<=0;grant_delay<=0;
                    access_fn<=rach_payload[39:32]==1 ? {6'd0,rach_payload[15:0]} :
                        22'((frame_number+{14'd0,rach_payload[23:16]})%42432);
                end
                if(channel_valid)begin
                    confirm_pending<=1;confirm_token<=channel_token;
                    dedicated_enabled<=channel_logch==8'h80;
                    dedicated_has_fill<=0;
                    if(channel_logch!=8'h80)begin fill_pending<=0;block_pending<=0;ua_pending<=0;end
                    if(channel_logch==8'h50 && !psw_sent)begin psw_pending<=1;psw_sent<=1;end
                end
            end
            if(grant_delay!=0 && !(messages!=seen_messages && rach_valid))begin
                grant_delay<=grant_delay-1'b1;
                if(grant_delay==1)grant_pending<=1;
            end
            if(delay_count!=0)begin
                delay_count<=delay_count-1'b1;
                if(delay_count==1)pending<=1;
            end
            if((pending || confirm_pending || rssi_pending || psw_pending || access_pending || grant_pending || fill_pending || block_pending) && !lock && !service_busy && !event_valid && messages==seen_messages)begin
                lock<=1;start<=1;
                dedicated_packet<=!access_pending && !grant_pending && !psw_pending && !confirm_pending && !rssi_pending && (fill_pending || block_pending);
                block_packet<=!fill_pending && block_pending;
                ua_packet<=ua_pending && fill_pending;
                mm_packet<=!ua_pending && mm_allowed && mm_valid && fill_pending;
                if(!access_pending && !grant_pending && !psw_pending && !confirm_pending && !rssi_pending && fill_pending && ua_pending)ua_pending<=0;
                access_packet<=access_pending || grant_pending;grant_packet<=!access_pending && grant_pending;
                psw_packet<=psw_pending;confirm_packet<=!psw_pending && confirm_pending;rssi_packet<=!psw_pending && !confirm_pending && rssi_pending;
                if(access_pending)access_pending<=0;
                else if(grant_pending)grant_pending<=0;
                else if(psw_pending)psw_pending<=0;
                else if(confirm_pending)confirm_pending<=0;
                else if(rssi_pending)rssi_pending<=0;
                else if(fill_pending)fill_pending<=0;
                else if(block_pending)block_pending<=0;
                else pending<=0;
            end
            if(packet_done || packet_error)begin
                lock<=0;
                if(!packet_error)begin
                    packets<=packets+1'b1;
                    if(dedicated_packet && !block_packet)dedicated_has_fill<=1;
                    if(dedicated_packet && ua_packet)mm_allowed<=1;
                    if(access_packet)begin
                        if(grant_packet)rach_active<=0;
                        else grant_delay<=CLK_HZ/10;
                    end
                    if(!dedicated_packet && !access_packet && !confirm_packet && !rssi_packet && !psw_packet)begin bcch<=1;if(bcch)si_kind<=si_kind==2 ? 2'd0 : si_kind+1'b1;delay_count<=CLK_HZ/4;end
                end
            end
            if(reset)begin
                access_pending<=0;grant_pending<=0;access_packet<=0;grant_packet<=0;rach_active<=0;
                access_ra<=0;access_fn<=0;grant_delay<=0;
                ua_pending<=0;ua_packet<=0;mm_packet<=0;mm_allowed<=0;ua_frame<=0;ua_channel<=0;
                dedicated_enabled<=0;dedicated_has_fill<=0;fill_pending<=0;block_pending<=0;dedicated_packet<=0;block_packet<=0;fill_fn<=0;
                lock<=0;start<=0;pending<=0;bcch<=0;confirm_pending<=0;confirm_packet<=0;confirm_token<=0;rssi_pending<=0;rssi_packet<=0;psw_pending<=0;psw_packet<=0;psw_sent<=0;si_kind<=0;seen_messages<=0;delay_count<=0;frame_phase<=0;frame_number<=0;packets<=0;end
        end
    end else begin: disabled
        assign net_lock=0;assign net_valid=0;assign net_write=0;assign net_fiq=0;
        assign net_address=0;assign net_data=0;assign net_be=0;
        assign network_packets=0;
    end endgenerate
endmodule
