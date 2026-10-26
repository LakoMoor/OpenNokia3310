// SPDX-License-Identifier: GPL-3.0-or-later
// ROM-6 device-side boot / local-security transport, not an application HLE.
// The stock MCU firmware owns its queues, UI and self-test decisions.
// RF signal processing and a GSM network are not implemented here.
module dsp_service #(parameter CLK_HZ=27_000_000) (
    input logic clk,reset,
    input logic event_valid,
    input logic [31:0] event_address,
    input logic [15:0] event_value,
    output logic busy,fiq0,irq4,
    output logic m_valid,m_write,
    output logic [31:0] m_address,m_wdata,
    output logic [3:0] m_be,
    input logic m_ready,
    input logic [31:0] m_rdata,
    output logic [7:0] last_opcode,last_sub,
    output logic [31:0] messages,
    output logic channel_valid,
    output logic [7:0] channel_token
);
    typedef enum logic [4:0] {IDLE,TX_ISSUE,TX_WAIT,CONSUME,CONSUME_WAIT,
        RING_ISSUE,RING_WAIT,REPLY_ISSUE,REPLY_WAIT,COMMIT,COMMIT_WAIT,
        CB_CLEAR,CB_CLEAR_WAIT,CB_REQUEST,CB_REQUEST_WAIT,HOST_CLEAR,HOST_CLEAR_WAIT,
        SHORT_CLEAR,SHORT_CLEAR_WAIT} state_t;
    state_t state;
    logic tx_pending,cb_pending,host_pending,running,selftest_done;
    logic [15:0] previous_tx,tx_end;
    logic [7:0] tx_pos,tx_length,tx_opcode,tx_index;
    logic [7:0] payload [0:31];
    logic [7:0] byte_value;
    logic [2:0] kind;
    logic [7:0] reply_length,reply_index;
    logic [15:0] rx_cursor;
    logic [15:0] cb_value;
    logic [7:0] cb_block;
    logic [8:0] cb_delay;
    logic [27:0] heartbeat;
    wire [15:0] next_cursor=rx_cursor==16'he3 ? 16'h80 : rx_cursor+1'b1;
    wire [191:0] unlocked_record=192'hffffffffff0f0000009800000000000000000000087c0000;
    function automatic [7:0] response_byte(input integer i);
        begin
            response_byte=0;
            case(kind)
                1: if(i==0) response_byte=8'h0d;
                2: begin
                    if(i==0) response_byte=8'h34;
                    else if(i==1) response_byte=8'h0e;
                    else if(i>=3 && i<16) response_byte=payload[i-2];
                end
                3: begin
                    case(i)
                        0:response_byte=8'h35;
                        1:response_byte=8'h32;
                        2:response_byte=1;
                        default:begin
                            if(i>=4 && i<28) response_byte=unlocked_record[191-(i-4)*8-:8];
                            else if(i>=28 && i<52) response_byte=payload[i-26];
                        end
                    endcase
                end
                4: if(i==0) response_byte=8'h36;
                5: begin if(i==0) response_byte=8'hc8;else if(i==3) response_byte=6;end
                default: ;
            endcase
        end
    endfunction
    wire [15:0] reply_word=kind==6 ? 16'h0300 : reply_index==0 ? {reply_length,8'h74} :
        {response_byte((int'(reply_index)-1)*2),response_byte((int'(reply_index)-1)*2+1)};
    always_comb begin
        byte_value=(m_rdata>>((3-tx_pos[1:0])*8)) & 8'hff;
        busy=state!=IDLE || tx_pending || cb_pending || host_pending;
    end
    task automatic request(input bit wr,input [31:0] a,input [31:0] d,input [3:0] mask,input state_t next_state);
        begin m_valid<=1;m_write<=wr;m_address<=a;m_wdata<=d;m_be<=mask;state<=next_state;end
    endtask
    always_ff @(posedge clk) begin
        fiq0<=0;irq4<=0;
        if(cb_delay!=0) cb_delay<=cb_delay-1'b1;
        if(selftest_done && heartbeat<4*CLK_HZ) heartbeat<=heartbeat+1'b1;
        if(event_valid) begin
            case(event_address)
                32'h100a4: begin
                    if(event_value!=previous_tx) begin
                        tx_pending<=1;tx_pos<={previous_tx[6:0],1'b0};tx_end<=event_value;
                    end
                    previous_tx<=event_value;
                end
                32'h100e4:begin
                    cb_value<=event_value;
                    if(event_value!=4) begin cb_pending<=1;cb_delay<=256;end
                    else if(cb_block==8'h14) begin cb_block<=1;cb_pending<=1;cb_delay<=256;end
                    else if(cb_block==1) begin cb_block<=2;cb_pending<=1;cb_delay<=256;end
                end
                32'h30000,32'h30001: if(event_value[2]) host_pending<=1;
                default: ;
            endcase
        end
        case(state)
            IDLE:begin
                if(cb_pending && cb_delay==0) state<=CB_CLEAR;
                else if(host_pending) state<=HOST_CLEAR;
                else if(tx_pending) begin tx_index<=0;state<=TX_ISSUE;end
                else if(selftest_done && heartbeat==4*CLK_HZ) begin
                    kind<=6;reply_length<=0;state<=RING_ISSUE;
                end
            end
            TX_ISSUE:request(0,32'h10000+{24'b0,tx_pos},0,15,TX_WAIT);
            TX_WAIT:if(m_ready) begin
                m_valid<=0;
                if(tx_index==0) tx_length<=byte_value;
                else if(tx_index==1) tx_opcode<=byte_value;
                else if(tx_index-2<32) payload[tx_index-2]<=byte_value;
                tx_pos<=tx_pos==8'ha3 ? 8'd0 : tx_pos+1'b1;
                tx_index<=tx_index+1'b1;
                state<=(tx_index>=1 && tx_index=={1'b0,tx_length}+1) ? CONSUME : TX_ISSUE;
            end
            CONSUME:request(1,32'h100a6,{16'b0,tx_end},3,CONSUME_WAIT);
            CONSUME_WAIT:if(m_ready) begin
                m_valid<=0;tx_pending<=0;messages<=messages+1'b1;
                last_opcode<=tx_opcode;last_sub<=payload[0];
                channel_valid<=tx_opcode==8'h02 && tx_length>=9;
                channel_token<=payload[8]>=8'hc0 ? {7'd0,!payload[8][0]} : {7'd0,payload[6][0]};
                kind<=0;state<=IDLE;
                if(tx_opcode==8'h70) begin
                    case(payload[0])
                        8'h0d:begin kind<=1;reply_length<=2;state<=RING_ISSUE;end
                        8'h13:begin kind<=2;reply_length<=16;state<=RING_ISSUE;end
                        8'h16:begin kind<=3;reply_length<=52;state<=RING_ISSUE;end
                        8'h17:begin kind<=4;reply_length<=4;state<=RING_ISSUE;end
                        8'h0a:begin kind<=5;reply_length<=4;state<=RING_ISSUE;end
                        default: ;
                    endcase
                end
            end
            RING_ISSUE:request(0,32'h101c8,0,15,RING_WAIT);
            RING_WAIT:if(m_ready) begin
                m_valid<=0;
                if(m_rdata[31:16]==m_rdata[15:0] && m_rdata[15:0]>=16'h80 && m_rdata[15:0]<16'he4) begin
                    rx_cursor<=m_rdata[31:16];reply_index<=0;state<=REPLY_ISSUE;
                end else state<=RING_ISSUE;
            end
            REPLY_ISSUE:begin
                if(rx_cursor[0]) request(1,32'h10000+{15'b0,rx_cursor,1'b0},{16'b0,reply_word},3,REPLY_WAIT);
                else request(1,32'h10000+{15'b0,rx_cursor,1'b0},{reply_word,16'b0},12,REPLY_WAIT);
            end
            REPLY_WAIT:if(m_ready) begin
                m_valid<=0;rx_cursor<=next_cursor;reply_index<=reply_index+1'b1;
                state<=reply_index==({1'b0,reply_length}+1)/2 ? COMMIT : REPLY_ISSUE;
            end
            COMMIT:request(1,32'h101c8,{rx_cursor,16'b0},12,COMMIT_WAIT);
            COMMIT_WAIT:if(m_ready) begin
                m_valid<=0;fiq0<=1;heartbeat<=0;state<=IDLE;
                if(kind==1) selftest_done<=1;
            end
            CB_CLEAR:request(1,32'h100e4,0,12,CB_CLEAR_WAIT);
            CB_CLEAR_WAIT:if(m_ready) begin
                m_valid<=0;
                if(!running) irq4<=1;
                if(cb_value!=0) running<=1;
                if(running) state<=CB_REQUEST;
                else begin state<=IDLE;cb_pending<=0;end
            end
            CB_REQUEST:request(1,32'h100e2,{24'b0,cb_block},3,CB_REQUEST_WAIT);
            CB_REQUEST_WAIT:if(m_ready) begin m_valid<=0;cb_pending<=0;state<=IDLE;end
            HOST_CLEAR:request(1,32'h100e0,0,12,HOST_CLEAR_WAIT);
            HOST_CLEAR_WAIT:if(m_ready) begin m_valid<=0;state<=SHORT_CLEAR;end
            SHORT_CLEAR:request(1,32'h100dc,0,12,SHORT_CLEAR_WAIT);
            SHORT_CLEAR_WAIT:if(m_ready) begin m_valid<=0;host_pending<=0;state<=IDLE;end
            default:state<=IDLE;
        endcase
        if(reset) begin
            state<=IDLE;m_valid<=0;m_write<=0;m_address<=0;m_wdata<=0;m_be<=0;
            tx_pending<=0;cb_pending<=0;host_pending<=0;previous_tx<=0;tx_end<=0;
            tx_pos<=0;tx_length<=0;tx_opcode<=0;tx_index<=0;kind<=0;reply_length<=0;reply_index<=0;rx_cursor<=0;
            cb_value<=0;cb_block<=8'h14;cb_delay<=0;running<=0;selftest_done<=0;heartbeat<=0;
            fiq0<=0;irq4<=0;last_opcode<=0;last_sub<=0;messages<=0;
            channel_valid<=0;channel_token<=0;
            for(int i=0;i<32;i=i+1) payload[i]<=0;
        end
    end
endmodule
