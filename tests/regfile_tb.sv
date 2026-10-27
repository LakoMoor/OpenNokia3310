`timescale 1ns/1ps
module regfile_tb;
    reg CLK=0,CLKEN=0,nRESET=0,t_bit=0,wa_enable=0,force_user_bank=0,dbg_we=0,dbg_force_user_bank=0;
    reg [4:0] mode='h10;
    reg [31:0] pc_in=0,wa_data=0,dbg_wdata=0,STATE_WDATA=0;
    reg [3:0] ra_addr=0,rb_addr=0,rc_addr=0,wa_addr=0,dbg_addr=0;
    reg STATE_WRITE=0;
    reg [4:0] STATE_INDEX=0;
    wire [31:0] ra_data,rb_data,rc_data,dbg_rdata,STATE_RDATA;
    wire [991:0] VER_GPRS;
    wire pc_written;
    reg [31:0] expected[0:30];
    reg [31:0] rng=32'h3310f1a0;
    arm7tdmis_regfile dut(.*);
    always #5 CLK=~CLK;
    function automatic [31:0] random_word;
        rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);return rng;
    endfunction
    function automatic integer physical(input integer r,input [4:0] bank);
        if(r<8 || r==15)return r;
        if(bank=='h11)return r+8;
        if(r<13)return r;
        case(bank)
            'h12:return r+10;
            'h13:return r+12;
            'h17:return r+14;
            'h1b:return r+16;
            default:return r;
        endcase
    endfunction
    function automatic [31:0] value(input integer r,input [4:0] bank);
        return r==15 ? pc_in+(t_bit ? 32'd4 : 32'd8) : expected[physical(r,bank)];
    endfunction
    task tick;
        @(posedge CLK);
        if(!nRESET)for(integer i=0;i<31;i++)expected[i]=0;
        else if(STATE_WRITE && STATE_INDEX<30)
            expected[STATE_INDEX<15 ? STATE_INDEX : STATE_INDEX+1]=STATE_WDATA;
        else if(dbg_we && dbg_addr!=15)
            expected[physical(dbg_addr,dbg_force_user_bank ? 5'h10 : mode)]=dbg_wdata;
        else if(CLKEN && wa_enable && wa_addr!=15)
            expected[physical(wa_addr,force_user_bank ? 5'h10 : mode)]=wa_data;
        #1;
        if(ra_data!==value(ra_addr,force_user_bank ? 5'h10 : mode) ||
           rb_data!==value(rb_addr,force_user_bank ? 5'h10 : mode) ||
           rc_data!==value(rc_addr,force_user_bank ? 5'h10 : mode) ||
           dbg_rdata!==value(dbg_addr,dbg_force_user_bank ? 5'h10 : mode))$fatal(1,"banked read mismatch");
        if(pc_written!==(wa_enable && wa_addr==15 && nRESET && CLKEN))$fatal(1,"PC write strobe changed");
        if(STATE_RDATA!==expected[STATE_INDEX<15 ? STATE_INDEX : STATE_INDEX<30 ? STATE_INDEX+1 : 0])
            $fatal(1,"save-state read mapping/reset");
        for(integer i=0;i<31;i++)if(VER_GPRS[i*32+:32]!==expected[i])$fatal(1,"physical snapshot/reset %0d",i);
        @(negedge CLK);
    endtask
    initial begin
        tick();nRESET=1;
        // Restore every physical bank while the architectural clock is stopped.
        for(integer i=0;i<30;i++)begin STATE_WRITE=1;STATE_INDEX=5'(i);STATE_WDATA=32'h33100000+32'(i);tick();end
        STATE_WRITE=0;nRESET=0;tick();nRESET=1; // stale RAM words must read as zero
        for(integer i=0;i<5000;i++)begin
            case(random_word()%8)
                0:mode='h10;1:mode='h11;2:mode='h12;3:mode='h13;
                4:mode='h17;5:mode='h1b;6:mode='h1f;7:mode=0;
            endcase
            {CLKEN,t_bit,wa_enable,force_user_bank,dbg_we,dbg_force_user_bank,STATE_WRITE}=7'(random_word());
            pc_in=random_word();wa_data=random_word();dbg_wdata=random_word();STATE_WDATA=random_word();
            {ra_addr,rb_addr,rc_addr,wa_addr,dbg_addr}=20'(random_word());STATE_INDEX=5'(random_word());
            nRESET=(i%97)!=0;tick();
        end
        $display("PASS regfile: banked/PC/debug/clock/reset, write priority, save-state and physical snapshots (5000 random cycles)");$finish;
    end
    initial begin #100000;$fatal(1,"regfile timeout");end
endmodule
