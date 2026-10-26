"""Compare actual SDRAM words cached by the nokia_romtest FPGA target."""
from pathlib import Path
import argparse
import json
import time
import zlib
import serial
from nokia_protocol import Parser,keys

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('port');p.add_argument('firmware',type=Path)
a=p.parse_args();rom=a.firmware.read_bytes();parser=Parser();results=[]
expected_crc=zlib.crc32(rom)
with serial.Serial(a.port,115200,timeout=.05,write_timeout=1) as dev:
    dev.reset_input_buffer()
    try:
        dev.write(keys(0));end=time.monotonic()+12;actual_crc=None
        # Discard previous mode packets, then require completed full-ROM CRC.
        flush_until=time.monotonic()+.5
        while time.monotonic()<flush_until:parser.feed(dev.read(4096))
        while time.monotonic()<end and actual_crc is None:
            for kind,b in parser.feed(dev.read(4096)):
                if kind==0 and b[0]&3==3 and int.from_bytes(b[5:7],'big')==65535:
                    actual_crc=int.from_bytes(b[1:5],'big')
        print(json.dumps(dict(expected_crc=f'{expected_crc:08x}',actual_crc=None if actual_crc is None else f'{actual_crc:08x}',match=actual_crc==expected_crc)),flush=True)
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
if actual_crc!=expected_crc or not all(item['match'] for item in results):
    raise SystemExit('FAIL: SPI-to-SDRAM ROM integrity; do not claim successful phone boot')
print('PASS: full 2 MiB ROM CRC32 and sampled entry instructions match')
