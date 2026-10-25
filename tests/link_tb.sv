`timescale 1ns/1ps
module link_tb;
    reg clk=0,reset=1,stream_enabled=0,lcd_wr=0,lcd_dc=0;
    reg [7:0] lcd_data=0,flags=8'h13;
    reg [31:0] address=32'h00200040;
    reg [15:0] lcd_count=16'h1234;
    reg [72:0] audio_control={16'd4000,16'd3080,16'd1,16'd1234,8'd2,1'b1};
    reg [3:0] volume=5;
    reg menu_open=0,gray=0;
    reg [2:0] menu_row=0;
    wire tx;
    integer frame_type,frame_length,checksum=0,screen_frames=0,audio_frames=0,status_frames=0;
    reg [7:0] got;
    reg [7:0] bitmap[0:2047];
    reg [7:0] expected;
    integer raw_fd,bank_index,column_index;
    initial begin
        $readmemh("rtl/nokia/menu_bitmap.hex",bitmap);
        raw_fd=$fopen("build/tests/link-stream.bin","wb");
    end
    always #5 clk=~clk;
    nokia_link #(.CLK_HZ(115200),.BAUD(11520)) dut(.*);
    task send(input bit dc,input [7:0] d);
        @(negedge clk);lcd_wr=1;lcd_dc=dc;lcd_data=d;@(negedge clk);lcd_wr=0;
    endtask
    task rxbyte;
        @(negedge tx);repeat(15)@(negedge clk);
        for(integer b=0;b<8;b=b+1)begin got[b]=tx;repeat(10)@(negedge clk);end
        if(tx!==1)$fatal(1,"UART stop");
        $fwrite(raw_fd,"%c",got);
        checksum=checksum^int'(got);
    endtask
    initial begin
        wait(!reset);
        forever begin
            checksum=0;rxbyte();if(got!==8'h4e)$fatal(1,"magic N");
            rxbyte();if(got!==8'h34)$fatal(1,"magic 4");
            rxbyte();frame_type=int'(got);rxbyte();frame_length=int'(got)*256;rxbyte();frame_length=frame_length+int'(got);
            if(frame_length>504)$fatal(1,"invalid length");
            for(integer j=0;j<frame_length;j=j+1)begin
                rxbyte();
                if(frame_type==1)begin
                    expected=8'(j)^8'ha5;
                    if(screen_frames>0)begin
                        bank_index=j/84;column_index=j%84;
                        expected=bitmap[512+j];
                        if(bank_index==2 && column_index>=56 && column_index<72)
                            expected=bitmap[1024+(column_index<64 ? 8 : 0)+(column_index%8)];
                        if(bank_index==3)expected=~expected;
                    end
                    if(got!==expected)$fatal(1,"snapshot %0d byte %0d=%h expected %h",screen_frames,j,got,expected);
                end
                if(frame_type==2 && j==0 && got!==flags)$fatal(1,"status flags");
                if(frame_type==2 && j==7 && got!==(status_frames==0 ? 8'd5 : 8'd10))$fatal(1,"status volume");
                if(frame_type==2 && j==8 && got!==(status_frames==0 ? 8'd0 : 8'd3))$fatal(1,"status palette/menu flags");
                if(frame_type==3 && j==1 && got!==8'ha0)$fatal(1,"audio frequency");
            end
            rxbyte();if(checksum!=0)$fatal(1,"N4 checksum");
            if(frame_type==1)screen_frames++;if(frame_type==2)status_frames++;if(frame_type==3)audio_frames++;
            if(screen_frames==1)begin menu_open=1;menu_row=2;volume=10;gray=1;end
            if(screen_frames>1 && status_frames>0 && audio_frames>0)begin
                $fclose(raw_fd);
                $display("PASS link: UART framing, 504 LCD bytes, ROM menu/digits/highlight, status and audio");$finish;
            end
        end
    end
    initial begin
        repeat(5)@(negedge clk);reset=0;repeat(510)@(negedge clk);
        send(0,'h20);send(0,'h0c);
        for(integer j=0;j<504;j=j+1)send(1,8'(j)^8'ha5);
        stream_enabled=1;
    end
    initial begin #2000000;$fatal(1,"link timeout");end
endmodule
