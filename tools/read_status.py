"""Read N3 development telemetry from a Tang running nokia_top."""
import argparse
import json
import time
import serial

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('port')
p.add_argument('--seconds',type=float,default=5)
a=p.parse_args()
buffer=bytearray()
received=0
previous=None
with serial.Serial(a.port,115200,timeout=0.1) as port:
    port.reset_input_buffer()
    end=time.monotonic()+a.seconds
    while time.monotonic()<end:
        buffer.extend(port.read(64))
        while True:
            at=buffer.find(b'N3')
            if at<0:
                buffer[:]=buffer[-1:]
                break
            if at: del buffer[:at]
            if len(buffer)<10: break
            packet=buffer[:10]
            checksum=0
            for byte in packet: checksum^=byte
            if checksum:
                del buffer[0]
                continue
            del buffer[:10]
            received+=1
            if packet==previous: continue
            previous=packet
            flags=packet[2]
            print(json.dumps(dict(sdram_ready=bool(flags&1),rom_done=bool(flags&2),
                memory_error=bool(flags&4),lcd_overflow=bool(flags&8),pll_locked=bool(flags&16),
                spi_selected=bool(flags&32),memory_valid=bool(flags&64),bus_fault=bool(flags&128),
                address=f'0x{int.from_bytes(packet[3:7],"big"):08x}',
                address_kind='rom_first_word' if flags&2 and packet[7:9]==b'\x00\x00' else 'bus_address',
                lcd_writes=int.from_bytes(packet[7:9],'big'))),flush=True)
if not received:
    raise SystemExit('No N3 packets received')
