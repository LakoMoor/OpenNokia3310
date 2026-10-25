// SPDX-License-Identifier: GPL-3.0-or-later
module nokia_controls #(parameter CLK_HZ=16_875_000) (
    input logic clk,reset,menu_button,
    input logic [16:0] keys,
    input logic control_wr,
    input logic [7:0] control_opcode,control_data,
    output logic menu_open,stream_enabled,gray,reset_request,test_start,
    output logic [2:0] menu_row,
    output logic [3:0] volume
);
    logic [16:0] previous;
    logic menu_previous;
    logic [25:0] repeat_count;
    wire up=keys[14] && (!previous[14] || repeat_count==CLK_HZ/3);
    wire down=keys[15] && (!previous[15] || repeat_count==CLK_HZ/3);
    wire left_key=keys[4] && !previous[4],right_key=keys[6] && !previous[6];
    wire select_key=keys[12] && !previous[12];
    always_ff @(posedge clk) begin
        previous<=keys;menu_previous<=menu_button;reset_request<=0;test_start<=0;
        if(keys[14] || keys[15]) repeat_count<=repeat_count==CLK_HZ/3 ? 0 : repeat_count+1'b1;
        else repeat_count<=0;
        if(menu_button && !menu_previous) menu_open<=~menu_open;
        if(control_wr) case(control_opcode)
            5:begin stream_enabled<=control_data[0];if(control_data[1])menu_open<=~menu_open;if(control_data[2])reset_request<=1;end
            6:volume<=control_data>10 ? 4'd10 : control_data[3:0];
            7:gray<=control_data[0];
            8:if(control_data==1)test_start<=1;
            default: ;
        endcase
        if(menu_open) begin
            if(up) menu_row<=menu_row==0 ? 3'd4 : menu_row-1'b1;
            if(down) menu_row<=menu_row==4 ? 3'd0 : menu_row+1'b1;
            if(keys[13] && !previous[13])menu_open<=0;
            case(menu_row)
                0:if(select_key)menu_open<=0;
                1:begin
                    if(left_key && volume!=0)volume<=volume-1'b1;
                    if(right_key && volume<10)volume<=volume+1'b1;
                    if(select_key)volume<=volume==0 ? 4'd5 : 4'd0;
                end
                2:if(select_key || left_key || right_key)gray<=~gray;
                3:if(select_key)test_start<=1;
                4:if(select_key)reset_request<=1;
                default: ;
            endcase
        end
        if(reset) begin previous<=0;menu_previous<=0;repeat_count<=0;menu_open<=0;stream_enabled<=0;gray<=0;
            reset_request<=0;test_start<=0;menu_row<=0;volume<=5;end
    end
endmodule
