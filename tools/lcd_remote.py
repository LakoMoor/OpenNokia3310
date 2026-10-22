"""Send a PCD8544 diagnostic frame to nokia_io_top over USB-UART (pyserial)."""
import argparse
from pathlib import Path
import time


def packets(dc, data):
    return b"".join(bytes((0xa5, dc, b)) for b in data)


if __name__ == "__main__":
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("port", help="e.g. COM5 or /dev/ttyUSB0")
    p.add_argument("--frame", type=Path, help="504 raw PCD8544 bytes (6 banks x 84 columns)")
    a=p.parse_args()
    if a.frame:
        frame=a.frame.read_bytes()
        if len(frame)!=504:
            p.error("frame must contain exactly 504 bytes")
    else:
        frame=bytes(255 if x in (0,83) else 1 if bank==0 else 128 if bank==5 else 0
                    for bank in range(6) for x in range(84))
    import serial
    with serial.Serial(a.port,115200,timeout=1) as port:
        time.sleep(0.2)
        port.write(packets(0,bytes((0x20,0x0c,0x80,0x40))))
        port.write(packets(1,frame))
        port.flush()
    print("Sent 84x48 diagnostic frame to HDMI and ST7735S")
