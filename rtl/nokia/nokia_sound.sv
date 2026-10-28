// SPDX-License-Identifier: GPL-3.0-or-later
// Hardware register taps from the DCT3 model: MAD2 PWM buzzer and DSP tone regs.
module nokia_audio_regs (
    input logic clk,reset,write,
    input logic [31:0] address,wdata,
    input logic [3:0] be,
    output logic [72:0] control
);
    logic [15:0] f1,f2,amp,divider;
    logic [7:0] volume;
    logic enabled;
    assign control={f1,f2,amp,divider,volume,enabled};
    always_ff @(posedge clk) begin
        if(write) for(int i=0;i<4;i=i+1) if(be[3-i]) begin
            case((address & 32'hfffffffc)+32'(i))
                32'h100ae:f1[15:8]<=wdata[31-i*8-:8];
                32'h100af:f1[7:0]<=wdata[31-i*8-:8];
                32'h100b0:f2[15:8]<=wdata[31-i*8-:8];
                32'h100b1:f2[7:0]<=wdata[31-i*8-:8];
                32'h100b6:amp[15:8]<=wdata[31-i*8-:8];
                32'h100b7:amp[7:0]<=wdata[31-i*8-:8];
                32'h20015:enabled<=wdata[29-i*8];
                32'h2001c:divider[15:8]<=wdata[31-i*8-:8];
                32'h2001d:divider[7:0]<=wdata[31-i*8-:8];
                32'h2001e:volume<=wdata[31-i*8-:8];
                default: ;
            endcase
        end
        if(reset) begin f1<=0;f2<=0;amp<=0;divider<=0;volume<=0;enabled<=0;end
    end
endmodule

module nokia_sound #(parameter CLK_HZ=16_875_000) (
    input logic clk,reset,
    input logic [72:0] control,
    input logic [3:0] volume,
    input logic test_start,
    output logic audio_clk,
    output logic [15:0] sample,
    output logic speaker_p,speaker_n,test_active
);
    wire [15:0] f1=control[72:57],f2=control[56:41],amp=control[40:25],divider=control[24:9];
    wire enabled=control[0];
    // PUP volume is 0..255; four fractional amplitude bits avoid a multiplier.
    wire signed [15:0] buzzer_level=$signed({4'b0,control[8:1],4'b0});
    logic [17:0] p1,p2,pt;
    logic [24:0] tick13;
    logic [15:0] buzzer_count;
    logic [24:0] test_count;
    logic [24:0] audio_phase;
    logic [16:0] delta;
    logic signed [15:0] mixed;
    logic signed [20:0] scaled;
    wire test_on=test_count!=0;
    assign test_active=test_on;
    always_comb begin
        mixed=0;
        if(amp!=0) begin
            if(f1!=0) mixed=mixed+(p1<96000 ? 16'sd2048 : -16'sd2048);
            if(f2!=0) mixed=mixed+(p2<96000 ? 16'sd2048 : -16'sd2048);
        end
        if(enabled && divider!=0) mixed=mixed+(buzzer_count<(divider>>1) ? buzzer_level : -buzzer_level);
        if(test_on) mixed=mixed+(pt<96000 ? 16'sd4096 : -16'sd4096);
        scaled=$signed(mixed)*$signed({1'b0,volume});
        sample=16'(scaled>>>4);
        speaker_p=volume!=0 && (amp!=0 || (enabled && divider!=0 && control[8:1]!=0) || test_on) ? delta[16] : 1'b0;
        speaker_n=volume!=0 && (amp!=0 || (enabled && divider!=0 && control[8:1]!=0) || test_on) ? ~delta[16] : 1'b0;
    end
    always_ff @(posedge clk) begin
        // DSP tones are sampled at codec rate. Quarter-Hz phase units give
        // exactly the same frequencies with 18-bit rather than 28-bit NCOs.
        if(audio_phase+96_000>=CLK_HZ && !audio_clk)begin
            p1<=p1+{2'b0,f1}>=192000 ? p1+{2'b0,f1}-192000 : p1+{2'b0,f1};
            p2<=p2+{2'b0,f2}>=192000 ? p2+{2'b0,f2}-192000 : p2+{2'b0,f2};
            pt<=pt+4000>=192000 ? pt+4000-192000 : pt+4000;
        end
        tick13<=tick13+13_000_000>=CLK_HZ ? tick13+13_000_000-CLK_HZ : tick13+13_000_000;
        if(tick13+13_000_000>=CLK_HZ) buzzer_count<=buzzer_count+1'b1>=divider ? 16'd0 : buzzer_count+1'b1;
        if(!enabled || divider==0) buzzer_count<=0;
        if(test_count!=0) test_count<=test_count-1'b1;
        if(test_start) test_count<=CLK_HZ;
        if(audio_phase+96_000>=CLK_HZ) begin audio_phase<=audio_phase+96_000-CLK_HZ;audio_clk<=~audio_clk;end
        else audio_phase<=audio_phase+96_000;
        delta<={1'b0,delta[15:0]}+{1'b0,sample^16'h8000};
        if(reset) begin p1<=0;p2<=0;pt<=0;tick13<=0;buzzer_count<=0;test_count<=0;audio_phase<=0;audio_clk<=0;delta<=0;end
    end
endmodule
