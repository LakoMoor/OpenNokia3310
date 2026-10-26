`timescale 1ns/1ps
module sim_chv_tb;
    reg clk=0,reset=1,start=0;
    reg [7:0] instruction=0,p1=0,p2=1,length=8;
    reg [63:0] presented=0,replacement=64'h34333231ffffffff;
    wire done,pin1_enabled;
    wire [15:0] status_word;
    wire [1:0] verified;
    wire [7:0] pin1_status,pin2_status,puk1_status,puk2_status;
    sim_chv dut(.*);
    always #5 clk=~clk;
    task issue(input [7:0] op,input [63:0] code,input [15:0] expected);
        @(negedge clk);instruction=op;presented=code;length=(op=='h24 || op=='h2c) ? 16 : 8;start=1;
        @(negedge clk);start=0;
        if(!done || status_word!==expected)$fatal(1,"CHV op=%h status=%h expected=%h",op,status_word,expected);
    endtask
    initial begin
        repeat(4)@(negedge clk);reset=0;
        issue('h20,64'h31323334ffffffff,'h9808); // disabled
        issue('h28,64'h31323334ffffffff,'h9000);
        if(!pin1_enabled || !verified[0])$fatal(1,"enable PIN1");
        issue('h28,64'h31323334ffffffff,'h9808);
        issue('h20,0,'h9804);issue('h20,0,'h9804);
        @(negedge clk);reset=1;@(negedge clk);reset=0;
        if(!pin1_enabled || pin1_status!='h81 || verified!=0)$fatal(1,"card reset must preserve retries and enabled state");
        issue('h20,0,'h9840);issue('h20,64'h31323334ffffffff,'h9840);
        issue('h2c,0,'h9804);
        if(puk1_status!='h89)$fatal(1,"PUK retries");
        issue('h2c,64'h3132333435363738,'h9000);
        if(pin1_status!='h83 || puk1_status!='h8a)$fatal(1,"unblock counters");
        issue('h20,64'h34333231ffffffff,'h9000);
        replacement=64'h39383736ffffffff;
        issue('h24,64'h34333231ffffffff,'h9000);
        issue('h26,64'h39383736ffffffff,'h9000);
        if(pin1_enabled)$fatal(1,"disable PIN1");
        p2=2;issue('h20,64'h35363738ffffffff,'h9000);
        if(!verified[1] || pin2_status!='h83)$fatal(1,"independent PIN2");
        issue('h26,64'h35363738ffffffff,'h6b00);
        issue('h20,64'hf5363738ffffffff,'h9804); // invalid ASCII must not alias digit 5
        issue('h20,64'h35363738ffffffff,'h9000);
        replacement=64'h313233ffffffffff; // new PIN shorter than four digits
        issue('h24,64'h35363738ffffffff,'h6b00);
        issue('h20,64'h35363738ffffffff,'h9000);
        $display("PASS SIM CHV: enable/verify/change/disable, retry blocking across reset, PUK and PIN2");$finish;
    end
    initial begin #20000;$fatal(1,"timeout");end
endmodule
