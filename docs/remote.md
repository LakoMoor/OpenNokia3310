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

#### Original-ROM boot audio observation

The local `audio-register-boot` run completed 400,000,000 cycles using the
v6.39 PPM-W image, virtual network, 16,875,000 Hz and eight memory wait cycles.
Its 30 accepted audio-region byte writes contain no nonzero DSP frequency,
DSP amplitude, buzzer divider or buzzer volume. PUP control was only 0x00 or
0x08, so bit 0x20 (buzzer enable) was not asserted. The observed screen during
this no-key run was the stock Time prompt. This establishes that boot alone
did not request sound, not that ringtone playback works or fails.

A separate `audio-keypad-gain` run uses the existing virtual-call key script
and the updated RTL. Its outcome is pending; the key-script manifest must be
checked at completion before interpreting its events.

Use `python tools/render_audio_trace.py TRACE OUTPUT.wav --end CYCLE` to
render AUDIO-W events to 24kHz mono PCM. `--start`, `--clock-hz` and `--volume`
select the interval and host gain. This reconstructs known oscillators only;
it is not captured hardware audio or a PCM speech decoder. Two tests verify
register timing, 1kHz pitch, square-wave levels, phone mute and interval checks.
The completed boot trace renders 568,888 silent samples, consistent with its
zero active sound-register states.

#### Completed keypad audio and restored hardware stream

The `audio-keypad-gain` simulation completed 640,000,000 cycles with matching
initial/final key-script hashes. It contains 164 sound-region byte writes,
including nonzero DSP tones, but no PUP divider/volume writes. Rendering cycles
400,000,000 through 640,000,000 produces 341,333 PCM samples. The earlier
400,000,000..470,000,000 segment has 10,184 nonzero samples and peak 2200.
This confirms simulated menu/key tone commands, not original ringtone playback.

The gain-adjusted non-network hardware image was routed with final clock maxima
35.17MHz system and 139.78MHz pixel (required 16.875MHz and 27MHz), SHA256
`7f18a70718dfedaff36b2f4ddf1b732dfcc9ffb759fc435fad7be7921d157f38`.
It was loaded into SRAM, with flash unchanged. Initially Studio received no
frames. After temporarily loading I/O diagnostics and restoring the phone image,
a raw read found 61 N4 headers, then `link_remote.py` received 13 LCD frames and
one silent audio state in three seconds. Studio subsequently displayed the phone's
Insert SIM card screen. The recovery mechanism is not established; this does not
prove reliable reconnects or SIM acceptance. The app now retries the idempotent
stream-enable command when LCD data is absent and labels its waiting state.
The controls regression confirms repeated stream enables preserve menu state
and do not reset the phone.

Studio Activity now offers Read SIM diagnostics on the current UART connection.
It selects the existing opcode-7 diagnostic address mode, waits 500ms before
interpreting queued statuses, logs command count/last instruction after boot,
and restores normal status reporting after three seconds or at disconnect.
Palette selection is preserved. Rust build and six existing tests pass; this
new button is not yet hardware-qualified. A separate three-second COM6 attempt
returned no N4 status packets, so no physical SIM command count was established.

#### Current ROM and SIM receive FIFO investigation

A fresh JTAG flash read returned exactly 2,097,152 bytes at offset 0x200000.
SHA256 `5cd18ff08b40f44c9dbe155bc09efbcea15b5037234fa9d54b3e43bac8fcc8a2`
matches the simulation ROM byte-for-byte, including EEPROM. SRAM restoration
succeeded afterwards. A SIM status sample then observed counts 123 and 124,
last instruction B2, with SDRAM ready and no reported memory error, overflow
or bus fault. A mirror capture showed the stock Time prompt. Three C presses
then produced Insert SIM card on the physical board.

The receive model had released the next UART byte only after the MCU read the
previous byte. A new Tang-clock regression fails on that behavior: queued UART
bytes must become visible at their paced arrival times even while the MCU is
not reading. The source now permits that buffering, prefetches the next FIFO
byte on a read, and preserves RX interrupt state when arrival coincides with
consumption of the previous last byte. SIM, SIM pace and MAD2 regressions pass.
An original-ROM run and FPGA build are pending. This is a timing-model correction;
it is not yet evidence that physical Insert SIM card has been fixed.

The Tang-clock SIM pace regression additionally schedules consumption of the
last visible byte on the exact next byte-arrival edge. It verifies that one
byte remains visible, RX interrupt/FIQ stays asserted, and the next ATR byte
is readable. This collision check passes along with paced backlog and
back-to-back FIFO reads.

A separate full-core `core_sim` test now runs ARM instructions that activate
SIMI, poll until four ATR bytes accumulate, read them through the CPU/MMIO bus,
and store the expected 3B 60 00 00 values to external RAM with wait states.
It passes at the Tang device clock. The general ARM/MAD2 smoke test also passes.
Neither test establishes that the original firmware accepts the SIM.

During the pending original-ROM UART-buffer regression, the first 116 completed
SIM responses exactly matched the prior hardware-power simulation in instruction,
file, status, length, offset and P1/P2/P3. This is a prefix comparison only;
completion, post-Time UI and physical acceptance remain pending.
