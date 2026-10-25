"""N3 legacy telemetry / N4 live LCD and device audio framing."""
import time


class Parser:
    def __init__(self):
        self.buffer = bytearray()

    def feed(self, data):
        self.buffer.extend(data)
        packets = []
        while len(self.buffer) >= 2:
            if self.buffer[:2] not in (b'N3', b'N4'):
                del self.buffer[0]
                continue
            legacy = self.buffer[1] == 0x33
            if len(self.buffer) < (10 if legacy else 5):
                break
            size = 10 if legacy else 6 + int.from_bytes(self.buffer[3:5], 'big')
            if size > 1030:
                del self.buffer[0]
                continue
            if len(self.buffer) < size:
                break
            packet = self.buffer[:size]
            check = 0
            for byte in packet:
                check ^= byte
            if check:
                del self.buffer[0]
                continue
            del self.buffer[:size]
            packets.append((0 if legacy else packet[2], bytes(packet[2:9] if legacy else packet[5:-1])))
        return packets


def command(opcode, value):
    return bytes((0xa5, opcode, value & 255))


def keys(mask):
    return command(2, mask) + command(3, mask >> 8) + command(4, mask >> 16)


def status(payload):
    flags = payload[0]
    result = dict(sdram_ready=bool(flags & 1), rom_done=bool(flags & 2),
                memory_error=bool(flags & 4), lcd_overflow=bool(flags & 8),
                pll_locked=bool(flags & 16), spi_selected=bool(flags & 32),
                memory_valid=bool(flags & 64), bus_fault=bool(flags & 128),
                address=f'0x{int.from_bytes(payload[1:5], "big"):08x}',
                lcd_writes=int.from_bytes(payload[5:7], 'big'))
    if len(payload) >= 10:
        result.update(volume=payload[7], menu_open=bool(payload[8]&1), gray=bool(payload[8]&2), version=payload[9])
    return result
