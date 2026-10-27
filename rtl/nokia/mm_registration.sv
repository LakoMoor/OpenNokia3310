// SPDX-License-Identifier: GPL-3.0-or-later
// Minimal virtual MM location-update peer for an already established SAPI-0
// link. Caller must send UA before accepting the first pending I-frame.
// Also starts the virtual CM connection with an unencrypted cipher command.
// No authentication, CC call state machine or SMS service yet.
module mm_registration #(parameter RETRY_CYCLES=27000000,MAX_RETRIES=3) (
    input logic clk,reset,uplink_valid,
    input logic [183:0] uplink_frame,
    input logic [4:0] uplink_length,
    input logic [23:0] plmn,
    input logic [15:0] lac,
    input logic downlink_ready,
    output logic downlink_valid,
    output logic [183:0] downlink_frame,
    output logic registered,failed,cm_active
);
    typedef enum logic [3:0] {IDLE,ACCEPT_OUT,ACCEPT_ACK,RELEASE_OUT,RELEASE_ACK,COMPLETE,FAILED,
        CIPHER_OUT,CIPHER_ACK,CIPHER_COMPLETE,CM_ACTIVE} state_t;
    state_t state;
    localparam TIMER_BITS=RETRY_CYCLES<2 ? 1 : $clog2(RETRY_CYCLES);
    localparam RETRY_BITS=MAX_RETRIES<1 ? 1 : $clog2(MAX_RETRIES+1);
    logic [TIMER_BITS-1:0] timer;
    logic [RETRY_BITS-1:0] retries;
    logic [23:0] plmn_q;
    logic [15:0] lac_q;
    wire [7:0] addr=uplink_frame[183:176],ctrl=uplink_frame[175:168],li=uplink_frame[167:160];
    wire sapi0=addr[7:2]==0 && addr[0];
    wire valid_length=uplink_length>=3 && uplink_length<=23;
    wire rr=uplink_valid && valid_length && sapi0 && ctrl[3:0]==1 && li==1;
    // I-frames carry N(R) too. Accept their acknowledgement independently of
    // the still-unimplemented uplink L3/reassembly path, but validate framing.
    wire iframe_ack=uplink_valid && valid_length && sapi0 && !ctrl[0] && li[0] &&
        li[7:2]<=20 && {1'b0,uplink_length}>={1'b0,li[7:2]}+7'd3;
    wire acknowledgement=rr || iframe_ack;
    wire [7:0] identity_length=uplink_frame[87:80];
    wire [7:0] identity_first=uplink_frame[79:72];
    logic valid_identity;
    always_comb begin
        valid_identity=0;
        if(identity_first[2:0]==1 && identity_length==8 && identity_first[3] && identity_first[7:4]<=9)begin
            valid_identity=1;
            for(integer i=0;i<7;i++)
                if(uplink_frame[71-i*8-:4]>9 || uplink_frame[67-i*8-:4]>9)valid_identity=0;
        end
        if(identity_first==8'hf4 && identity_length==5)valid_identity=1;
    end
    wire lu_sabm=uplink_valid && valid_length && sapi0 && (ctrl & 8'hef)==8'h2f &&
        li[1:0]==1 && li[7:2]>=15 && li[7:2]<=20 &&
        {1'b0,uplink_length}>={1'b0,li[7:2]}+7'd3 &&
        uplink_frame[159:152]==5 && uplink_frame[151:144]==8 &&
        uplink_frame[137:136]!=3 && {2'd0,li[7:2]}==identity_length+8'd10 && valid_identity;
    // ROM v6.39: CM service request, three-byte Classmark 2 and a complete
    // 15-digit IMSI. Do not accept truncated or segmented establishment data.
    logic cm_identity_valid;
    always_comb begin
        // First IMSI digit may differ from the reference virtual SIM.
        cm_identity_valid=uplink_frame[91:88]==9 && uplink_frame[95:92]<=9;
        for(integer i=0;i<7;i++)
            if(uplink_frame[87-i*8-:4]>9 || uplink_frame[83-i*8-:4]>9)cm_identity_valid=0;
    end
    wire cm_sabm=uplink_valid && valid_length && sapi0 && (ctrl & 8'hef)==8'h2f &&
        li==8'h41 && uplink_length>=19 && uplink_frame[159:144]==16'h0524 &&
        (uplink_frame[139:136]==1 || uplink_frame[139:136]==2 || uplink_frame[139:136]==4) &&
        uplink_frame[135:128]==3 && uplink_frame[103:96]==8 && cm_identity_valid;
    wire cipher_complete=iframe_ack && ctrl[7:5]==1 && ctrl[3:1]==0 &&
        li==9 && uplink_frame[159:144]==16'h0632;
    always_comb begin
        registered=state==COMPLETE;
        cm_active=state==CM_ACTIVE;
        failed=state==FAILED;
        downlink_valid=state==ACCEPT_OUT || state==RELEASE_OUT || state==CIPHER_OUT;
        downlink_frame={23{8'h2b}};
        if(state==ACCEPT_OUT)begin
            downlink_frame[183:160]=24'h03001d; // N(S)=0, N(R)=0, seven L3 bytes
            downlink_frame[159:144]=16'h0502;
            downlink_frame[143:120]=plmn_q;
            downlink_frame[119:104]=lac_q;
        end else if(state==CIPHER_OUT)begin
            downlink_frame[183:136]=48'h03000d063501; // A5/0; request mode complete
        end else if(state==RELEASE_OUT)begin
            downlink_frame[183:136]=48'h03020d060d00; // N(S)=1, CHANNEL RELEASE
        end
    end
    always_ff @(posedge clk)begin
        if(state==ACCEPT_ACK || state==RELEASE_ACK || state==CIPHER_ACK)begin
            if(timer==RETRY_CYCLES-1)begin
                timer<=0;
                if(retries==MAX_RETRIES)state<=FAILED;
                else begin retries<=retries+1'b1;state<=state==ACCEPT_ACK ? ACCEPT_OUT : state==CIPHER_ACK ? CIPHER_OUT : RELEASE_OUT;end
            end else timer<=timer+1'b1;
        end
        case(state)
            IDLE:if(lu_sabm)begin plmn_q<=plmn;lac_q<=lac;state<=ACCEPT_OUT;retries<=0;timer<=0;end
                else if(cm_sabm)begin state<=CIPHER_OUT;retries<=0;timer<=0;end
            CIPHER_OUT:if(retries!=0 && acknowledgement && ctrl[7:5]==1)begin state<=cipher_complete ? CM_ACTIVE : CIPHER_COMPLETE;timer<=0;end
                else if(downlink_ready)begin state<=CIPHER_ACK;timer<=0;end
            CIPHER_ACK:if(acknowledgement && ctrl[7:5]==1)begin state<=cipher_complete ? CM_ACTIVE : CIPHER_COMPLETE;timer<=0;end
            CIPHER_COMPLETE:if(cipher_complete)state<=CM_ACTIVE;
            ACCEPT_OUT:if(retries!=0 && acknowledgement && ctrl[7:5]==1)begin state<=RELEASE_OUT;retries<=0;timer<=0;end
                else if(downlink_ready)begin state<=ACCEPT_ACK;timer<=0;end
            ACCEPT_ACK:if(acknowledgement && ctrl[7:5]==1)begin state<=RELEASE_OUT;retries<=0;timer<=0;end
            RELEASE_OUT:if(retries!=0 && acknowledgement && ctrl[7:5]==2)begin state<=COMPLETE;timer<=0;end
                else if(downlink_ready)begin state<=RELEASE_ACK;timer<=0;end
            RELEASE_ACK:if(acknowledgement && ctrl[7:5]==2)begin state<=COMPLETE;timer<=0;end
            default:;
        endcase
        if(reset)begin state<=IDLE;plmn_q<=0;lac_q<=0;timer<=0;retries<=0;end
    end
endmodule
