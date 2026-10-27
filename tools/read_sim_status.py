"""Read SIM command count/last instruction from a diagnostic FPGA image.

This selects the N4 status address field using opcode 7 value 0x40, then
restores normal address reporting. It does not expose APDU contents.
"""
import argparse
import json
import time
import serial
from nokia_protocol import Parser, command, status

def decode(body):
    value=int.from_bytes(body[1:5],'big')
    return {'sim_commands_mod_2_24':value & 0xffffff,'last_instruction':f'0x{value >> 24:02x}'}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('port')
    parser.add_argument('--seconds',type=float,default=5)
    args=parser.parse_args()
    if args.seconds<=0:parser.error('--seconds must be positive')
    decoder=Parser();received=0;previous=None
    with serial.Serial(args.port,115200,timeout=.1,write_timeout=1) as port:
        try:
            port.reset_input_buffer();port.write(command(7,0x40));port.flush()
            # Discard status already queued before the mode-select command.
            time.sleep(.5);port.reset_input_buffer();decoder=Parser()
            end=time.monotonic()+args.seconds
            while time.monotonic()<end:
                for kind,body in decoder.feed(port.read(1024)):
                    if kind==2 and len(body)>=10:
                        received+=1;item={**decode(body),**{k:v for k,v in status(body).items() if k!='address'}}
                        if item!=previous:print(json.dumps(item),flush=True);previous=item
        finally:
            port.write(command(7,0));port.flush()
    if not received:raise SystemExit('No N4 status packets received')

if __name__=='__main__':main()
