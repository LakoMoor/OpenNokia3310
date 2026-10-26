"""Read real ARM bus / instruction PC from a diagnostic-capable N4 build."""
import argparse
import json
import time
from pathlib import Path
import serial
from nokia_protocol import Parser,command,status

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('port');p.add_argument('--seconds',type=float,default=8)
p.add_argument('--output',type=Path,default=Path('build/boot-diagnostics.json'))
a=p.parse_args();packets=[];parser=Parser()
with serial.Serial(a.port,115200,timeout=.1,write_timeout=1) as device:
    device.reset_input_buffer()
    try:
        for name,value in [('bus',0),('pc',128)]:
            device.write(command(7,value))
            # Discard any already buffered status from the preceding selection.
            until=time.monotonic()+.4
            while time.monotonic()<until:parser.feed(device.read(4096))
            until=time.monotonic()+a.seconds
            while time.monotonic()<until:
                for kind,body in parser.feed(device.read(4096)):
                    if kind==2 and len(body)>=7:
                        entry={'source':name,**status(body)};packets.append(entry)
                        print(json.dumps(entry),flush=True)
    finally:device.write(command(7,0))
a.output.parent.mkdir(parents=True,exist_ok=True)
a.output.write_text(json.dumps(packets,indent=2))
if not packets:raise SystemExit('No N4 diagnostics received')
