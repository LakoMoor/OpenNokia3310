`timescale 1ns/1ps
module multiplier_tb;
    reg is_signed,is_long,accumulate;
    reg [31:0] op_a,op_b,acc_lo,acc_hi;
    wire [31:0] result_lo,result_hi;
    wire n_out,z_out;
    wire [3:0] flag_we;
    wire [2:0] cycle_count;
    arm7tdmis_multiplier dut(.*);
    reg [31:0] edges[0:7];
    reg [31:0] rng=32'h33102026;
    function automatic [31:0] random_word;
        rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);return rng;
    endfunction
    task check;
        reg [63:0] a,b,expected,acc;
        reg [2:0] cycles;
        a=is_signed ? {{32{op_a[31]}},op_a} : {32'd0,op_a};
        b=is_signed ? {{32{op_b[31]}},op_b} : {32'd0,op_b};
        acc=accumulate ? (is_long ? {acc_hi,acc_lo} : {32'd0,acc_lo}) : 0;
        expected=a*b+acc;
        cycles=(op_b[31:8]==0 || op_b[31:8]=='hffffff) ? 1 :
            (op_b[31:16]==0 || op_b[31:16]=='hffff) ? 2 :
            (op_b[31:24]==0 || op_b[31:24]=='hff) ? 3 : 4;
        #1;
        if(result_lo!==expected[31:0] || result_hi!==(is_long ? expected[63:32] : 32'd0) ||
           n_out!==(is_long ? expected[63] : expected[31]) ||
           z_out!==(is_long ? expected==0 : expected[31:0]==0) || flag_we!==4'b1100 || cycle_count!==cycles)
            $fatal(1,"multiply mismatch a=%h b=%h signed=%b long=%b accumulate=%b",op_a,op_b,is_signed,is_long,accumulate);
    endtask
    initial begin
        edges[0]=0;edges[1]=1;edges[2]='hffffffff;edges[3]='h80000000;
        edges[4]='h7fffffff;edges[5]='hffffff80;edges[6]='h00008000;edges[7]='h01000000;
        for(integer mode=0;mode<8;mode++)begin
            {is_signed,is_long,accumulate}=3'(mode);
            for(integer a=0;a<8;a++)for(integer b=0;b<8;b++)begin
                op_a=edges[a];op_b=edges[b];acc_hi=edges[(a+1)%8];acc_lo=edges[(b+2)%8];check();
            end
        end
        for(integer i=0;i<20000;i++)begin
            {is_signed,is_long,accumulate}=3'(random_word());
            op_a=random_word();op_b=random_word();acc_hi=random_word();acc_lo=random_word();check();
        end
        $display("PASS multiplier: 512 boundary and 20000 deterministic random signed/unsigned/accumulate/flags/cycles");$finish;
    end
endmodule
