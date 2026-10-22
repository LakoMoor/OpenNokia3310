`timescale 1ns/1ps
module sim_tb;
    reg clk=0,reset=1,valid=0,write=0;
    reg [7:0] address=0,wdata=0;
    wire [7:0] rdata,last_ins;
    wire fiq;
    wire [31:0] commands;
    sim_card #(.CLK_HZ(96000)) dut(.*);
    always #5 clk=~clk;
    task put(input [7:0] a,input [7:0] d);
        @(negedge clk);valid=1;write=1;address=a;wdata=d;
        @(negedge clk);valid=0;write=0;
    endtask
    task get(input [7:0] expected);
        address=8'h3c;#1;wait(rdata!=0);
        @(negedge clk);address=8'h37;#1;
        if(rdata!==expected) $fatal(1,"SIM received %h expected %h",rdata,expected);
        valid=1;@(negedge clk);valid=0;
    endtask
    task header(input [7:0] ins,input [7:0] p1,input [7:0] p2,input [7:0] p3);
        put('h3e,4);put('h36,'ha0);put('h36,ins);put('h36,p1);put('h36,p2);put('h36,p3);put('h3e,0);
    endtask
    initial begin
        repeat(4) @(negedge clk);reset=0;
        put('h39,'hb2);address='h39;#1;if(rdata!=='hf2) $fatal(1,"SIM activation status");
        get('h3b);get('h60);get(0);get(0);
        header('ha4,0,0,2);get('ha4); // procedure ACK occurs once
        put('h3e,4);put('h36,'h3f);put('h36,0);put('h3e,0);
        get('h9f);get(34);
        header('hc0,0,0,34);get('hc0);
        for(integer i=0;i<34;i=i+1) begin
            case(i)
                4:get('h3f);6:get(1);12:get('h15);13:get('h81);15:get('h16);
                16:get(3);18,20:get('h83);19,21:get('h8a);default:get(0);
            endcase
        end
        get('h90);get(0);
        header('ha4,0,0,2);get('ha4);
        put('h3e,4);put('h36,'h6f);put('h36,7);put('h3e,0);get('h9f);get(15);
        header('hb0,0,0,9);get('hb0);
        get(8);get(9);get('h10);get('h10);get('h32);get('h54);get('h76);get('h98);get('h10);get('h90);get(0);
        // UPDATE BINARY must be reflected in subsequent READ.
        header('hd6,0,8,1);get('hd6);
        put('h3e,4);put('h36,'h55);put('h3e,0);get('h90);get(0);
        header('hb0,0,8,1);get('hb0);get('h55);get('h90);get(0);
        header('ha4,0,0,2);get('ha4);
        put('h3e,4);put('h36,'h6f);put('h36,'h3c);put('h3e,0);get('h9f);get(15);
        header('hb2,2,4,176);get('hb2);
        repeat(176) get('hff);get('h90);get(0);
        header('hdc,2,4,176);get('hdc);
        for(integer start=0;start<176;start=start+15) begin
            put('h3e,4);
            for(integer j=start;j<start+15 && j<176;j=j+1) put('h36,8'(j)^8'ha5);
            put('h3e,0);
        end
        get('h90);get(0); // no extra procedure ACK between payload chunks
        header('hb2,2,4,176);get('hb2);
        for(integer j=0;j<176;j=j+1) get(8'(j)^8'ha5);
        get('h90);get(0);
        if(commands!=10) $fatal(1,"APDU completion count %0d",commands);
        $display("PASS SIM: ATR, T=0 ACK, FCP, IMSI, binary update, 176-byte record chunks/readback, FIFO wrap");$finish;
    end
    initial begin #1000000;$fatal(1,"SIM timeout");end
endmodule
