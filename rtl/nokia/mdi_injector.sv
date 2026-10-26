// SPDX-License-Identifier: GPL-3.0-or-later
// Queued device record -> firmware-owned D2M ring. Requires exclusive DSP bus
// ownership while busy; caller must arbitrate against dsp_service.
module mdi_injector (
    input logic clk,reset,
    input logic in_valid,in_last,
    input logic [7:0] in_data,
    output logic in_ready,busy,done,error,fiq0,
    output logic m_valid,m_write,
    output logic [31:0] m_address,m_wdata,
    output logic [3:0] m_be,
    input logic m_ready,
    input logic [31:0] m_rdata
);
    typedef enum logic [3:0] {COLLECT,DROP,CHECK,RING,WAIT_RING,WORD,WAIT_WORD,COMMIT,WAIT_COMMIT,FINISH} state_t;
    state_t state;
    logic [7:0] buffer[0:63];
    logic [6:0] count,bytes_count;
    logic [5:0] word_index;
    logic [15:0] cursor;
    wire [15:0] following=cursor==16'he3 ? 16'h80 : cursor+1'b1;
    wire [6:0] byte_index={word_index,1'b0};
    wire [15:0] word_data={buffer[byte_index[5:0]],byte_index+1<bytes_count ? buffer[(byte_index+1)&63] : 8'd0};
    assign in_ready=state==COLLECT || state==DROP;
    assign busy=state!=COLLECT || count!=0;
    task automatic request(input bit wr,input [31:0] address,data,input [3:0] lanes,input state_t next);
        begin m_valid<=1;m_write<=wr;m_address<=address;m_wdata<=data;m_be<=lanes;state<=next;end
    endtask
    always_ff @(posedge clk)begin
        done<=0;error<=0;fiq0<=0;
        case(state)
            COLLECT:if(in_valid)begin
                buffer[count[5:0]]<=in_data;
                if(in_last)begin bytes_count<=count+1'b1;count<=0;state<=CHECK;end
                else if(count==63)begin count<=0;state<=DROP;end
                else count<=count+1'b1;
            end
            DROP:if(in_valid && in_last)begin state<=COLLECT;error<=1;end
            CHECK:begin
                if(bytes_count<2 || bytes_count!={1'b0,buffer[0]}+2 || buffer[0]>62)begin error<=1;state<=COLLECT;end
                else state<=RING;
            end
            RING:request(0,32'h101c8,0,15,WAIT_RING);
            WAIT_RING:if(m_ready)begin
                m_valid<=0;
                // High half is the DSP producer; low half belongs to the MCU.
                if(m_rdata[31:16]==m_rdata[15:0] && m_rdata[15:0]>=16'h80 && m_rdata[15:0]<16'he4)begin
                    cursor<=m_rdata[31:16];word_index<=0;state<=WORD;
                end else state<=RING;
            end
            WORD:if(cursor[0])request(1,32'h10000+{15'b0,cursor,1'b0},{16'b0,word_data},3,WAIT_WORD);
                 else request(1,32'h10000+{15'b0,cursor,1'b0},{word_data,16'b0},12,WAIT_WORD);
            WAIT_WORD:if(m_ready)begin
                m_valid<=0;cursor<=following;word_index<=word_index+1'b1;
                state<=({word_index,1'b0}+2>=bytes_count) ? COMMIT : WORD;
            end
            COMMIT:request(1,32'h101c8,{cursor,16'b0},12,WAIT_COMMIT);
            WAIT_COMMIT:if(m_ready)begin m_valid<=0;state<=FINISH;end
            FINISH:begin fiq0<=1;done<=1;state<=COLLECT;end
            default:state<=COLLECT;
        endcase
        if(reset)begin state<=COLLECT;count<=0;bytes_count<=0;word_index<=0;cursor<=0;
            m_valid<=0;m_write<=0;m_address<=0;m_wdata<=0;m_be<=0;done<=0;error<=0;fiq0<=0;end
    end
endmodule
