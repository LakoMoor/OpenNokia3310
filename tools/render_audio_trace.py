"""Render accepted original-ROM AUDIO-W register writes to mono PCM WAV."""
import argparse
import json
import re
import sys
import wave
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps/desktop"))
from pc_audio import Synth

WRITE = re.compile(r"AUDIO-W pc=[0-9a-f]+ addr=([0-9a-f]+) byte=([0-9a-f]+) cycle=(\d+)")


def render(trace, output, clock_hz, start, end, volume=10):
    if clock_hz <= 0 or start < 0 or end <= start or not 0 <= volume <= 10:
        raise ValueError("Invalid clock, cycle interval or output volume")
    regs = {}
    synth = Synth()
    previous = 0
    frames = 0
    events = 0
    active = 0
    def update():
        nonlocal active
        word = lambda a: (regs.get(a, 0) << 8) | regs.get(a+1, 0)
        body = b"".join(word(a).to_bytes(2, "big") for a in (0x100ae, 0x100b0, 0x100b6, 0x2001c))
        body += bytes((bool(regs.get(0x20015, 0) & 0x20), regs.get(0x2001e, 0), volume))
        synth.update(body)
        if (word(0x100b6) and (word(0x100ae) or word(0x100b0))) or (body[8] and body[9] and word(0x2001c)):
            active += 1
    output.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(output), "wb") as wav:
        wav.setnchannels(1); wav.setsampwidth(2); wav.setframerate(synth.rate)
        def emit(cycle):
            nonlocal frames
            target = max(0, min(cycle, end)-start)*synth.rate//clock_hz
            while frames < target:
                count = min(4096, target-frames)
                wav.writeframesraw(synth.render(count, now=synth.last_rx))
                frames += count
        with trace.open() as source:
            for line in source:
                match = WRITE.search(line)
                if not match:
                    continue
                address, byte = (int(match[i], 16) for i in (1, 2))
                cycle = int(match[3])
                if cycle < previous:
                    raise ValueError("Audio register events are not ordered")
                previous = cycle
                if cycle > end:
                    break
                emit(cycle)
                regs[address] = byte
                update()
                events += 1
        emit(end)
    return dict(frames=frames, sample_rate=synth.rate, register_writes=events,
                active_register_states=active, source=str(trace), output=str(output))


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("trace", type=Path)
    p.add_argument("output", type=Path)
    p.add_argument("--clock-hz", type=int, default=16875000)
    p.add_argument("--start", type=int, default=0)
    p.add_argument("--end", type=int, required=True)
    p.add_argument("--volume", type=int, choices=range(11), default=10)
    a = p.parse_args()
    print(json.dumps(render(a.trace, a.output, a.clock_hz, a.start, a.end, a.volume)))
