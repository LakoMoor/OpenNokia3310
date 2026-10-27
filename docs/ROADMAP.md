# Original Nokia compatibility goal

The target is original Nokia 3310 firmware running on Tang Nano 20K, with a
virtual cellular environment inside FPGA. Real RF service is outside this
target. A recreated menu is not a substitute for original firmware behavior.

| Area | Acceptance evidence | Current state |
| --- | --- | --- |
| Boot | Full ROM CRC after SPI→SDRAM; repeated cold/warm boots; original standby | Blocked by corrupted ROM transfer; registered SPI CS fix awaits hardware |
| Original UI | Original Phonebook, Settings, languages, clock and games exercised | Older hardware build reached menus; current stalled-memory simulation responds in Messages/Write messages; board regression under diagnosis |
| Input | DS2, Windows and Android press/hold/release in original menus | DS2 previously confirmed; N4 system menu checked on Tang |
| Display | Matching original 84×48 framebuffer on HDMI, ST7735S and apps | Framebuffer logic passes; physical ST7735 appearance not yet confirmed |
| Audio | Original keypad, alerts, ringtone and game tones; HDMI and app playback | Register synthesis and PC playback tests pass; original ringtone not verified |
| SIM | ATR/APDU, phonebook/SMS records, PIN lifecycle and no SIM errors | File/record and CHV/PIN lifecycle tests pass; original phone settings integration incomplete |
| Virtual network | Original firmware registers, displays operator/signal, handles simulated outgoing/incoming calls/SMS | Not implemented; requires DCT3 DSP/baseband message modeling |
| Persistence | Contacts, language/settings and virtual messages survive power cycle | NOR writes are SDRAM-only |
| Installation | One action validates FPGA+ROM, backs up 8 MiB, verifies both writes, starts FPGA | Windows backend and seven tests implemented; full hardware flow pending |
| Android | OTG installation/control and screen/audio with physical Android device | Control APK built; physical OTG and installation not yet verified/implemented |

## Reference review — October 26, 2026

Fetched Open Pocket GBC main revision
`865574cf0c5d9c5dfb2b850a8019dd04cab8979f`.
Compared with previously studied `46fea7708ca76c988ad74b646d18184403c031b1`:
new Web Serial remote, serialized writes and disconnect cleanup, updated native
apps, release automation, printer/gallery support and firmware changes.
Its `apps/studio/main.js` includes staged JTAG installation and a serial updater
fallback. Nokia cannot use the GBC updater unchanged: its protocol and flash
layout must be implemented explicitly. Likewise, GBC games and Nokia ROM are
different payloads despite sharing the physical 0x200000 flash region.

The immediate priority is verified ROM loading, then original firmware boot.
Virtual RF/DSP behavior must be driven by observed original-firmware messages;
no generated UI should be presented as proof of cellular emulation.

## Virtual-cell transport work

`rtl/nokia/virtual_cell.sv` builds device-side SCH and BCCH/SI3 MDI
RECEIVED_BLOCK records. Cell identity, PLMN, LAC, ARFCN, BSIC and frame number
are explicit inputs, latched per record. A ready/valid byte interface preserves
the packet under stalls. Tests cover envelope lengths, identity, backpressure
and reset. The module is deliberately not yet wired into `dsp_service`:
registration, calls and SMS are not implemented by this building block.

SI3 field order and pseudo-length follow
[ETSI TS 144 018, section 9.1.35](https://www.etsi.org/deliver/etsi_ts/144000_144099/144018/10.06.00_60/ts_144018v100600p.pdf).
The DCT3 envelope is studied from `src/mad2/mdi_gsm.c` in the pinned Nokia
reference emulator. Its firmware addresses and receive-state analysis describe
v5.79 and must not be assumed valid for the active v6.39 ROM. Before integration,
trace firmware-owned queue initialization and radio requests for each ROM,
then qualify ring ownership, queue wrapping and FIQ delivery. Continue with
SI2/SI4, channel assignment, MM registration and CC/SMS transactions; merely
transmitting SI3 does not prove successful camping or subscriber service.

`mdi_injector.sv` now buffers complete records, rejects malformed lengths,
waits for an initialized empty receive ring and commits only the DSP producer
halfword. It preserves MCU ownership of the consumer and raises FIQ after
commit. Directed tests include arbitrary memory wait states, e3→80 wrapping,
odd-length padding, malformed records and reset. An integration test connects
the SI3 generator through this injector to a stalled shared-memory model and
checks the resulting MDI header, PLMN/LAC/identity, padding and producer cursor.
Before use in `nokia_core`, it still needs a DSP-master arbiter and observed
firmware radio-request triggers; it is not active in the phone build yet.

An experimental `dsp_network` wrapper now arbitrates existing DSP service
transactions and packet injection, blocking new doorbell events while a
network record owns the bus. The core's `VIRTUAL_NETWORK` parameter enables it
for simulation; the physical top remains disabled until qualified. A v6.39
trace actually emits opcode 56 at cycle 110,942,900, so the prototype uses
that device request (rather than writing firmware FSM state) to send SCH,
then periodic SI3. This is a search-response experiment, not registration.
`trace_firmware.py --virtual-network` enables the experiment; baseline runs
remain off. The wrapper test verifies existing local DSP commands and actual
search→SCH→SI3 ring delivery with memory stalls and producer/consumer checks.


Virtual-network trace qualification now distinguishes packet commits from MCU
consumer-cursor movement. `trace_firmware.cpp` logs producer/consumer positions
at each virtual packet and later consumer changes. A consumer change is queue
activity, not proof of RR acceptance or registration. Correlate it with actual
v6.39 radio requests, decoded protocol responses and original UI before advancing
network acceptance. Trace runs already executing use their previously compiled
harness; the new counters apply only after recompilation.


For a bounded protocol summary of a single isolated run:

```powershell
python tools/trace_protocol.py build/trace-runs/RUN/trace.log --output build/protocol-report.json
```

This reports captured MCU-to-DSP requests, not complete radio transactions.
Truncated payloads and I-frame continuations must be inspected before decoding
L3 content. RR acknowledgements alone do not qualify call/SMS service.
