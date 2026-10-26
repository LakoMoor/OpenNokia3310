"""Compare actual SDRAM words cached by the nokia_romtest FPGA target."""
from pathlib import Path
import argparse
import json
import time
import serial
from nokia_protocol import Parser,keys

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('port');p.add_argument('firmware',type=Path)
a=p.parse_args();rom=a.firmware.read_bytes();parser=Parser();results=[]
with serial.Serial(a.port,115200,timeout=.05) as dev:
    dev.reset_input_buffer()
    try:
        for index in [0,1,2,3,*range(16,32)]:
            end=time.monotonic()+2;found=None
            while time.monotonic()<end and found is None:
                dev.write(keys(0x10000|index))
                for kind,b in parser.feed(dev.read(4096)):
                    if kind==0 and b[0]&2 and int.from_bytes(b[5:7],'big')==index:
                        found=int.from_bytes(b[1:5],'big')
            expected=int.from_bytes(rom[index*4:index*4+4],'big')
            entry=dict(address=f'{0x200000+index*4:08x}',expected=f'{expected:08x}',
                       actual=None if found is None else f'{found:08x}',match=found==expected)
            results.append(entry);print(json.dumps(entry),flush=True)
    finally:dev.write(keys(0))
Path('build/rom-word-probe.json').write_text(json.dumps(results,indent=2))
