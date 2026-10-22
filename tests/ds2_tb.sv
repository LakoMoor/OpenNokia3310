`timescale 1ns/1ps
module ds2_tb;
    reg clk=0,reset=1,miso=1;
    wire sck,cs_n,mosi;
    wire [7:0] buttons0,buttons1;
    wire [7:0] controller_id;
    wire connected;
    wire [16:0] keys;
    reg [7:0] row_signal=8'hef,row_direction=8'h1f;
    wire [7:0] columns;
    pad_3310 pad(.*);
    keypad_3310 matrix(.*);
    integer bit_number=0,byte_number=0,polls=0;
    reg bad=0;
    reg [7:0] reply,command=0;
    time byte_end;
    always #5 clk=~clk;
    ds2_pad #(.CLK_HZ(1_000_000)) dut(.*);
    always @(negedge cs_n) begin bit_number=0;byte_number=0;command=0;end
    always @(negedge sck) if(!cs_n) begin
        if(byte_number>0 && bit_number==0 && $time-byte_end<1920)
            $fatal(1,"controller requires inter-byte ACK/recovery gap");
        case(byte_number)
            1: reply=bad ? 8'hff : 8'h41;
            2: reply=8'h5a;
            3: reply=8'hef;
            4: reply=8'hdf;
            default:reply=8'hff;
        endcase
        miso=reply[bit_number];
    end
    always @(posedge sck) if(!cs_n) begin
        command[bit_number]=mosi;
        if(bit_number==7) begin
            byte_end=$time;
            if((byte_number==0 && command!==8'h01) || (byte_number==1 && command!==8'h42) ||
               (byte_number>1 && command!==8'h00)) $fatal(1,"bad DS2 command byte %0d = %h",byte_number,command);
            bit_number=0;byte_number=byte_number+1;
        end else bit_number=bit_number+1;
    end
    always @(posedge cs_n) if(!reset) polls=polls+1;
    initial begin
        repeat(5) @(negedge clk);reset=0;
        wait(polls==1);repeat(2) @(negedge clk);
        if(buttons0!==8'hef || buttons1!==8'hdf) $fatal(1,"button sample");
        if(!connected || controller_id!==8'h41) $fatal(1,"controller identification");
        if(keys!==17'h05000 || columns!==8'h17) $fatal(1,"DS2 Circle to Nokia Menu row 4");
        row_signal=8'hfe; #1;
        if(columns!==8'h1d) $fatal(1,"DS2 Up to Nokia Up row 0");
        bad=1;wait(polls==2);repeat(2) @(negedge clk);
        if(buttons0!==8'hff || buttons1!==8'hff) $fatal(1,"invalid controller must release buttons");
        if(connected || controller_id!==8'hff) $fatal(1,"disconnect status");
        if(keys!==0 || columns!==8'h1f) $fatal(1,"disconnect must release Nokia matrix");
        $display("PASS DS2: LSB-first 01/42 poll, synchronized response, invalid ID release");$finish;
    end
    initial begin #500000;$fatal(1,"timeout");end
endmodule
