`timescale 1ns/1ps
module mdi_injector_tb;
    reg clk=0,reset=1,in_valid=0,in_last=0;
    reg [7:0] in_data=0;
    reg cell_mode=0,cell_start=0;
    wire cell_valid,cell_last,cell_busy,cell_done;
    wire [7:0] cell_data;
    reg [15:0] expected_producer=16'h82;
    wire in_ready,busy,done,error,fiq0,m_valid,m_write;
    wire [31:0] m_address,m_wdata;
    wire [3:0] m_be;
    reg [31:0] memory[0:127];
    reg [3:0] ticks=0;
    wire m_ready=ticks==7;
    wire [31:0] m_rdata=memory[m_address[8:2]];
    integer writes=0,interrupts=0,errors=0;
    reg held=0;
    reg [68:0] previous;
    always #5 clk=~clk;
    mdi_injector dut(.clk(clk),.reset(reset),.in_valid(cell_mode ? cell_valid : in_valid),
        .in_data(cell_mode ? cell_data : in_data),.in_last(cell_mode ? cell_last : in_last),
        .in_ready(in_ready),.busy(busy),.done(done),.error(error),.fiq0(fiq0),
        .m_valid(m_valid),.m_write(m_write),.m_address(m_address),.m_wdata(m_wdata),.m_be(m_be),.m_ready(m_ready),.m_rdata(m_rdata));
    virtual_cell cell_source(.clk(clk),.reset(reset),.start(cell_start),.bcch(1'b1),.channel_confirm(1'b0),.confirm_token(8'd0),.all_rssi(1'b0),.no_psw(1'b0),.si_kind(2'd0),.plmn(24'h00f110),
        .lac(16'h1234),.cell_id(16'h5678),.arfcn(10'd586),.bsic(6'd27),.frame_number(22'h234567),
        .ready(cell_mode && in_ready),.valid(cell_valid),.last(cell_last),.data(cell_data),.busy(cell_busy),.done(cell_done));
    always @(posedge clk)begin
        ticks<=ticks+1'b1;
        if(!reset)begin
            if(held && (!m_valid || {m_write,m_address,m_wdata,m_be}!==previous))$fatal(1,"stalled memory request changed");
            held<=m_valid && !m_ready;previous<={m_write,m_address,m_wdata,m_be};
            if(error)errors++;
            if(fiq0)begin
                interrupts++;
                if(memory['h1c8/4][31:16]!==expected_producer)$fatal(1,"FIQ before producer commit");
            end
            if(m_valid && m_ready && m_write)begin
                writes++;
                for(integer lane=0;lane<4;lane++)if(m_be[lane])memory[m_address[8:2]][lane*8+:8]<=m_wdata[lane*8+:8];
                if(m_address==32'h101c8 && m_be!==12)$fatal(1,"MCU consumer must never be written");
            end
        end else held<=0;
    end
    task send(input [7:0] value,input bit ending);
        wait(in_ready);@(negedge clk);in_data=value;in_last=ending;in_valid=1;
        @(negedge clk);in_valid=0;in_last=0;
    endtask
    initial begin
        for(integer i=0;i<128;i++)memory[i]=0;
        memory['h1c8/4]=32'h00e300e2; // not empty
        repeat(4)@(negedge clk);reset=0;
        send(3,0);send('h80,0);send('haa,0);send('hbb,0);send('hcc,1);
        repeat(100)@(negedge clk);
        if(writes || fiq0 || !busy)$fatal(1,"nonempty queue overwritten");
        memory['h1c8/4]=32'h00e300e3;
        wait(done);repeat(3)@(negedge clk);
        if(writes!=4 || interrupts!=1 || memory['h1c4/4][15:0]!==16'h0380 ||
           memory['h100/4]!==32'haabbcc00 || memory['h1c8/4]!==32'h008200e3)
            $fatal(1,"record packing, ring wrap, odd-byte padding or ownership");
        // Actual SI3 generator -> packet buffering -> stalled DSP bus -> MCU ring.
        memory['h1c8/4]=32'h00800080;expected_producer=16'h92;
        cell_mode=1;@(negedge clk);cell_start=1;@(negedge clk);cell_start=0;
        wait(cell_done);wait(done);repeat(3)@(negedge clk);cell_mode=0;
        if(writes!=23 || interrupts!=2 || memory['h100/4]!==32'h2180501b ||
           memory['h10c/4]!==32'h49061b56 || memory['h110/4]!==32'h7800f110 ||
           memory['h114/4][31:16]!==16'h1234 || memory['h120/4]!==32'h2b2b2b00 ||
           memory['h1c8/4]!==32'h00920080)$fatal(1,"SI3 generator-to-ring integration");
        send(9,0);send('h80,1);repeat(5)@(negedge clk);
        if(errors!=1 || writes!=23)$fatal(1,"malformed record accepted");
        // Long ALL_RSSI-sized record must fit and wrap without aliasing bytes.
        memory['h1c8/4]=32'h00e300e3;expected_producer=16'hd1;
        send(162,0);send('h8b,0);
        for(integer i=0;i<162;i++)send(8'(i),i==161);
        wait(done);repeat(3)@(negedge clk);
        if(writes!=106 || interrupts!=3 || memory['h1c8/4]!==32'h00d100e3)$fatal(1,"long record count/ownership");
        for(integer k=0;k<82;k++)begin
            integer slot;
            reg [15:0] actual,expected;
            slot='he3+k;if(slot>='he4)slot-=100;
            actual=slot%2 ? memory[(slot*2)/4][15:0] : memory[(slot*2)/4][31:16];
            expected=k==0 ? 16'ha28b : {8'(2*k-2),8'(2*k-1)};
            if(actual!==expected)$fatal(1,"long record word %0d %h != %h",k,actual,expected);
        end
        // Oversized framing is drained, never committed into the finite ring.
        send(195,0);for(integer i=1;i<196;i++)send(0,0);send(0,1);
        repeat(5)@(negedge clk);
        if(errors!=2 || writes!=106)$fatal(1,"oversized record accepted");
        send(1,0);@(negedge clk);reset=1;@(negedge clk);reset=0;
        if(busy || m_valid || fiq0)$fatal(1,"reset did not discard partial record");
        $display("PASS MDI injector: empty-ring ownership, wait states, wrap, odd byte, commit/FIQ ordering, invalid/reset");$finish;
    end
    initial begin #100000;$fatal(1,"timeout");end
endmodule
