"""Host-side control, live LCD capture and audio-state evidence for the Android link."""
import argparse
import json
from pathlib import Path
import time
import serial
from nokia_protocol import Parser, command, keys, status

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('port')
p.add_argument('--seconds',type=float,default=5)
p.add_argument('--output',type=Path,default=Path('build/usb-lcd.pgm'))
p.add_argument('--menu',action='store_true')
p.add_argument('--volume',type=int,choices=range(11))
p.add_argument('--audio-test',action='store_true')
a=p.parse_args()
parser=Parser()
frames=0
audio=0
a.output.parent.mkdir(parents=True,exist_ok=True)
with serial.Serial(a.port,115200,timeout=.1,write_timeout=1) as port:
    port.reset_input_buffer()
    port.write(command(5,3 if a.menu else 1))
    if a.volume is not None:port.write(command(6,a.volume))
    if a.audio_test:port.write(command(8,1))
    end=time.monotonic()+a.seconds
    try:
        while time.monotonic()<end:
            for kind,body in parser.feed(port.read(1024)):
                if kind==1 and len(body)==504:
                    pixels=bytes(0 if body[y//8*84+x] & (1<<(y%8)) else 255 for y in range(48) for x in range(84))
                    a.output.write_bytes(b'P5\n84 48\n255\n'+pixels)
                    frames+=1
                elif kind==3 and len(body)==11:
                    audio+=1
                    print(json.dumps(dict(tone1_hz=int.from_bytes(body[:2],'big')/4,
                        tone2_hz=int.from_bytes(body[2:4],'big')/4,amplitude=int.from_bytes(body[4:6],'big'),
                        buzzer_divider=int.from_bytes(body[6:8],'big'),buzzer_on=bool(body[8]),volume=body[10])))
        print(json.dumps(dict(lcd_frames=frames,audio_events=audio,snapshot=str(a.output))))
    finally:
        port.write(keys(0)+command(5,0))
if not frames:raise SystemExit('No N4 LCD frames; update the FPGA bitstream or check USB')
