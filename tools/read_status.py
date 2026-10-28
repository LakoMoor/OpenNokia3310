"""Read legacy N3 or current N4 diagnostics from a Tang running nokia_top."""
import argparse
import json
import time
import serial
from nokia_protocol import Parser, status

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('port')
p.add_argument('--seconds', type=float, default=5)
a = p.parse_args()
parser = Parser()
previous = None
received = 0
started = time.monotonic()
last_received = None
with serial.Serial(a.port, 115200, timeout=.1,write_timeout=1) as port:
    port.reset_input_buffer()
    end = time.monotonic() + a.seconds
    while time.monotonic() < end:
        for kind, body in parser.feed(port.read(1024)):
            if kind in (0, 2) and len(body) >= 7:
                received += 1
                last_received = time.monotonic()
                if body != previous:
                    previous = body
                    print(json.dumps(status(body)), flush=True)
if not received:
    raise SystemExit('No N3/N4 status packets received')
print(json.dumps(dict(status_packets=received, observed_seconds=round(time.monotonic()-started, 3),
                      seconds_since_last_packet=round(time.monotonic()-last_received, 3))), flush=True)
