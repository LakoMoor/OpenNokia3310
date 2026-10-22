// SPDX-License-Identifier: GPL-3.0-or-later
// Intel/Sharp top-boot NOR in SDRAM: array/ID/status, program (AND), erase.
// Opcode fetches see the array while command/data transactions use the FSM.
module nor_bus (
    input logic clk,reset,valid,write,code,
    input logic [31:0] address,wdata,
    input logic [3:0] be,
    output logic ready,error,
    output logic [31:0] rdata,
    output logic m_valid,m_write,m_code,
    output logic [31:0] m_address,m_wdata,
    output logic [3:0] m_be,
    input logic m_ready,m_error,
    input logic [31:0] m_rdata
);
    typedef enum logic [2:0] {IDLE,REQUEST,PROGRAM_READ,PROGRAM_WRITE,ERASE,RESPONSE} state_t;
    state_t state;
    logic [1:0] mode,busy_polls;
    logic program_armed,erase_armed;
    logic [31:0] program_data;
    logic [13:0] erase_left;
    logic [31:0] value;
    logic [15:0] ident;
    wire flash=address>=32'h200000 && address<32'h400000;
    always_comb begin
        value=wdata;
        if(be==4'hc) value={16'b0,wdata[31:16]};
        else if(be==4'h3) value={16'b0,wdata[15:0]};
        else if(be!=4'hf) value=(wdata>>((3-address[1:0])*8)) & 32'hff;
        case(address[2:1])
            0:ident=16'h0089;
            1:ident=16'h8890;
            default:ident=16'hffff;
        endcase
        ready=state==RESPONSE;
        m_valid=state==REQUEST || state==PROGRAM_READ || state==PROGRAM_WRITE || state==ERASE;
    end
    always_ff @(posedge clk) begin
        case(state)
            IDLE: if(valid) begin
                error<=0;
                m_address<=address;m_wdata<=wdata;m_be<=be;m_write<=write;m_code<=code;
                if(flash && write) begin
                    state<=RESPONSE;
                    if(program_armed) begin
                        program_armed<=0;mode<=1;program_data<=wdata;
                        m_write<=0;m_code<=0;state<=PROGRAM_READ;
                    end else case(value[7:0])
                        8'hff,8'hf0:begin mode<=0;erase_armed<=0;end
                        8'h90:mode<=2;
                        8'h70:mode<=1;
                        8'h50:busy_polls<=0;
                        8'h40,8'h10:begin program_armed<=1;mode<=1;end
                        8'h20:begin erase_armed<=1;mode<=1;end
                        8'hd0:begin
                            mode<=1;erase_armed<=0;
                            if(erase_armed) begin
                                state<=ERASE;m_write<=1;m_code<=0;m_wdata<=32'hffffffff;m_be<=15;
                                if(address>=32'h3f0000) begin m_address<={address[31:13],13'b0};erase_left<=2047;end
                                else begin m_address<={address[31:16],16'b0};erase_left<=16383;end
                            end
                        end
                        default: ;
                    endcase
                end else if(flash && !code && mode==1) begin
                    rdata<=busy_polls==0 ? 32'h80808080 : 32'd0;
                    if(busy_polls!=0) busy_polls<=busy_polls-1'b1;
                    state<=RESPONSE;
                end else if(flash && !code && mode==2 && address[2:1]!=3) begin
                    if(be==15) rdata<={ident,ident};
                    else if(be==12) rdata<={ident,16'b0};
                    else if(be==3) rdata<={16'b0,ident};
                    else rdata<={24'b0,(address[0] ? ident[7:0] : ident[15:8])}<<((3-address[1:0])*8);
                    state<=RESPONSE;
                end else state<=REQUEST;
            end
            REQUEST: if(m_ready) begin rdata<=m_rdata;error<=m_error;state<=RESPONSE;end
            PROGRAM_READ: if(m_ready) begin
                if(m_error) begin error<=1;state<=RESPONSE;end
                else begin m_wdata<=m_rdata & program_data;m_write<=1;state<=PROGRAM_WRITE;end
            end
            PROGRAM_WRITE: if(m_ready) begin error<=m_error;busy_polls<=2;state<=RESPONSE;end
            ERASE: if(m_ready) begin
                if(m_error || erase_left==0) begin error<=m_error;busy_polls<=2;state<=RESPONSE;end
                else begin erase_left<=erase_left-1'b1;m_address<=m_address+4;end
            end
            RESPONSE:state<=IDLE;
            default:state<=IDLE;
        endcase
        if(reset) begin
            state<=IDLE;mode<=0;program_armed<=0;erase_armed<=0;busy_polls<=0;
            error<=0;rdata<=0;m_write<=0;m_code<=0;m_address<=0;m_wdata<=0;m_be<=0;
            program_data<=0;erase_left<=0;
        end
    end
endmodule
