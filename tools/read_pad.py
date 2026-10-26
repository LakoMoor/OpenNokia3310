"""Read physical controller diagnostics from the nokia_io_top target only."""
import argparse
import json
import time
import serial

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('port')
p.add_argument('--seconds',type=float,default=10)
a=p.parse_args()
buffer=bytearray()
previous=None
with serial.Serial(a.port,115200,timeout=.1,write_timeout=1) as port:
    port.reset_input_buffer()
    end=time.monotonic()+a.seconds
    while time.monotonic()<end:
        buffer.extend(port.read(64))
        while True:
            at=buffer.find(b'N3')
            if at<0:
                buffer[:]=buffer[-1:]
                break
            del buffer[:at]
            if len(buffer)<10: break
            packet=buffer[:10]
            check=0
            for value in packet: check^=value
            if check:
                del buffer[0]
                continue
            del buffer[:10]
            if packet==previous: continue
            previous=packet
            print(json.dumps(dict(connected=bool(packet[2]&1),
                controller_id=f'{packet[4]:02x}',buttons0=f'{packet[5]:02x}',
                buttons1=f'{packet[6]:02x}',nokia_keys=f'{int.from_bytes(packet[7:9],"big"):04x}')),flush=True)
if previous is None: raise SystemExit('No controller diagnostics received')
