# Verification status — October 22, 2026

## Real hardware

- Tang Nano 20K, GW2A(R)-18, JTAG ID 0x81b.
- HDMI captured directly using the USB3.0 UHD DirectShow capture device.
- Original v5.79 and v6.39 W firmware reached their original menus on the FPGA.
- v6.39: Phonebook, Settings, Language, English and Russian selection confirmed.
  See the actual captures in [img/](img/). The Russian confirmation reads “Есть!”.
- The full v6.39 image was written at SPI offset 0x200000 with read-back verification.
  A separate complete read-back matched SHA256
  `5cd18ff08b40f44c9dbe155bc09efbcea15b5037234fa9d54b3e43bac8fcc8a2`.
- Original SPI contents and the previous v5.79 ROM are backed up locally and
  excluded from this repository. FPGA configurations have been loaded into SRAM.
- ST7735S is physically connected, but its displayed output remains unverified.

Repeated boots are not yet reliable. A previous image sometimes ran without
producing LCD writes. A subsequent instrumented build booted again, but the
root cause is not established. There is no basis to call this stable yet.
v5.79 also eventually displayed a virtual SIM error.

## Controller

The first driver passed basic simulation but did not control the physical phone.
Comparison with Open Pocket GBC exposed missing select setup and inter-byte
recovery delays. The driver now waits 100 us after select and 192 us between
bytes at 125 kHz, matching the conservative timing of the reference adapter.

The real pad now responds with ID **0x41** and a valid 0x5A response header.
UART captures from the separate I/O qualification target confirmed:

| Raw active-low bytes | Mapped Nokia key |
| --- | --- |
| EF FF | Up (0x4000) |
| BF FF | Down (0x8000) |
| 7F FF | 4 (0x0010) |
| DF FF | 6 (0x0040) |
| FF DF | Menu (0x1000) |
| FF BF | C / Back (0x2000) |
| FF FF | All released |

Complete phone menu operation with the revised driver is still being checked.
Run `python tools/read_pad.py COM6 --seconds 10` only with `nokia_io_top`.
It decodes controller ID, connection, raw bytes and mapped keys. Full phone
telemetry uses a different field interpretation (`tools/read_status.py`).

## FPGA integration

`nokia_top` integrates ARM, MAD2, NOR, DSP transport service, virtual SIM, SDRAM,
SPI boot DMA, LCD CDC FIFO, HDMI, ST7735S, DS2 and UART.
HDMI: 27 MHz pixel / 135 MHz serializer. ARM/SDRAM: 16.875 MHz.
The SDRAM init wait is 3500 cycles, refresh interval 125 cycles.

LUT4-only mapping avoids the failed wide-LUT placement at 93% utilization.
The last completed instrumented full build passed timing: sys Fmax 41.27 MHz,
pixel Fmax 141.32 MHz, bitstream SHA256
`3bafc5ea3cd041518227daca844141a266f219f71e650dee2d951473374b954b`.
The revised DS2 full integration build is in progress; this hash identifies
the earlier instrumented build, not that pending build.

## RTL verification

The complete current suite passed **15/15** after the DS2 changes.
Expanded keypad, DS2 and flash boot regressions pass. Tests verify every
key/row and both pad mappings, DS2 command ordering, inter-byte recovery,
physical response to Nokia matrix conversion, invalid-controller release,
the first ROM word, DMA backpressure, LCD/video data, SIM protocol and FIQ return.

The local ARM fix prevents loss of banked LR when an FIQ coincides with completion
of a memory instruction. See [LOCAL_CHANGES.md](../third_party/arm7tdmi-sv/LOCAL_CHANGES.md).

Original v5.79 also reached standby and the main menu in a 650-million-cycle
RTL simulation, with 27,404 LCD writes. Simulation frames are not HDMI captures.

## Limits

- NOR/settings changes currently live only in SDRAM and are lost on reset.
- Synthetic SIM; no real subscriber Ki.
- Partial DSP ROM6 device service, not a full C54x implementation.
- No GSM RF hardware, network registration, cellular calls or mobile SMS.
- Games and sustained operation remain unverified.

[Earlier Russian development notes](STATUS.ru.md) are retained for context;
this document is the current English status.
