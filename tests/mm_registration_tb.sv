`timescale 1ns/1ps
module mm_registration_tb;
    reg clk=0,reset=1,uplink_valid=0,downlink_ready=0;
    reg [183:0] uplink_frame={24'h033f49,144'h05087000f110ffff33080910103254769810,16'h2b2b};
    reg [4:0] uplink_length=23;
    reg [23:0] plmn=24'h00f110;
    reg [15:0] lac=1;
    wire downlink_valid,registered,failed;
    wire [183:0] downlink_frame;
    mm_registration dut(.*);
    always #5 clk=~clk;
    task uplink(input [23:0] header);
        @(negedge clk);uplink_frame[183:160]=header;uplink_valid=1;
        @(negedge clk);uplink_valid=0;
    endtask
    task sent;
        @(negedge clk);downlink_ready=1;@(negedge clk);downlink_ready=0;
    endtask
    initial begin
        repeat(4)@(negedge clk);reset=0;
        uplink(24'h033f09);if(downlink_valid)$fatal(1,"two-byte LU header is not a complete request");
        uplink_frame[71:68]=4'ha;
        uplink(24'h033f49);if(downlink_valid)$fatal(1,"invalid IMSI digit accepted");
        uplink_frame[71:68]=1;
        uplink_frame[87:80]=7;
        uplink(24'h033f49);if(downlink_valid)$fatal(1,"identity length mismatch accepted");
        uplink_frame[87:80]=8;
        uplink_frame[159:144]=16'h0508;
        uplink_frame[159:144]=16'h0608;
        uplink(24'h033f49);if(downlink_valid)$fatal(1,"wrong protocol discriminator accepted");
        uplink_frame[159:144]=16'h0508;
        uplink(24'h033f4b);if(downlink_valid)$fatal(1,"segmented establishment accepted");
        uplink(24'h0f3f49);if(downlink_valid)$fatal(1,"wrong SAPI accepted");
        uplink_length=4;uplink(24'h033f49);if(downlink_valid)$fatal(1,"truncated LU accepted");
        uplink_length=23;uplink(24'h033f49);
        if(!downlink_valid || registered || downlink_frame[183:104]!==80'h03001d050200f1100001)
            $fatal(1,"LU accept identity/frame");
        plmn=0;lac=0;
        repeat(5)@(negedge clk);
        if(downlink_frame[143:104]!==40'h00f1100001)$fatal(1,"pending identity changed");
        uplink(24'h032101); // acknowledgement before output acceptance cannot advance
        if(downlink_frame[175:168]!=0)$fatal(1,"unsent frame acknowledged");
        sent();
        uplink(24'h030101);if(downlink_valid || registered)$fatal(1,"wrong N(R) accepted");
        uplink(24'h0f2101);if(downlink_valid)$fatal(1,"wrong SAPI acknowledgement");
        uplink(24'h032101);
        if(!downlink_valid || downlink_frame[183:136]!==48'h03020d060d00 || registered)
            $fatal(1,"release before correct LU acknowledgement");
        sent();uplink(24'h032101);if(registered)$fatal(1,"duplicate acknowledgement advanced");
        uplink(24'h034101);if(!registered || downlink_valid)$fatal(1,"release acknowledgement");
        @(negedge clk);reset=1;@(negedge clk);if(registered || downlink_valid)$fatal(1,"MM reset");
        reset=0;uplink_frame[87:80]=5;uplink_frame[79:72]=8'hf4;
        uplink(24'h033f3d);if(!downlink_valid)$fatal(1,"valid TMSI request rejected");
        @(negedge clk);reset=1;@(negedge clk);reset=0;
        uplink_frame={24'h033f41,128'h05247103301881081910103254769810,32'h2b2b2b2b};
        uplink_length=18;uplink(24'h033f41);
        if(downlink_valid)$fatal(1,"truncated CM service accepted");
        uplink_length=23;uplink_frame[95:92]=4'ha;uplink(24'h033f41);
        if(downlink_valid)$fatal(1,"invalid CM IMSI accepted");
        uplink_frame[95:92]=1;uplink(24'h033f43);
        if(downlink_valid)$fatal(1,"segmented CM establishment accepted");
        uplink(24'h033f41);
        if(!downlink_valid || downlink_frame[183:136]!==48'h03000d063501)
            $fatal(1,"CM service did not produce unencrypted cipher command");
        repeat(4)@(negedge clk);
        if(!downlink_valid)$fatal(1,"cipher command lost under backpressure");
        sent();uplink(24'h030101);
        if(dut.state!=dut.CIPHER_ACK)$fatal(1,"wrong cipher N(R) accepted");
        uplink(24'h032101);
        if(downlink_valid || registered || dut.state!=dut.CIPHER_COMPLETE)
            $fatal(1,"cipher acknowledgement confused with registration/release");
        uplink_frame[159:144]=16'h0632;uplink(24'h032209);
        if(dut.state!=dut.CIPHER_COMPLETE)$fatal(1,"out of sequence mode complete accepted");
        uplink(24'h032009);
        if(dut.state!=dut.CM_ACTIVE || registered || downlink_valid)
            $fatal(1,"cipher mode complete did not activate virtual CM connection");
        $display("PASS MM peer: LU/LAI/release and CM cipher establishment, framing/identity/sequence/reset");$finish;
    end
    initial begin #10000;$fatal(1,"MM timeout");end
endmodule
