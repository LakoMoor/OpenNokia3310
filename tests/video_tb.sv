`timescale 1ns/1ps
module video_tb;
    reg clk=0,reset=1,lcd_wr=0,lcd_dc=0;
    reg [7:0] lcd_data=0;
    reg menu_open=0,gray=0;
    reg [2:0] menu_row=0;
    reg [3:0] volume=5;
    reg [9:0] hdmi_x=0,hdmi_y=0;
    wire ready,lcd_scl,lcd_sda,lcd_cs,lcd_dc_out,lcd_rst,lcd_bl;
    wire [23:0] rgb;
    integer fd;
    reg on;
    reg [7:0] b;
    always #5 clk=~clk;
    nokia_video dut(.*);
    task send(input bit dc,input [7:0] d);
        @(negedge clk);lcd_wr=1;lcd_dc=dc;lcd_data=d;
        @(negedge clk);lcd_wr=0;
    endtask
    task hdmi_check(input integer x,y,input [23:0] expected);
        @(negedge clk);hdmi_x=x;hdmi_y=y;
        @(posedge clk);#1;if(rgb!==expected) $fatal(1,"HDMI %0d,%0d = %h expected %h",x,y,rgb,expected);
    endtask
    initial begin
        repeat(5) @(negedge clk);reset=0;wait(ready);
        send(0,8'h20);send(0,8'h0c);
        for(integer bank=0;bank<6;bank=bank+1)
            for(integer x=0;x<84;x=x+1) begin
                b=(x==0 || x==83) ? 8'hff : bank==0 ? 8'h01 : bank==5 ? 8'h80 : 8'h00;
                send(1,b);
            end
        hdmi_check(24,48,24'h26351c);
        hdmi_check(32,56,24'hc4cfa1);
        hdmi_check(695,431,24'h26351c);
        hdmi_check(23,48,24'h101810);
        hdmi_check(696,431,24'h101810);
        // Wait for a complete capture after the source frame finished writing.
        repeat(500000) @(negedge clk);
        fd=$fopen("build/tests/panel.pgm","w");
        $fwrite(fd,"P2\n128 128\n255\n");
        for(integer y=0;y<128;y=y+1)
            for(integer x=0;x<128;x=x+1) begin
                on=x>=22 && x<106 && y>=40 && y<88 && (x==22 || x==105 || y==40 || y==87);
                if(dut.u_panel.fb_hi[y*128+x] !== (on ? 9'd35 : 9'd409) ||
                   dut.u_panel.fb_lo[y*128+x] !== (on ? 4'd1 : 4'd10))
                    $fatal(1,"ST7735 captured frame %0d,%0d",x,y);
                $fwrite(fd,"%0d ",on ? 32 : 200);
            end
        $fclose(fd);
        gray=1;
        hdmi_check(24,48,24'h252525);hdmi_check(32,56,24'hdeded3);
        repeat(500000) @(negedge clk);
        for(integer y=0;y<128;y=y+1)
            for(integer x=0;x<128;x=x+1) begin
                on=x>=22 && x<106 && y>=40 && y<88 && (x==22 || x==105 || y==40 || y==87);
                if(dut.u_panel.fb_hi[y*128+x] !== (on ? 9'd34 : 9'd511) ||
                   dut.u_panel.fb_lo[y*128+x] !== (on ? 4'd1 : 4'd15))
                    $fatal(1,"ST7735 gray frame %0d,%0d",x,y);
            end
        $display("PASS video: HDMI bounds, 16384 ST7735 pixels, green/gray palette on both outputs");$finish;
    end
    initial begin #12000000;$fatal(1,"timeout");end
endmodule
