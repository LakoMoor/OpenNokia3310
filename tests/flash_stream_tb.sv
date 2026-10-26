`timescale 1ns/1ps
// Long SPI transaction with variable SDRAM stalls and a reset/reload.
module flash_stream_tb;
    reg clk=0,reset=1,mem_ready=0,flash_miso=0;
    wire done,req,flash_cs_n,flash_clk,flash_mosi;
    wire [20:0] addr;
    wire [31:0] wdata,first_word;
    reg ack=0;
    integer bit_count=0,accepted=0,delay_count=0,transactions=0;
    reg [31:0] command_word=0,word_data;
    always #5 clk=~clk;
    flash_boot #(.WORDS(512),.CLEAR_WORDS(17),.DEST_BASE(21'h80000)) dut(.*);
    function automatic [31:0] contents(input integer word_index);
        case(word_index)
            0:contents=32'h20650f59;
            1:contents=32'h05fd8012;
            16:contents=32'he3a01602;
            17:contents=32'he5910000;
            default:contents=32'ha5c35a69^(32'(word_index)*32'h10203041);
        endcase
    endfunction
    always @(negedge flash_cs_n)begin
        bit_count=0;command_word=0;transactions++;
    end
    always @(posedge flash_cs_n)if(!reset && accepted!=529)$fatal(1,"SPI transaction terminated at DMA word %0d",accepted);
    always @(posedge flash_clk)if(!flash_cs_n)begin
        if(bit_count<32)begin
            command_word={command_word[30:0],flash_mosi};
            if(bit_count==31 && command_word!=32'h03200000)$fatal(1,"SPI command/address");
        end
        bit_count++;
    end
    always @(negedge flash_clk)if(!flash_cs_n && bit_count>=32)begin
        word_data=contents((bit_count-32)/32);
        flash_miso=word_data[31-(bit_count-32)%32];
    end
    always @(negedge clk)begin
        ack=0;
        if(req)begin
            if(delay_count==0)ack=1;
            else delay_count--;
        end
    end
    always @(posedge clk)begin
        if(reset)begin accepted=0;delay_count=0;end
        else if(req && ack)begin
            if(accepted<17)begin
                if(addr!==21'(accepted) || wdata!==0)$fatal(1,"clear data/address");
            end else if(addr!==21'h80000+21'(accepted-17) || wdata!==contents(accepted-17))
                $fatal(1,"ROM corruption word=%0d address=%h data=%h",accepted-17,addr,wdata);
            accepted++;delay_count=(accepted*17)%97;
        end
    end
    initial begin
        repeat(5)@(negedge clk);reset=0;mem_ready=1;
        wait(done);@(negedge clk);
        if(first_word!==contents(0) || accepted!=529)$fatal(1,"first transfer incomplete");
        reset=1;repeat(4)@(negedge clk);reset=0;
        wait(done);@(negedge clk);
        if(accepted!=529 || transactions!=2 || !flash_cs_n)$fatal(1,"reset/reload failed");
        $display("PASS flash stream: 512 ROM words, variable 0-96 cycle stalls, continuous CS, reset/reload");$finish;
    end
    initial begin #3000000;$fatal(1,"stream timeout");end
endmodule
