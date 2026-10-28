# USB remote protocol v2 (N4)

FT2232-compatible USB debugger, vendor 0403 / product 6010, UART channel B,
115200 baud, 8 data bits, no parity, one stop bit. Channel A is JTAG.

## Host commands

All commands are three bytes: `A5 opcode value`. Payload A5 is valid; it must
not restart the packet parser. Malformed stop bits reset command framing.

| Opcode | Value |
| --- | --- |
| 00 / 01 | Diagnostic LCD command/data; ignored by full phone integration |
| 02 | Nokia key mask bits 7:0 |
| 03 | Nokia key mask bits 15:8 |
| 04 | Nokia key mask bit 16 (power) |
| 05 | bit 0: LCD/audio stream enabled; bit 1: toggle system menu; bit 2: restart FPGA/phone |
| 06 | Volume 0–10, clamped |
| 07 | bit 0: grayscale palette (0 = green) |
| 08 | 01: explicit one-second 1kHz audio output test |

Key bits 0–9: digits, 10: star, 11: hash, 12: Menu/OK, 13: C/Back,
14: up, 15: down, 16: power. Transmit the complete key mask every 100ms while
connected. The FPGA releases stale keys after one second without input.

## FPGA packets

`4E 34 type length_hi length_lo payload... xor`

Length is big-endian and excludes framing. The final byte is XOR of all prior
bytes in the frame, including the magic and length. Maximum accepted payload
is 1024 bytes. Consumers recover from noise, corrupt checksums and oversized
lengths. Legacy N3 ten-byte status frames remain supported by host software.

| Type | Length | Payload |
| --- | --- | --- |
| 01 | 504 | Six vertical banks of 84 bytes, bit 0 at the top of each bank; current LCD or system overlay |
| 02 | 10 | Flags, CPU/boot address (BE32), LCD writes (BE16), volume, display flags, settings format version (1) |
| 03 | 11 | DSP f1 (BE16 quarter-Hz), f2 (same), amplitude (BE16), buzzer divider (BE16), buzzer enabled, buzzer volume register, system volume |

Type 01 is a captured snapshot at approximately four frames per second;
transmission takes ~45ms. Display blank, all-on and inverse modes are reflected.
Type 02 runs without an active stream as well. Flags: SDRAM ready, ROM loaded,
memory error, LCD FIFO overflow, PLL lock, SPI selected, memory valid, sticky
bus fault (bits 0 through 7). With ROM loaded and zero LCD writes, the address
field holds the first SPI ROM word to aid boot diagnosis.
Display flags: bit 0 = system menu open, bit 1 = gray LCD (zero = green LCD).
The selected palette applies to HDMI, ST7735S, Android and the desktop remote.
Hosts also accept older seven-byte N4 status payloads without settings.

Type 03 reports changes in device audio state; it is not captured PCM. DSP
frequencies are encoded in quarter-Hz units. Buzzer frequency is 13MHz/divider.
Android synthesizes the reported oscillators and silences them if data stops.
The explicit output test is marked by a 1000Hz / amplitude=1 tone state.

Legacy N3: `4E 33 flags address_BE32 lcd_count_BE16 xor`.
`nokia_io_top` uses a different N3 payload interpretation; use `read_pad.py`
only with that diagnostic target.

### Ringtone debugging

Set `NOKIA_AUDIO_TRACE=1` when running `tools/trace_firmware.py` to log
accepted writes to DSP tone registers and the PUP buzzer region as `AUDIO-W`.
Each record includes PC, byte address, byte value and cycle. This is opt-in
and does not change the FPGA design. A one-million-cycle compile/run smoke
check completed; it does not demonstrate a ringtone.

Rust Studio Activity logs decoded tone frequencies and host output startup.
Its buzzer oscillator uses a square wave and applies the phone volume byte
(payload byte 9) as well as the host volume (byte 10). A synthetic 1kHz test
checks pitch, waveform polarity, zero phone volume and disable. Actual
original-ROM ringtone audibility remains unverified. The register interpretation
is consistent with [the reference buzzer model](https://github.com/bialasik/nokia-3310-emulator/blob/main/crates/emucore/src/buzzer.rs).

The FPGA sound mixer now applies PUP volume to its buzzer path too. It uses
`volume_byte << 4` amplitude (0..4080), keeping a small fixed-point gain
approximation without another multiplier. The sound RTL regression passes
zero, half and full PUP gain and disabled-generator checks. This source change
has not yet been routed or loaded on Tang; the previous hardware image is
unchanged. Android debug assembly succeeded after the companion-side change;
Python audio tests pass 4/4 and Rust tests pass 6/6.
