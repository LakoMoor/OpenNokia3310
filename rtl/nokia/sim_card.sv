// SPDX-License-Identifier: GPL-3.0-or-later
// Local synthetic GSM SIM: paced SIMI UART, T=0, PIN-disabled filesystem.
// Device protocol follows the DCT3 reference model; no subscriber key or RF.
module sim_card #(parameter CLK_HZ=27_000_000) (
    input logic clk,reset,valid,write,
    input logic [7:0] address,wdata,
    output logic [7:0] rdata,
    output logic fiq,
    output logic [31:0] commands,
    output logic [7:0] last_ins
);
    `include "rtl/nokia/sim_fixture.svh"
    logic [7:0] files[0:4095];
    initial $readmemh("rtl/nokia/sim_fixture.hex",files);
    logic [7:0] header[0:4];
    logic [7:0] payload[0:255];
    logic [7:0] payload_q,fid_hi,fid_lo,rx_q;
    logic [8:0] count;
    logic dirty,acked;
    logic [7:0] control,clock_control,low_water,rx_flush,tx_flush,interrupts;
    logic [7:0] rx[0:511];
    logic [9:0] wr_ptr,read_ptr,visible_ptr;
    logic [25:0] pace;
    logic [15:0] selected,selected_df,fcp_fid;
    logic fcp_directory;
    typedef enum logic [3:0] {IDLE,PARSE,ATR,ACK,OUT_ACK,DATA_PREP,DATA,SW1,SW2,UPDATE_PREP,UPDATE,CHV_WAIT} state_t;
    state_t state;
    logic [8:0] index,length;
    logic [7:0] status1,status2,ins;
    logic [15:0] offset;
    logic [7:0] current_record;
    logic [8:0] requested_length;
    logic [15:0] requested_offset;
    logic [7:0] requested_record;
    logic [1:0] data_kind;
    logic chv_start;
    wire chv_done,pin1_enabled;
    wire [1:0] pin_verified;
    wire [15:0] chv_status;
    wire [7:0] pin1_status,pin2_status,puk1_status,puk2_status;
    wire card_reset=valid && write && address==8'h39 && (!wdata[7] || !control[7]);
    wire protected_file=selected==16'h6f07 || selected==16'h6f3a || selected==16'h6f3c;
    sim_chv u_chv(.clk(clk),.reset(reset || card_reset),.start(chv_start),.instruction(ins),
        .p1(header[2]),.p2(header[3]),.length(header[4]),
        .presented({payload[0],payload[1],payload[2],payload[3],payload[4],payload[5],payload[6],payload[7]}),
        .replacement({payload[8],payload[9],payload[10],payload[11],payload[12],payload[13],payload[14],payload[15]}),
        .done(chv_done),.status_word(chv_status),.pin1_enabled(pin1_enabled),.verified(pin_verified),
        .pin1_status(pin1_status),.pin2_status(pin2_status),.puk1_status(puk1_status),.puk2_status(puk2_status));
    wire [8:0] visible_count=9'(visible_ptr-read_ptr);
    wire active=control[7];
    wire [15:0] select_fid={fid_hi,fid_lo};
    wire select_dir=select_fid==16'h3f00 || select_fid==16'h7f20 || select_fid==16'h7f10;
    wire has_input=ins==8'ha4 || ins==8'h20 || ins==8'h24 || ins==8'h26 ||
        ins==8'h28 || ins==8'h2c || ins==8'hdc || ins==8'hd6 || ins==8'h10 ||
        ins==8'h14 || ins==8'hc2 || ins==8'h88 || ins==8'ha2 || ins==8'h32;
    always_comb begin
        requested_length=header[4]==0 && (ins==8'hb0 || ins==8'hb2) ? 9'd256 : {1'b0,header[4]};
        requested_record=header[2];
        if(header[3][2:0]==2)requested_record=current_record+1'b1;
        else if(header[3][2:0]==3)requested_record=current_record>1 ? current_record-1'b1 : 8'd0;
        else if(header[2]==0)requested_record=current_record;
        requested_offset=(ins==8'hb0 || ins==8'hd6) ? {header[2],header[3]} :
            (requested_record==0 ? 16'd0 : {8'b0,requested_record}-1'b1)*{8'b0,ef_record(selected)};
    end
    function automatic [7:0] fcp_byte(input [15:0] fid,input bit directory,input [8:0] i);
        reg [11:0] size;
        begin
            size=ef_size(fid);fcp_byte=0;
            case(i)
                2:fcp_byte=directory ? 0 : {4'b0,size[11:8]};
                3:fcp_byte=directory ? 0 : size[7:0];
                4:fcp_byte=fid[15:8];5:fcp_byte=fid[7:0];
                6:fcp_byte=directory ? (fid==16'h3f00 ? 1 : 2) : 4;
                8:fcp_byte=directory ? 0 : ((fid==16'h6f07 || fid==16'h6f3a || fid==16'h6f3c) ? 8'h11 : 8'h00);
                9:fcp_byte=directory ? 0 : 8'hff;
                10:fcp_byte=directory ? 0 : 8'h55;
                11:fcp_byte=directory ? 0 : 1;
                12:fcp_byte=directory ? 8'h15 : 2;
                13:fcp_byte=directory ? (pin1_enabled ? 8'h01 : 8'h81) : (ef_record(fid)!=0 ? 1 : 0);
                14:fcp_byte=directory ? 0 : ef_record(fid);
                15:if(directory) fcp_byte=8'h16;
                16:if(directory) fcp_byte=3;
                18:if(directory)fcp_byte=pin1_status;
                19:if(directory)fcp_byte=puk1_status;
                20:if(directory)fcp_byte=pin2_status;
                21:if(directory)fcp_byte=puk2_status;
                default: ;
            endcase
        end
    endfunction
    logic [7:0] file_q;
    always_ff @(posedge clk) begin
        file_q<=files[ef_base(selected)+12'(offset+index)];
        payload_q<=payload[index[7:0]];
        rx_q<=rx[read_ptr[8:0]];
    end
    wire [7:0] data_byte=data_kind==0 ? fcp_byte(fcp_fid,fcp_directory,index) :
        offset+index<ef_size(selected) ? file_q : 8'hff;
    always_comb begin
        fiq=|(interrupts & 8'h50);
        case(address)
            8'h36:rdata=0;
            8'h37:rdata=visible_count==0 ? 8'hff : rx_q;
            8'h38:rdata=interrupts;
            8'h39:rdata=(control & 8'hbf)|(active ? 8'h40 : 0);
            8'h3a:rdata=clock_control;
            8'h3b:rdata=low_water;
            8'h3c:rdata=visible_count>255 ? 8'hff : visible_count[7:0];
            8'h3d:rdata=rx_flush;
            8'h3e:rdata=tx_flush;
            default:rdata=0;
        endcase
    end
    wire rx_emit=state==ATR || state==ACK || state==OUT_ACK || state==DATA || state==SW1 || state==SW2;
    logic [7:0] rx_in;
    always_comb case(state)
        ATR:rx_in=index==0 ? 8'h3b : index==1 ? 8'h60 : 8'd0;
        ACK,OUT_ACK:rx_in=ins;
        DATA:rx_in=data_byte;
        SW1:rx_in=status1;
        default:rx_in=status2;
    endcase
    always_ff @(posedge clk) if(rx_emit && !reset) rx[wr_ptr[8:0]]<=rx_in;
    always_ff @(posedge clk) begin
        chv_start<=0;
        if(rx_emit) wr_ptr<=wr_ptr+1'b1;
        if(pace!=0) pace<=pace-1'b1;
        else if(visible_ptr!=wr_ptr && visible_ptr==read_ptr) begin
            visible_ptr<=visible_ptr+1'b1;interrupts[6]<=1;pace<=CLK_HZ/960-1;
        end
        if(valid && !write && address==8'h37 && visible_count!=0) begin
            read_ptr<=read_ptr+1'b1;
            if(visible_count==1) interrupts[6]<=0;
        end
        if(valid && write) case(address)
            8'h36:if(count<261) begin
                if(count<5) header[count[2:0]]<=wdata;
                else payload[count[7:0]-8'd5]<=wdata;
                if(count==5) fid_hi<=wdata;
                if(count==6) fid_lo<=wdata;
                count<=count+1'b1;dirty<=1;
            end
            8'h38:interrupts<=interrupts & ~wdata;
            8'h39:begin
                control<=wdata;
                if(wdata[7] && !control[7]) begin
                    count<=0;dirty<=0;acked<=0;wr_ptr<=0;read_ptr<=0;visible_ptr<=0;
                    interrupts<=0;pace<=CLK_HZ/960;index<=0;state<=ATR;
                    selected<=16'h3f00;selected_df<=16'h3f00;
                end
            end
            8'h3a:clock_control<=wdata;
            8'h3b:low_water<=wdata;
            8'h3d:rx_flush<=wdata;
            8'h3e:begin
                tx_flush<=wdata;
                if(wdata==0 && tx_flush!=0 && dirty) begin
                    dirty<=0;interrupts[4]<=1;ins<=header[1];state<=PARSE;
                end
            end
            default: ;
        endcase
        case(state)
            IDLE: ;
            ATR:begin
                index<=index+1'b1;if(index==3) state<=IDLE;
            end
            PARSE:begin
                state<=IDLE;
                if(count>=5) begin
                    if(has_input && count<9'd5+{1'b0,header[4]}) begin
                        if(!acked) begin acked<=1;state<=ACK;end
                    end else begin
                        commands<=commands+1'b1;last_ins<=ins;
                        count<=0;acked<=0;index<=0;length<=0;offset<=0;
                        status1<=8'h90;status2<=0;state<=SW1;
                        case(ins)
                            8'ha4:begin
                                if(select_dir || ef_size(select_fid)!=0) begin
                                    selected<=select_fid;fcp_fid<=select_fid;fcp_directory<=select_dir;
                                    current_record<=0;
                                    if(select_dir) selected_df<=select_fid;
                                    status1<=8'h9f;status2<=select_dir ? 34 : 15;
                                end else begin status1<=8'h94;status2<=4;end
                            end
                            8'hc0,8'hf2:begin
                                data_kind<=0;state<=OUT_ACK;
                                if(ins==8'hf2) begin fcp_fid<=selected_df;fcp_directory<=1;end
                                length<=header[4]!=0 && header[4]<(ins==8'hf2 || fcp_directory ? 34 : 15) ?
                                    {1'b0,header[4]} : (ins==8'hf2 || fcp_directory ? 34 : 15);
                            end
                            8'hb0,8'hb2:begin
                                data_kind<=1;state<=OUT_ACK;length<=requested_length;offset<=requested_offset;
                                if(ins==8'hb2)current_record<=requested_record;
                                if(ef_size(selected)==0 || (ins==8'hb2 && (ef_record(selected)==0 || requested_record==0)))begin state<=SW1;status1<=8'h94;status2<=8'h08;end
                                else if({1'b0,requested_offset}+{8'b0,requested_length}>{5'b0,ef_size(selected)})begin state<=SW1;status1<=8'h94;status2<=2;end
                                else if(protected_file && pin1_enabled && !pin_verified[0])begin state<=SW1;status1<=8'h98;status2<=4;end
                            end
                            8'hd6,8'hdc:begin
                                state<=header[4]==0 ? SW1 : UPDATE_PREP;length<={1'b0,header[4]};
                                offset<=requested_offset;
                                if(ins==8'hdc)current_record<=requested_record;
                                if(ef_size(selected)==0 || (ins==8'hdc && (ef_record(selected)==0 || requested_record==0)))begin state<=SW1;status1<=8'h94;status2<=8'h08;end
                                else if({1'b0,requested_offset}+{8'b0,requested_length}>{5'b0,ef_size(selected)})begin state<=SW1;status1<=8'h94;status2<=2;end
                                else if(protected_file && pin1_enabled && !pin_verified[0])begin state<=SW1;status1<=8'h98;status2<=4;end
                            end
                            8'h88:begin status1<=8'h98;status2<=4;end // no GSM secret
                            8'h20,8'h24,8'h26,8'h28,8'h2c:begin chv_start<=1;state<=CHV_WAIT;end
                            8'h10,8'h14,8'hc2,8'ha2,8'h32,8'h04,8'h44,8'hfa: ;
                            default:begin status1<=8'h6d;status2<=0;end
                        endcase
                    end
                end
            end
            ACK:begin state<=IDLE;end
            CHV_WAIT:if(chv_done)begin status1<=chv_status[15:8];status2<=chv_status[7:0];state<=SW1;end
            OUT_ACK:state<=DATA_PREP;
            DATA_PREP:state<=DATA;
            DATA:begin index<=index+1'b1;state<=index+1'b1==length ? SW1 : DATA_PREP;end
            UPDATE_PREP:state<=UPDATE;
            UPDATE:begin
                if(offset+index<ef_size(selected)) files[ef_base(selected)+12'(offset+index)]<=payload_q;
                index<=index+1'b1;state<=index+1'b1==length ? SW1 : UPDATE_PREP;
            end
            SW1:begin state<=SW2;end
            SW2:begin state<=IDLE;end
            default:state<=IDLE;
        endcase
        // Card power/reset has priority over an in-flight APDU state. Discard
        // stale procedure/data bytes before sending a new ATR on reactivation.
        if(valid && write && address==8'h39 && (!wdata[7] || !control[7]))begin
            count<=0;dirty<=0;acked<=0;wr_ptr<=0;read_ptr<=0;visible_ptr<=0;interrupts<=0;
            pace<=CLK_HZ/960;index<=0;state<=wdata[7] ? ATR : IDLE;
            selected<=16'h3f00;selected_df<=16'h3f00;current_record<=0;
        end
        if(reset) begin
            state<=IDLE;count<=0;dirty<=0;acked<=0;control<=0;clock_control<=0;
            low_water<=0;rx_flush<=0;tx_flush<=0;interrupts<=0;
            wr_ptr<=0;read_ptr<=0;visible_ptr<=0;pace<=0;selected<=16'h3f00;
            selected_df<=16'h3f00;fcp_fid<=16'h3f00;fcp_directory<=1;
            index<=0;length<=0;status1<=0;status2<=0;ins<=0;offset<=0;data_kind<=0;
            commands<=0;last_ins<=0;fid_hi<=0;fid_lo<=0;
            current_record<=0;chv_start<=0;
        end
    end
endmodule
