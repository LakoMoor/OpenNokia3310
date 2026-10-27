// SPDX-License-Identifier: GPL-3.0-or-later
// Diagnostic run of the actual big-endian CPU RTL, not a phone boot assertion.
#include "Vnokia_core.h"
#include "verilated.h"
#include <array>
#include <fstream>
#include <iostream>
#include <memory>
#include <vector>
#include <cstdint>
#include <cstdlib>

int main(int argc,char **argv) {
    if(argc<2) return 2;
    const unsigned limit=argc>2?std::stoul(argv[2]):10000000;
    const unsigned hold_power=argc>3?std::stoul(argv[3]):27000000;
    const std::string output_dir=std::getenv("NOKIA_TRACE_OUTPUT") ? std::getenv("NOKIA_TRACE_OUTPUT") : "build/boot_trace";
    // Reference MAD2 emulator uses a 24-bit, zero-backed address space.
    // Keep unmapped bus reads distinguishable from ARM architectural aborts.
    std::vector<uint8_t> memory(0x1000000,0);
    std::ifstream file(argv[1],std::ios::binary);
    file.read(reinterpret_cast<char*>(memory.data()+0x200000),0x200000);
    if(file.gcount()!=0x200000) { std::cerr<<"expected 2 MiB raw firmware\n"; return 2; }
    // Reset trampoline; original image starts at 0x200040, as in model_3310.
    const uint8_t trampoline[]={0xe5,0x1f,0xf0,0x04,0x00,0x20,0x00,0x40};
    for(int i=0;i<8;i++) memory[i]=trampoline[i];
    auto context=std::make_unique<VerilatedContext>();
    auto cpu=std::make_unique<Vnokia_core>(context.get());
    std::array<bool,512> seen{};
    unsigned lcd=0,unknown=0,flash_writes=0,fetches=0;
    std::array<uint8_t,504> frame{};
    unsigned lx=0,ly=0,lmode=0;
    bool lext=false,lvertical=false;
    uint32_t last_addr=0;
    uint32_t prev_pc=0;
    unsigned watches=0;
    uint32_t scripted_keys=0;
    unsigned aborts=0,sim_accesses=0,timer_accesses=0;
    unsigned dsp_messages=0,sim_commands=0;
    unsigned network_packets=0;
    uint16_t network_consumer=0;
    unsigned network_drains=0;
    unsigned returns=0;
    const unsigned memory_wait=std::getenv("NOKIA_MEM_WAIT")?std::stoul(std::getenv("NOKIA_MEM_WAIT")):0;
    unsigned wait_left=0;
    bool memory_pending=false;
    const bool cpu_trace=std::getenv("NOKIA_CPU_TRACE")!=nullptr;
    const bool queue_trace=std::getenv("NOKIA_QUEUE_TRACE")!=nullptr;
    const bool io_trace=std::getenv("NOKIA_IO_TRACE")!=nullptr;
    auto save_frame=[&](const std::string &name) {
        std::ofstream image(name);
        image<<"P2\n84 48\n255\n";
        for(unsigned y=0;y<48;y++) for(unsigned x=0;x<84;x++) {
            bool on=(frame[(y/8)*84+x]>>(y&7))&1;
            on=lmode==0?false:lmode==1?true:lmode==3?!on:on;
            image<<(on?0:255)<<" ";
        }
    };
    for(unsigned cycle=0;cycle<limit;cycle++) {
        // Reload a local stimulus file at bounded intervals, allowing continued
        // UI debugging without restarting the original ROM for each key press.
        if(argc>4 && cycle%1000000==0) {
            const uint32_t previous_keys=scripted_keys;
            std::ifstream keys_file(argv[4]);
            uint32_t at,mask;
            while(keys_file>>std::dec>>at>>std::hex>>mask) {
                if(at>cycle) break;
                scripted_keys=mask & 0x1ffffu;
            }
            if(previous_keys!=scripted_keys)
                std::cout<<"KEY mask="<<std::hex<<scripted_keys<<std::dec<<" cycle="<<cycle<<"\n"<<std::flush;
        }
        if(cycle && cycle%25000000==0) {
            save_frame(output_dir+"/frame-"+std::to_string(cycle)+".pgm");
            std::cout<<"PROGRESS cycle="<<cycle<<" pc="<<std::hex<<cpu->trace_pc<<" addr="<<cpu->mem_addr<<std::dec<<" LCD="<<lcd<<" reads="<<fetches<<"\n"<<std::flush;
        }
        cpu->clk=0;cpu->resetn=cycle>=8;cpu->keys=scripted_keys | (cycle<hold_power ? 1u<<16 : 0);
        cpu->mem_ready=0;cpu->mem_error=0;cpu->mem_rdata=0;
        cpu->eval();
        const uint32_t addr=cpu->mem_addr,base=addr&~3u;
        if(cpu->trace_exec && watches<32 && cpu->trace_pc!=prev_pc && (cpu->trace_pc==0x2eebee || cpu->trace_pc==0x2eec46 || cpu->trace_pc==0x2eebae)) {
            ++watches;
            std::cout<<"WATCH pc="<<std::hex<<cpu->trace_pc<<" cpsr="<<cpu->trace_cpsr;
            for(int i=0;i<8;i++) std::cout<<" r"<<i<<"="<<cpu->trace_regs[i];
            std::cout<<" lr="<<cpu->trace_regs[14]<<" svc_lr="<<cpu->trace_regs[26];
            std::cout<<std::dec<<" clock="<<cycle<<"\n";
        }
        if(cpu_trace && (cpu->trace_pc==0x2e51c0 || cpu->trace_pc==0x2e5114 || cpu->trace_pc==0x2e5158 || cpu->trace_pc==0x2e5160) && prev_pc!=cpu->trace_pc && returns++<24) {
            uint32_t sp=cpu->trace_regs[0];
            std::cout<<"FIQ-RETURN pc="<<std::hex<<cpu->trace_pc<<" r1="<<cpu->trace_regs[1]<<" spfiq="<<cpu->trace_regs[21]<<" cpsr="<<std::hex<<cpu->trace_cpsr<<" sp="<<sp<<" lrfiq="<<cpu->trace_regs[22]<<" stack=";
            for(unsigned k=0;k<32 && sp+k<memory.size();k++) std::cout<<unsigned(memory[sp+k])<<",";
            std::cout<<std::dec<<" cycle="<<cycle<<"\n";
        }
        prev_pc=cpu->trace_pc;
        last_addr=addr;
        if(!cpu->mem_valid)memory_pending=false;
        if(cpu->mem_valid && !memory_pending) {memory_pending=true;wait_left=memory_wait;}
        const bool memory_accept=cpu->mem_valid && wait_left==0;
        if(wait_left) --wait_left;
        if(memory_accept) {
            cpu->mem_ready=1;
            if(base+3<memory.size()) {
                cpu->mem_rdata=(uint32_t(memory[base])<<24)|(uint32_t(memory[base+1])<<16)|
                    (uint32_t(memory[base+2])<<8)|memory[base+3];
                if(cpu->mem_write) {
                    if(addr>=0x200000 && addr<0x400000) ++flash_writes;
                    if(queue_trace && ((cycle>16366000 && cycle<16380000 && addr>=0x116600 && addr<0x116900) || (addr>=0x104860 && addr<0x104880) || (addr>=0x10be60 && addr<0x10be70)))
                        std::cout<<"QUEUE-W pc="<<std::hex<<cpu->trace_pc<<" addr="<<addr<<" data="<<cpu->mem_wdata<<" be="<<unsigned(cpu->mem_be)<<std::dec<<" cycle="<<cycle<<"\n";
                    for(int lane=0;lane<4;lane++) if(cpu->mem_be&(8>>lane))
                        memory[base+lane]=(cpu->mem_wdata>>(24-lane*8))&255;
                } else ++fetches;
            } else {
                cpu->mem_error=1;
                if(aborts++<8) {
                    std::cout<<"ABORT pc="<<std::hex<<cpu->trace_pc<<" address="<<addr<<" cpsr="<<cpu->trace_cpsr<<"\n";
                    for(int i=0;i<31;i++) std::cout<<" r"<<i<<"="<<cpu->trace_regs[i];
                    std::cout<<std::dec<<"\n";
                }
            }
        }
        cpu->eval();
        if(io_trace && cpu->trace_valid && cpu->trace_ready && cpu->trace_address>=0x20000 && cpu->trace_address<0x20100 && cycle<150000) {
            std::cout<<"IO pc="<<std::hex<<cpu->trace_pc<<" addr="<<cpu->trace_address<<" wr="<<unsigned(cpu->trace_write)
                <<" data="<<cpu->trace_wdata<<" be="<<unsigned(cpu->trace_be)<<std::dec<<"\n";
        }
        if(cpu->trace_valid && cpu->trace_ready && cpu->trace_address>=0x20036 && cpu->trace_address<=0x2003f && sim_accesses++<350) {
            std::cout<<"SIM-IO pc="<<std::hex<<cpu->trace_pc<<" addr="<<cpu->trace_address<<" wr="<<unsigned(cpu->trace_write)<<" data="<<(cpu->trace_write?cpu->trace_wdata:cpu->trace_rdata)<<std::dec<<" cycle="<<cycle<<"\n";
        }
        if(cpu->trace_valid && cpu->trace_ready && cpu->trace_write && cpu->trace_address>=0x2000f && cpu->trace_address<=0x20013 && timer_accesses++<160) {
            std::cout<<"TIMER-W pc="<<std::hex<<cpu->trace_pc<<" addr="<<cpu->trace_address<<" data="<<cpu->trace_wdata<<std::dec<<" cycle="<<cycle<<"\n";
        }
        if(cpu->trace_sim_commands!=sim_commands) {
            sim_commands=cpu->trace_sim_commands;
            std::cout<<"SIM command="<<sim_commands<<" ins="<<std::hex<<unsigned(cpu->trace_sim_ins)<<std::dec<<" cycle="<<cycle<<"\n";
        }
        if(cpu->trace_dsp_messages!=dsp_messages) {
            dsp_messages=cpu->trace_dsp_messages;
            std::cout<<"DSP message="<<dsp_messages<<" opcode="<<std::hex<<unsigned(cpu->trace_dsp_op)<<" sub="<<unsigned(cpu->trace_dsp_sub)
                     <<std::dec<<" length="<<unsigned(cpu->trace_dsp_length)<<" payload=";
            for(unsigned i=0;i<12 && i<cpu->trace_dsp_length;i++) {
                unsigned octet=(cpu->trace_dsp_payload[2-i/4]>>((3-i%4)*8))&255;
                const char* digits="0123456789abcdef";
                std::cout<<digits[octet>>4]<<digits[octet&15];
            }
            if(cpu->trace_dsp_length>12)std::cout<<"...";
            std::cout<<" cycle="<<cycle<<"\n";
        }
        if(cpu->trace_network_packets!=network_packets) {
            network_packets=cpu->trace_network_packets;
            const unsigned producer=(unsigned(memory[0x101c8])<<8)|memory[0x101c9];
            const unsigned consumer=(unsigned(memory[0x101ca])<<8)|memory[0x101cb];
            std::cout<<"VIRTUAL CELL packet="<<network_packets<<" cycle="<<cycle<<" pc="<<std::hex<<cpu->trace_pc
                     <<" producer="<<producer<<" consumer="<<consumer<<std::dec<<"\n"<<std::flush;
        }
        if(network_packets) {
            const uint16_t consumer=(uint16_t(memory[0x101ca])<<8)|memory[0x101cb];
            if(consumer!=network_consumer) {
                network_consumer=consumer;
                ++network_drains;
                std::cout<<"MDI CONSUMER change="<<network_drains<<" cursor="<<std::hex<<consumer
                         <<" pc="<<cpu->trace_pc<<std::dec<<" cycle="<<cycle<<"\n"<<std::flush;
            }
        }
        if(cpu->unsupported_mmio && cpu->trace_valid && cpu->trace_ready) {
            unsigned slot=(cpu->trace_address&255)+(cpu->trace_write?256:0);
            if(!seen[slot]) {
                seen[slot]=true;++unknown;
                std::cout<<"unimplemented "<<(cpu->trace_write?"W":"R")<<" 0x"<<std::hex<<cpu->trace_address
                    <<" data=0x"<<cpu->trace_wdata<<" be="<<unsigned(cpu->trace_be)<<std::dec<<" cycle="<<cycle<<"\n";
            }
        }
        if(cpu_trace && cpu->trace_exception) std::cout<<"EXCEPTION pc="<<std::hex<<cpu->trace_pc<<" cpsr="<<cpu->trace_cpsr<<" mode="<<unsigned(cpu->trace_rf_mode)<<" user="<<unsigned(cpu->trace_user_bank)<<" we="<<unsigned(cpu->trace_rf_we)<<" reg="<<unsigned(cpu->trace_rf_addr)<<" value="<<cpu->trace_rf_data<<std::dec<<" cycle="<<cycle<<"\n";
        cpu->clk=1;cpu->eval();context->timeInc(1);
        if(cpu->lcd_wr) {
            if(lcd==0)std::cout<<"FIRST LCD cycle="<<cycle<<" pc="<<std::hex<<cpu->trace_pc<<std::dec<<"\n";
            if(lcd<16 || !cpu->lcd_dc) std::cout<<"LCD "<<(cpu->lcd_dc?"data":"command")<<" 0x"<<std::hex<<unsigned(cpu->lcd_data)<<std::dec<<"\n";
            ++lcd;
            const unsigned b=cpu->lcd_data;
            if(cpu->lcd_dc) {
                frame[ly*84+lx]=b;
                if(lvertical) {if(++ly==6) {ly=0;lx=(lx+1)%84;}}
                else if(++lx==84) {lx=0;ly=(ly+1)%6;}
            } else if((b&0xf8)==0x20) {lext=b&1;lvertical=b&2;}
            else if(!lext) {
                if((b&0xf8)==8) lmode=((b>>2)&1)*2+(b&1);
                else if(b&0x80) lx=std::min(b&127,83u);
                else if((b&0xf8)==0x40) ly=std::min(b&7,5u);
            }
        }
    }
    std::cout<<"TRACE ONLY: "<<limit<<" clocks; memory reads="<<fetches<<" LCD writes="<<lcd
        <<" distinct unsupported accesses="<<unknown<<" NOR writes="<<flash_writes
        <<" virtual packets="<<network_packets<<" MDI consumer changes="<<network_drains
        <<" last bus address=0x"<<std::hex<<last_addr<<"\n";
    std::cout<<"This does not assert a successful Nokia firmware boot.\n";
    std::ofstream ram(output_dir+"/ram.bin",std::ios::binary);
    ram.write(reinterpret_cast<const char*>(memory.data()),0x400000);
    cpu->final();
    save_frame(output_dir+"/lcd.pgm");
}
