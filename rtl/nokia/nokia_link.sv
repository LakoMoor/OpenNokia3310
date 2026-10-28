// SPDX-License-Identifier: GPL-3.0-or-later
// N4 framed UART: LCD snapshot (1), status (2), device audio controls (3).
module nokia_link #(parameter CLK_HZ=16_875_000,BAUD=115200) (
    input logic clk,reset,stream_enabled,
    input logic lcd_wr,lcd_dc,
    input logic [7:0] lcd_data,flags,
    input logic [31:0] address,
    input logic [15:0] lcd_count,
    input logic [72:0] audio_control,
    input logic [3:0] volume,
    input logic menu_open,gray,
    input logic [2:0] menu_row,
    output logic tx
);
    localparam DIV=(CLK_HZ+BAUD/2)/BAUD;
    logic [7:0] mirror[0:503],snapshot[0:503];
    logic [6:0] column;
    logic [2:0] bank;
    logic extended,vertical,mirror_ready;
    logic powerdown;
    logic [1:0] mode,capture_mode;
    logic [8:0] clear_addr,copy_addr;
    wire [8:0] mirror_addr=9'(int'(bank)*84+int'(column));
    logic [7:0] mirror_q,snapshot_q;
    logic [25:0] frame_timer,status_timer;
    logic frame_due,status_due;
    logic audio_credit;
    logic [72:0] audio_previous,audio_latch;
    logic [3:0] volume_previous,volume_latch;
    logic [79:0] status_latch;
    typedef enum logic [3:0] {IDLE,COPY_WAIT,COPY_BYTE,COPY_PIXEL,PIXEL_WAIT,LOAD,SEND,ACCEPT,WAIT_BYTE} state_t;
    state_t state;
    logic [2:0] pixel_bit;
    logic [6:0] copy_column;
    logic [2:0] copy_bank;
    logic [7:0] pixel_byte;
    logic overlay_pixel;
    logic copying_menu;
    logic [2:0] row_latch;
    logic gray_latch;
    wire [6:0] copy_x=copy_column;
    wire [5:0] copy_y={copy_bank,pixel_bit};
    nokia_overlay u_overlay(.clk(clk),.x(copy_x),.y(copy_y),.row(row_latch),.volume(volume_latch),.gray(gray_latch),.pixel(overlay_pixel));
    logic [2:0] kind;
    logic [9:0] length,tx_index;
    logic [7:0] checksum,byte_data;
    logic start_byte,byte_busy,byte_done;
    logic [15:0] baud_counter;
    logic [3:0] bit_index;
    logic [9:0] serial_word;
    always_ff @(posedge clk) begin
        byte_done<=0;
        if(!byte_busy) begin
            tx<=1;
            if(start_byte) begin serial_word<={1'b1,byte_data,1'b0};tx<=0;baud_counter<=DIV-1;bit_index<=0;byte_busy<=1;end
        end else if(baud_counter!=0)baud_counter<=baud_counter-1'b1;
        else if(bit_index==9)begin byte_busy<=0;byte_done<=1;tx<=1;end
        else begin serial_word<={1'b1,serial_word[9:1]};tx<=serial_word[1];bit_index<=bit_index+1'b1;baud_counter<=DIV-1;end
        if(reset)begin tx<=1;byte_busy<=0;byte_done<=0;baud_counter<=0;bit_index<=0;serial_word<=10'h3ff;end
    end
    wire [8:0] snap_read=tx_index>=5 && tx_index<509 ? 9'(tx_index-5) : 9'd0;
    always_ff @(posedge clk) begin
        mirror_q<=mirror[copy_addr];snapshot_q<=snapshot[snap_read];
        if(!mirror_ready)mirror[clear_addr]<=0;
        else if(lcd_wr && lcd_dc)mirror[mirror_addr]<=lcd_data;
        if(state==COPY_BYTE && !copying_menu)snapshot[copy_addr]<=capture_mode==0 ? 8'h00 : capture_mode==1 ? 8'hff : capture_mode==2 ? mirror_q : ~mirror_q;
        else if(state==COPY_PIXEL && pixel_bit==7)snapshot[copy_addr]<={overlay_pixel,pixel_byte[6:0]};
    end
    logic [7:0] payload_byte,next_byte;
    always_comb begin
        payload_byte=0;
        case(kind)
            1:payload_byte=snapshot_q;
            2:if(tx_index>=5 && tx_index<15)payload_byte=status_latch[79-(int'(tx_index)-5)*8-:8];
            3:case(tx_index)
                5:payload_byte=audio_latch[72:65];6:payload_byte=audio_latch[64:57];
                7:payload_byte=audio_latch[56:49];8:payload_byte=audio_latch[48:41];
                9:payload_byte=audio_latch[40:33];10:payload_byte=audio_latch[32:25];
                11:payload_byte=audio_latch[24:17];12:payload_byte=audio_latch[16:9];
                13:payload_byte={7'b0,audio_latch[0]};14:payload_byte=audio_latch[8:1];15:payload_byte={4'b0,volume_latch};
                default: ;
            endcase
            default: ;
        endcase
        case(tx_index)
            0:next_byte=8'h4e;1:next_byte=8'h34;2:next_byte={5'b0,kind};
            3:next_byte={6'b0,length[9:8]};4:next_byte=length[7:0];
            default:next_byte=tx_index==length+5 ? checksum : payload_byte;
        endcase
    end
    always_ff @(posedge clk) begin
        start_byte<=0;
        if(!mirror_ready)begin if(clear_addr==503)mirror_ready<=1;else clear_addr<=clear_addr+1'b1;end
        if(lcd_wr && mirror_ready) begin
            if(lcd_dc)begin
                if(vertical)begin if(bank==5)begin bank<=0;column<=column==83 ? 7'd0 : column+1'b1;end else bank<=bank+1'b1;end
                else if(column==83)begin column<=0;bank<=bank==5 ? 3'd0 : bank+1'b1;end else column<=column+1'b1;
            end else if((lcd_data&8'hf8)==8'h20)begin extended<=lcd_data[0];vertical<=lcd_data[1];powerdown<=lcd_data[2];end
            else if(!extended)begin
                if(lcd_data[7])column<=lcd_data[6:0]<84 ? lcd_data[6:0] : 7'd83;
                else if((lcd_data&8'hf8)==8'h40)bank<=lcd_data[2:0]<6 ? lcd_data[2:0] : 3'd5;
                else if((lcd_data&8'hf8)==8'h08)mode<={lcd_data[2],lcd_data[0]};
            end
        end
        frame_timer<=frame_timer+1'b1;status_timer<=status_timer+1'b1;
        if(frame_timer==CLK_HZ/4-1)begin frame_timer<=0;frame_due<=1;end
        if(status_timer==CLK_HZ/4-1)begin status_timer<=0;status_due<=1;end
        case(state)
            IDLE:begin
                tx_index<=0;checksum<=0;
                // Periodic status and screen frames must make progress even
                // when firmware updates sound registers continuously. Audio
                // changes are coalesced and sent when neither is due.
                if(status_due)begin
                    status_latch<={flags,address,lcd_count,4'b0,volume,6'b0,gray,menu_open,8'd1};
                    status_due<=0;kind<=2;length<=10;state<=LOAD;
                end
                else if(audio_credit && stream_enabled && (audio_control!=audio_previous || volume!=volume_previous))begin
                    audio_latch<=audio_control;volume_latch<=volume;audio_previous<=audio_control;volume_previous<=volume;
                    audio_credit<=0;kind<=3;length<=11;state<=LOAD;
                end
                else if(frame_due && stream_enabled && mirror_ready)begin
                    frame_due<=0;copy_addr<=0;pixel_bit<=0;copying_menu<=menu_open;row_latch<=menu_row;
                    copy_column<=0;copy_bank<=0;
                    gray_latch<=gray;volume_latch<=volume;audio_credit<=1;kind<=1;length<=504;state<=COPY_WAIT;
                    capture_mode<=powerdown ? 2'd0 : mode;
                end
                else if(stream_enabled && (audio_control!=audio_previous || volume!=volume_previous))begin
                    audio_latch<=audio_control;volume_latch<=volume;audio_previous<=audio_control;volume_previous<=volume;
                    audio_credit<=0;kind<=3;length<=11;state<=LOAD;
                end
            end
            COPY_WAIT:state<=copying_menu ? COPY_PIXEL : COPY_BYTE;
            COPY_BYTE:begin if(copy_addr==503)state<=LOAD;else begin copy_addr<=copy_addr+1'b1;state<=COPY_WAIT;end end
            COPY_PIXEL:begin
                pixel_byte[pixel_bit]<=overlay_pixel;
                if(pixel_bit==7)begin
                    pixel_bit<=0;
                    if(copy_column==83)begin copy_column<=0;copy_bank<=copy_bank+1'b1;end else copy_column<=copy_column+1'b1;
                    if(copy_addr==503)state<=LOAD;else begin copy_addr<=copy_addr+1'b1;state<=COPY_WAIT;end
                end
                else begin pixel_bit<=pixel_bit+1'b1;state<=PIXEL_WAIT;end
            end
            PIXEL_WAIT:state<=COPY_PIXEL;
            LOAD:state<=SEND;
            SEND:if(!byte_busy)begin byte_data<=next_byte;start_byte<=1;checksum<=checksum^next_byte;state<=ACCEPT;end
            ACCEPT:state<=WAIT_BYTE;
            WAIT_BYTE:if(byte_done)begin
                if(tx_index==length+5)state<=IDLE;
                else begin tx_index<=tx_index+1'b1;state<=LOAD;end
            end
            default:state<=IDLE;
        endcase
        if(reset)begin
            state<=IDLE;column<=0;bank<=0;extended<=0;vertical<=0;mirror_ready<=0;clear_addr<=0;copy_addr<=0;
            frame_timer<=0;status_timer<=0;frame_due<=0;status_due<=0;audio_credit<=0;audio_previous<=0;audio_latch<=0;
            volume_previous<=0;volume_latch<=0;status_latch<=0;kind<=0;length<=0;tx_index<=0;checksum<=0;
            byte_data<=0;start_byte<=0;pixel_bit<=0;pixel_byte<=0;copying_menu<=0;row_latch<=0;gray_latch<=0;
            powerdown<=1;mode<=0;capture_mode<=0;
            copy_column<=0;copy_bank<=0;
        end
    end
endmodule
