"""Press a Nokia key through the board's existing USB-UART control link."""
import argparse
import time
import serial

KEYS={str(i):i for i in range(10)}
KEYS.update(star=10,hash=11,menu=12,c=13,up=14,down=15,power=16)

def send(port,mask):
    port.write(bytes((0xa5,2,mask&255,0xa5,3,(mask>>8)&255,0xa5,4,(mask>>16)&1)))
    port.flush()

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('port')
    p.add_argument('key',choices=KEYS)
    p.add_argument('--hold',type=float,default=0.2)
    a=p.parse_args()
    if not 0<a.hold<=10: p.error('--hold must be in (0, 10] seconds')
    with serial.Serial(a.port,115200,timeout=1,write_timeout=1) as port:
        try:
            end=time.monotonic()+a.hold
            while time.monotonic()<end:
                send(port,1<<KEYS[a.key])
                time.sleep(min(0.1,max(0,end-time.monotonic())))
        finally:
            send(port,0)
    print('Released',a.key)
