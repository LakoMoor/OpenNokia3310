// SPDX-License-Identifier: GPL-3.0-or-later
// NHM-5 MAD2 register model, based on the DCT3 reference emulator.
// Keypad, LCD GENSIO, CTSI timers, IRQ/FIQ, CCONT ADC/RTC, SIMI and MBUS TX.
// DSP/HPI and NOR have separate bus blocks. Audio and RF remain unimplemented.
module mad2_mmio #(parameter CLK_HZ=27_000_000) (
    input logic clk, reset,
    input logic valid, write,
    input logic [7:0] address,
    input logic [31:0] wdata,
    input logic [3:0] byte_enable,
    output logic ready,
    output logic [31:0] rdata,
    input logic [16:0] keys,
    input logic dsp_fiq0,dsp_irq4,
    output logic irq, fiq,
    output logic lcd_wr, lcd_dc,
    output logic [7:0] lcd_data,
    output logic unsupported
);
    logic [7:0] shadow [0:255];
    logic [7:0] init_addr;
    logic initialized;
    logic [7:0] row_signal, row_direction, columns;
    logic [7:0] irq_pending, fiq_pending, irq_mask, fiq_mask, int_control;
    logic [16:0] keys_q;
    logic [15:0] timer0, timer1, destination;
    logic [7:0] timer_div, timer_prescale;
    logic [25:0] phase, seconds_div, cs_div;
    logic [2:0] ct_control;
    logic [7:0] ccont [0:15];
    logic [3:0] cc_addr;
    logic cc_have_addr;
    logic [2:0] adc_channel;
    logic [9:0] adc;
    logic [7:0] cc_q;
    logic [31:0] value, result;
    logic known;
    wire sim_select=address>=8'h36 && address<=8'h3f;
    wire [7:0] sim_rdata;
    wire sim_fiq;
    sim_card #(.CLK_HZ(CLK_HZ)) u_sim (.clk(clk),.reset(reset),
        .valid(valid && ready && sim_select),.write(write),.address(address),.wdata(value[7:0]),
        .rdata(sim_rdata),.fiq(sim_fiq),.commands(),.last_ins());
    logic [6:0] mbus_count,mbus_kick;
    logic mbus_empty;
    keypad_3310 u_keypad (.keys(keys), .row_signal(row_signal), .row_direction(row_direction), .columns(columns));
    always_comb begin
        // Bus values are lane-aligned by arm7tdmi_mister BIG_ENDIAN=1.
        if (byte_enable == 4'hf) value=wdata;
        else if (byte_enable == 4'hc) value={16'b0,wdata[31:16]};
        else if (byte_enable == 4'h3) value={16'b0,wdata[15:0]};
        else case(address[1:0])
            0: value={24'b0,wdata[31:24]};
            1: value={24'b0,wdata[23:16]};
            2: value={24'b0,wdata[15:8]};
            3: value={24'b0,wdata[7:0]};
        endcase
        case (adc_channel)
            1: adc=10'h220;
            2: adc=10'h220;
            3: adc=10'h026;
            4: adc=10'h200;
            default: adc=0;
        endcase
        case(cc_addr)
            2: cc_q=adc[7:0];
            3: cc_q={6'b101100,adc[9:8]};
            default: cc_q=ccont[cc_addr];
        endcase
        known=1;
        result={24'b0,shadow[address]};
        case(address)
            8'h00: result=32'ha1;
            8'h01: result={24'b0,shadow[1]};
            8'h02: result=shadow[2][0] ? 32'h53 : {24'b0,shadow[2] & 8'hef};
            8'h03: result={24'b0,shadow[3]};
            8'h04: result=byte_enable==4'hf || byte_enable==4'hc || byte_enable==4'h3 ? {16'b0,timer1} : {24'b0,timer1[7:0]};
            8'h05: result={24'b0,timer1[15:8]};
            8'h08: result={24'b0,fiq_pending};
            8'h09: result={24'b0,irq_pending};
            8'h0a: result={24'b0,fiq_mask};
            8'h0b: result={24'b0,irq_mask};
            8'h0c: result={24'b0,int_control};
            8'h0f: result={24'b0,timer_div};
            8'h10: result=byte_enable==4'hf || byte_enable==4'hc || byte_enable==4'h3 ? {16'b0,timer0} : {24'b0,timer0[7:0]};
            8'h11: result={24'b0,timer0[15:8]};
            8'h12: result=byte_enable==4'hf || byte_enable==4'hc || byte_enable==4'h3 ? {16'b0,destination} : {24'b0,destination[7:0]};
            8'h13: result={24'b0,destination[15:8]};
            8'h16: result={29'b0,ct_control};
            8'h18: result={24'b0,shadow[8'h18] & 8'h7f};
            8'h19: result=mbus_empty ? 32'h50 : 32'h40;
            8'h1a: result=0;
            8'h15,8'h1b,8'h1c,8'h1d,8'h1e: result={24'b0,shadow[address]};
            8'h28: result={24'b0,row_signal};
            8'h2a: result={24'b0,columns};
            8'ha8: result={24'b0,row_direction};
            8'h2c,8'h2d,8'h2e,8'h6e: result=0;
            8'h6c: result={24'b0,cc_q};
            8'h6d: result=7;
            default: known=0;
        endcase
        if(sim_select) begin known=1;result={24'b0,sim_rdata};end
        if(byte_enable==4'hf) rdata=result;
        else if(byte_enable==4'hc) rdata={result[15:0],16'b0};
        else if(byte_enable==4'h3) rdata={16'b0,result[15:0]};
        else case(address[1:0])
            0: rdata={result[7:0],24'b0};
            1: rdata={8'b0,result[7:0],16'b0};
            2: rdata={16'b0,result[7:0],8'b0};
            3: rdata={24'b0,result[7:0]};
        endcase
        ready=initialized;
        unsupported=valid && ready && !known;
        irq=|(irq_pending & ~irq_mask) && !int_control[3];
        fiq=((|(fiq_pending & ~fiq_mask)) || (ct_control[1] && !ct_control[2])) && !int_control[1];
    end
    always_ff @(posedge clk) begin
        lcd_wr<=0;
        keys_q<=keys;
        if(!initialized) begin
            shadow[init_addr]<=init_addr==1 ? 8'h01 : 8'h00;
            if(init_addr==255) initialized<=1;
            else init_addr<=init_addr+1'b1;
        end
        if(phase >= CLK_HZ-33055) begin
            phase<=phase-(CLK_HZ-33055);
            timer1<=timer1+1'b1;
            if(timer1==65535) fiq_pending[5]<=1;
            if(timer_prescale==timer_div) begin
                timer_prescale<=0; timer0<=timer0+1'b1;
                if(timer0+16'd1==destination) fiq_pending[4]<=1;
            end else timer_prescale<=timer_prescale+1'b1;
        end else phase<=phase+26'd33055;
        if(cs_div==CLK_HZ/100-1) begin
            cs_div<=0;
            if(ct_control[0] && !ct_control[2]) ct_control[1]<=1;
        end else cs_div<=cs_div+1'b1;
        if(seconds_div==CLK_HZ-1) begin
            seconds_div<=0;
            if(ccont[7]==59) begin
                ccont[7]<=0;
                if(ccont[8]==59) begin
                    ccont[8]<=0;
                    if(ccont[9]==23) begin ccont[9]<=0; ccont[10]<=ccont[10]+1'b1; end
                    else ccont[9]<=ccont[9]+1'b1;
                end else ccont[8]<=ccont[8]+1'b1;
            end else ccont[7]<=ccont[7]+1'b1;
        end else seconds_div<=seconds_div+1'b1;
        if(keys!=keys_q) irq_pending[0]<=1;
        if(dsp_fiq0) fiq_pending[0]<=1;
        if(sim_fiq) fiq_pending[6]<=1;
        if(dsp_irq4) irq_pending[4]<=1;
        if(mbus_kick!=0) begin
            mbus_kick<=mbus_kick-1'b1;
            if(mbus_kick==1) fiq_pending[3]<=1;
        end
        if(mbus_count!=0) begin
            mbus_count<=mbus_count-1'b1;
            if(mbus_count==1) begin
                mbus_empty<=1;
                if(shadow[8'h18][5]) fiq_pending[2]<=1;
            end
        end
        // A GENSIO read terminates the selected CCONT transaction. Without
        // this, the following ADC-high register selector is consumed as data.
        if(valid && ready && !write && address==8'h6c) cc_have_addr<=0;
        if(valid && ready && write) begin
            shadow[address]<=value[7:0];
            case(address)
                8'h08: fiq_pending<=fiq_pending & ~value[7:0];
                8'h09: irq_pending<=irq_pending & ~value[7:0];
                8'h0a: begin
                    fiq_mask<=value[7:0];
                    if(fiq_mask[3] && !value[3] && !shadow[8'h18][5]) mbus_kick<=64;
                end
                8'h0b: irq_mask<=value[7:0];
                8'h0c: int_control<=value[7:0];
                8'h0f: begin timer_div<=value[7:0]; timer_prescale<=0; end
                8'h10: begin
                    if(byte_enable==4'hf || byte_enable==4'hc || byte_enable==4'h3) timer0<=value[15:0];
                    else timer0[7:0]<=value[7:0];
                end
                8'h11: timer0[15:8]<=value[7:0];
                8'h12: begin
                    if(byte_enable==4'hf || byte_enable==4'hc || byte_enable==4'h3) destination<=value[15:0];
                    else destination[7:0]<=value[7:0];
                end
                8'h13: destination[15:8]<=value[7:0];
                8'h16: ct_control<=value[2:0] & 3'b101;
                8'h18: begin
                    if(value[5] && mbus_empty) fiq_pending[2]<=1;
                    else fiq_pending[2]<=0;
                end
                8'h1a: begin mbus_count<=64;mbus_empty<=0;fiq_pending[2]<=0;end
                8'h28: row_signal<=value[7:0];
                8'ha8: row_direction<=value[7:0];
                8'h2d: cc_have_addr<=0;
                8'h2c: begin
                    if(!cc_have_addr) begin cc_addr<=value[6:3]; cc_have_addr<=1; end
                    else begin
                        cc_have_addr<=0;
                        if(cc_addr==14) ccont[14]<=ccont[14] & ~(value[7:0] & 8'hfe);
                        else ccont[cc_addr]<=value[7:0];
                        if(cc_addr==0 && value[3]) adc_channel<=value[6:4];
                    end
                end
                8'h2e,8'h6e: begin lcd_wr<=1; lcd_dc<=address==8'h2e; lcd_data<=value[7:0]; end
                default: ;
            endcase
        end
        if(reset) begin
            initialized<=0; init_addr<=0; row_signal<=255; row_direction<=255;
            irq_pending<=0; fiq_pending<=0; irq_mask<=255; fiq_mask<=255; int_control<=0;
            timer0<=0; timer1<=0; destination<=0; timer_div<=0; timer_prescale<=0;
            phase<=0; seconds_div<=0; cs_div<=0; ct_control<=3'b100; keys_q<=0;
            for(int i=0;i<16;i=i+1) ccont[i]<=0;
            ccont[14]<=0; ccont[15]<=255;
            cc_addr<=0; cc_have_addr<=0; adc_channel<=2;
            mbus_count<=0;mbus_kick<=0;mbus_empty<=1;
            lcd_wr<=0; lcd_dc<=0; lcd_data<=0;
        end
    end
endmodule
