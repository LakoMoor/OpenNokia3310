# Verification status

## October 26, 2026 — original boot investigation

- Added the missing experimental blind-band-search response: DSP opcode `55`
  now requests an MDI `8B` ALL_RSSI report containing the fixture's ARFCN 586
  at level D0 and 39 empty carrier slots. The generator emits 162 payload bytes.
  The injector now buffers up to 196 total bytes (98 words, below the 100-word
  ring capacity) instead of truncating at 64 bytes. Directed tests cover all
  164 bytes through stalled queue writes and wrap, preserved consumer ownership,
  oversized-frame rejection, and actual `55` request-to-response integration.
  All 23 RTL cases pass. The current original-ROM experiment predates this
  change; firmware acceptance of ALL_RSSI is still unverified. Hardware remains
  on its qualified pre-CHV image with virtual networking disabled.

- Review of the reference DSP ROM6 dispatcher exposed an incorrect prototype
  `89` format: channel confirmation is a one-byte correlation token, not the
  ten-byte radio prefix used by RECEIVED_BLOCK. The wrapper now snapshots the
  token from request payload byte 6 (or traffic-logch parity), rejects truncated
  requests for confirmation, and sends a one-byte MDI `89` body. Tests cover
  BCCH and traffic token correlation, odd-byte padding, queue ownership and
  subsequent periodic SI delivery. All 23 RTL cases pass. Original-ROM testing
  with this corrected reply is running; no registration is claimed.
- The earlier long-confirm experiment completed 400M clocks with 17,846 LCD
  writes, 70 virtual packet commits and 145 receive-consumer changes. Its new
  opcode `55` is blind band search according to the reference dispatcher; it
  cannot be treated as evidence of successful channel setup. Its trace and RAM
  snapshot are retained locally for comparison with the corrected reply.

- The new channel-confirm v6.39 experiment shows actual MCU receive-consumer
  movement after virtual packet commits. It also emits a new DSP opcode `55`/
  sub `03` at cycle 160,633,848, whereas the previous 400M-cycle SI-only run
  stopped its DSP requests at opcode `02`. This is evidence of changed firmware
  behavior after the response, not proof of camping, registration or a call.
  The experiment is still running; the meaning of opcode `55` needs tracing.
- PIN format validation now uses local adjacent-padding checks instead of a
  prefix-padding chain. A directed equivalence check covers all 65,536 patterns
  made from digits, FF padding and two invalid byte classes; PIN/PUK and SIMI
  tests pass, including eight-digit PIN replacement and digits after padding.
  Full-top resource impact is being synthesized and is not yet established.

- In the SI3/SI2/SI4 v6.39 experiment, firmware emits DSP opcode `02`/sub `04`
  at cycle 111,049,877 immediately after search opcode `56`. The experimental
  wrapper now answers observed opcode `02` with an MDI `89` channel-change
  confirmation for the configured fixture's BCCH/ARFCN, without editing MCU RAM.
  Tests verify its ten-byte envelope, status, queue commit/FIQ and preservation
  of the periodic SI schedule. The full 23-case RTL suite passes. Firmware
  acceptance of this response is not yet established; it is disabled on Tang.
  This fixed-cell prototype does not yet decode arbitrary channel parameters
  from the request payload and must not be treated as a complete radio model.

- The optimized full CHV build still fails legal placement at 18,947 LUTs;
  the 163-LUT reduction is insufficient. The installed qualified image is unchanged.
- Experimental virtual-cell broadcasts now cycle SI3, SI2 and SI4 after SCH.
  Directed tests verify SI2 neighbour/NCC/RACH fields, SI4 identity and its
  12-octet mandatory pseudo-length, matching LAI and selection/RACH fields,
  stalled output stability and SI3 return after a full cycle. Queue integration
  verifies all four records and interrupt counts. These tests pass; original-ROM
  response is under investigation, with no registration/call/SMS claim.

- MAD2 shadow-register storage now uses one shared read port and one combined
  initialization/CPU write port; the independently consumed MBUS IRQ bit has a
  dedicated mirror. The full 23-case RTL regression passes, including shadow
  reset values, readback across 32 distinct addresses and special read masks.
  Full-top synthesis reduces packed LUT usage from 19,110 to 18,947 (163 LUTs),
  retaining all registers and the new CHV model. Placement is being evaluated;
  this is not a qualified replacement for the installed pre-CHV image.

- Windows [preview 0.2.3](https://github.com/LakoMoor/OpenNokia3310/releases/tag/v0.2.3-preview)
  now ships the combined installer, saved paths, programmer watchdog and the
  explicitly hash-checked qualified pre-CHV FPGA image. ZIP integrity, FPGA
  manifest/hash and absence of ROM files were checked. Final EXE startup passed;
  local audio smoke test opened its stream and wrote 23,520 PCM frames.
  ZIP SHA256 `abefac88bd4697e09677a6bf3cf59e9517b7e7fa01ad57dd1b952ced552eec88`.
  Full combined hardware installation and visual GUI review remain unverified.

- Desktop installer now terminates a stalled programmer after 30 seconds for
  board detection or 10 minutes for backup/programming. It reports failure and
  does not continue the installation. Nine backend tests pass, including a
  real silent child process killed by the watchdog and nonzero-exit log capture.
  Serial diagnostic tools also bound writes to one second after USB loss.
  These changes do not resolve the physical USB disappearance.
- The full installer success message now distinguishes verified flash writes
  and SRAM loading from actual phone boot and subsequent power-cycle testing.

- Tang became available again. Direct programmer read-back of the 2 MiB ROM
  matches SHA256 `5cd18ff08b40f44c9dbe155bc09efbcea15b5037234fa9d54b3e43bac8fcc8a2`.
- Registered-CS ROM probe initially returned all FF, but after the programmer
  initialized/read flash, the same FPGA probe passed full CRC32 `539dcc62` and
  all sampled entry instructions. Initial flash state/wakeup remains a separate
  issue to qualify; registered CS is not yet proof of reliable cold boot.
- The complete registered-CS pre-CHV bitstream then ran original v6.39 on real
  Tang. LCD writes progressed beyond 3,000; C/C/Menu opened the original
  **Phonebook**. The image below comes from actual Tang N4 LCD bytes, not the
  simulator and not an HDMI capture. HDMI/ST7735 appearance still needs checking.
  This successful bitstream does not contain the newer CHV or virtual-network
  changes that have not yet fitted/been qualified in the full device.

- The same qualified bitstream was written to configuration flash with programmer
  verification, after saving a 2 MiB configuration backup. The user then
  disconnected/reconnected USB power. Without a subsequent JTAG load, UART
  confirmed ROM completion and 3,188 original-firmware LCD writes, with no
  memory errors, FIFO overflow or bus fault. This proves one power-cycle boot;
  repeated cold-start reliability remains to be qualified. Both USB interfaces
  had disappeared before reconnecting; a stalled JTAG reset did not prove boot.
  A subsequent menu/capture attempt again lost both USB interfaces, so menu
  response after this particular cold start was not captured. USB stability
  remains unresolved; the successful SRAM Phonebook capture is separate evidence.
  Installed bitstream SHA256:
  `685910747c1699abae97c5ef5ccfe7359f5f4da49178371f2d21956ac5fdf073`.

![Original Phonebook restored — actual Tang USB LCD](img/hardware-phonebook-restored.png)

- The registered-CS full phone build now completes synthesis, placement,
  routing and packing. Post-route Fmax: pixel 141.46 MHz / system 32.80 MHz,
  passing 27 MHz / 16.875 MHz. This build predates the new CHV integration;
  the ROM probe and original phone boot have now passed on real Tang.
- Virtual SIM CHV1/CHV2 now implements verification, change, enable/disable,
  unblock, attempt counters and access protection. Unit and SIMI/APDU tests
  pass, including retained retry counts across card reset and protected IMSI
  reads after session reset. See [test credentials and limits](virtual-sim.md).
- The extended 22-case RTL regression passes after CHV integration.
- Initial CHV full synthesis reached 93% LUT4 and failed legal placement.
  Sequential CHV payload reads restore RAM inference and reduce synthesis
  usage to 19,013 / 20,736 LUT4 (91%), but this also fails legal placement.
  Further CHV storage/logic optimization is in progress; no new CHV bitstream
  is qualified for the board yet.
- The optional DSP network wrapper passes existing local-command transport and
  observed opcode-56→SCH→SI3 delivery tests. It is enabled only in an explicit
  original-ROM simulation experiment; the hardware top remains off pending
  firmware response analysis. Virtual registration/calls/SMS remain incomplete.
- In the actual v6.39 ROM experiment, opcode 56 causes the first virtual-cell
  record at cycle 110,943,074. Subsequent SI3 records are delivered while the
  firmware continues executing and updating LCD (3,752 writes by 250M cycles).
  This confirms transport integration, not a registered serving cell.
- Continuing original v6.39 simulation with eight-cycle external-memory stalls
  and scripted keypad input reached the original **Messages** menu and
  **Write messages** submenu. Captures below are rendered from simulated LCD
  RAM, not HDMI hardware. This verifies menu response in this model; it does
  not verify SMS transmission or the physical board's corrected ROM load.

![Original Messages menu — RTL simulation](img/simulation-messages.png)

![Original Write messages submenu — RTL simulation](img/simulation-write-message.png)

- A standalone address-dependent write/read test of all 8 MiB SDRAM passed on
  real Tang with zero errors. A separate SPI→SDRAM ROM CRC test failed: expected
  `539dcc62`; different builds produced `6b29a6b9` and `a1e799fa`.
- Direct SDRAM probes matched ROM word 0 but read `ffffffff` at entry 0x200040
  and subsequent instructions. This establishes corrupted loading before CPU
  execution; a correct SPI first word is insufficient boot evidence.
- The SPI chip-select output was combinatorially decoded from multiple FSM
  states. It is now registered and held continuously across all word/DMA
  boundaries. The extended flash test passes. A corrected ROM probe bitstream
  builds and subsequently passed full ROM CRC on Tang after programmer flash
  initialization. The earlier failure is retained here as investigation history.
- The diagnostic build now exposes actual bus address and selectable instruction
  PC instead of replacing zero-LCD telemetry with the first ROM word.
- Original ROM simulation with eight-cycle memory stalls at the board's actual
  16.875 MHz model clock reaches its first LCD write at cycle 23,498,920 and
  completes 200 million cycles with 3,176 LCD writes. This is not a hardware boot.
- Full-system one-action Windows installation passes seven backend tests.
  FPGA and ROM preparation precede backup/writes; ROM failure blocks FPGA write.
- Extended SPI stream regression passes 512 nonuniform ROM words, 0–96-cycle
  DMA backpressure and reset/reload while requiring one continuous CS assertion.
  All 18 existing RTL regressions pass with the registered-CS change.
- Installer paths now persist locally between application launches. A separate
  preferences test verifies round-trip paths and malformed-file recovery.
- A standalone virtual-cell MDI SCH/SI3 record builder now passes directed
  envelope, identity, ready/valid backpressure and reset tests. It is not yet
  sufficient to establish network registration; later integration is described
  above. No virtual registration, calls or SMS are claimed from this test.
- MDI record injection and generator-to-ring integration tests now pass:
  nonempty-ring protection, preserved MCU consumer, bus stalls, e3→80 wrap,
  odd-byte padding, producer commit before FIQ, invalid lengths and reset.
  It is now arbitrated by the optional DSP network wrapper; hardware remains
  disabled while actual firmware registration is investigated.
- See [compatibility goal and reference review](ROADMAP.md) for the remaining
  original-phone and virtual-network acceptance criteria.

## October 25, 2026 — companion apps, LCD palettes and audio

- Re-studied Open Pocket GBC revision `46fea7708ca76c988ad74b646d18184403c031b1`,
  including its Android FTDI channel-B transport and FPGA menu/audio interfaces.
- Android USB-C OTG app: release APK builds; three protocol tests pass. The APK
  installs and launches in an Android 34 emulator. A physical Android OTG session
  remains unverified. Native Android dialer/SMS intents use the Android modem;
  independent FPGA cellular calls still require additional hardware and models.
- Desktop Python remote: source and transport implemented; Python compilation
  passes. A portable Windows build now includes openFPGALoader and its DLLs,
  plus SRAM/flash/ROM installation and mandatory full backup before flash writes.
  Five flasher tests pass; the packaged EXE constructs both UI pages and its
  LCD image without errors. The bundled programmer detects the physical Tang
  without a system OSS CAD Suite installation. Visual window inspection is
  unavailable because the computer-use runtime failed to initialize.
  The same flash-manager backend successfully loads the bundled FPGA image
  into real Tang SRAM using only the bundled programmer/DLLs.
- Desktop PC audio now reproduces N4 device tone state on the default Windows
  output. Three PCM tests verify 1000 Hz pitch, buzzer conversion, mute and
  USB-timeout silence. A live output smoke test opens the Windows stream and
  supplies over 21,000 PCM frames. End-to-end playback from the user's Tang
  still needs user confirmation: the old application currently owns COM6.
- The complete 18-case RTL suite passes. Follow-up tests pass for menu bitmap
  capture, synchronized N4 volume/palette state, and green/gray switching on
  HDMI and all 16,384 ST7735 framebuffer pixels. This verifies framebuffer logic,
  not the physical panel's appearance.
- Python decodes the actual RTL-generated UART stream identically at seven
  chunk sizes, including checksum/oversize recovery and 17-key encoding.
- SIM fixture now advertises only implemented services and marks empty SMS
  records correctly. Extended tests cover record updates, relative selection,
  bounds, 256-byte transfers and power cycling. A one-billion-cycle original
  v6.39 trace completes; this alone does not establish complete SIM/GSM support.
- Buzzer and DSP tone registers drive the new audio path; RTL tests verify
  register byte lanes, oscillators, 48 kHz clocking, mute and explicit output test.
  Physical HDMI/speaker audio has not yet been captured.
- The HDMI capture card was not enumerated in this session. New hardware
  HDMI/audio capture qualification is pending its connection.
- Full synthesis, placement, routing and bitstream packing now pass. LUT4 use:
  18,481 / 20,736 (89%). Post-route maximum clocks: pixel 138.33 MHz against
  27 MHz required; system 37.70 MHz against 16.875 MHz required.
- The new bitstream was loaded into actual Tang SRAM. USB delivered 12 LCD
  snapshots in three seconds. Down/Down/OK selected Gray LCD; status reflected
  the selection and all 504 captured menu bytes matched the expected bitmap,
  digits and highlighted row. Green LCD was restored and confirmed in status.
  The explicit sound test reported 1000 Hz followed by silence; this proves
  device state transport, not audible HDMI/speaker output.
- FPGA bitstream SHA256:
  `b8531bf600204770d9c977897a9e05203cdb6fb4c74b6441346606cd3c39a632`.
- A complete 8 MiB SPI backup was saved locally. Its ROM region differs from
  the earlier Nokia image: another project had replaced the ROM region.
  Nokia v6.39 W was restored at 0x200000 with write/read-back verification.
  The FPGA test uses SRAM and does not replace persistent FPGA configuration.
- Original-phone boot is still failing in this new hardware build: after SRAM
  loading and a second full reset with Power held, ROM loading completes and
  no memory/bus fault is reported, but LCD writes remain zero. Working system
  menu/USB streaming does not establish a working original Nokia UI. Do not
  treat this preview as a stable phone implementation.

## October 22, 2026 — previously verified hardware build

## Real hardware

- Tang Nano 20K, GW2A(R)-18, JTAG ID 0x81b.
- HDMI captured directly using the USB3.0 UHD DirectShow capture device.
- Original v5.79 and v6.39 W firmware reached their original menus on the FPGA.
- v6.39: Phonebook, Settings, Language, English and Russian selection confirmed.
  See the actual captures in [img/](img/). The Russian confirmation reads “Есть!”.
- The full v6.39 image was written at SPI offset 0x200000 with read-back verification.
  A separate complete read-back matched SHA256
  `5cd18ff08b40f44c9dbe155bc09efbcea15b5037234fa9d54b3e43bac8fcc8a2`.
- Original SPI contents, the prior FPGA configuration and the previous v5.79
  ROM are backed up locally and excluded from this repository.
- The final FPGA configuration is now installed persistently in SPI flash,
  starting at 0x000000; the programmed sector range ends at 0x0E0000. The ROM
  starts separately at 0x200000. openFPGALoader write/read-back verification
  passed. Automatic reconfiguration from flash reached the original phone UI.
  A physical unplug/replug cold power cycle has not been performed.
- ST7735S is physically connected, but its displayed output remains unverified.

Repeated boots are not yet reliable. A previous image sometimes ran without
producing LCD writes. A subsequent instrumented build booted again, but the
root cause is not established. There is no basis to call this stable yet.
v5.79 also eventually displayed a virtual SIM error.

The home screen containing numeric fields and X placeholders was identified
as the firmware's **Net Monitor** engineering display (page 02). This is enabled
by the donor EEPROM. Selecting test 00 in Menu → Net monitor removed it on the
physical board; HDMI then showed ordinary standby. This does not fix GSM/SIM
model limitations, and the selection is lost on reset until settings persistence
is implemented.

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

The user confirmed full phone menu operation on the actual controller after
the revised full build was installed: Circle opens, Down scrolls and Cross
returns. HDMI captured the original Settings menu after flash boot.
Run `python tools/read_pad.py COM6 --seconds 10` only with `nokia_io_top`.
It decodes controller ID, connection, raw bytes and mapped keys. Full phone
telemetry uses a different field interpretation (`tools/read_status.py`).

## FPGA integration

`nokia_top` integrates ARM, MAD2, NOR, DSP transport service, virtual SIM, SDRAM,
SPI boot DMA, LCD CDC FIFO, HDMI, ST7735S, DS2 and UART.
HDMI: 27 MHz pixel / 135 MHz serializer. ARM/SDRAM: 16.875 MHz.
The SDRAM init wait is 3500 cycles, refresh interval 125 cycles.

LUT4-only mapping avoids the failed wide-LUT placement at 93% utilization.
The installed full build with revised DS2 timing passed synthesis, placement,
routing and timing: sys Fmax 40.59 MHz, pixel Fmax 149.88 MHz. Bitstream SHA256:
`4e434db30be2a36929940f8af2fa346441ed88730e049deb1ce021339a2e8710`.
The source `.fs` is 7,263,596 bytes of text; its parsed flash payload fits below
0x0E0000. The original configuration backup SHA256 is
`b3bfbfa25a69c59d3cf065a6963f555ddf3e461739d936c40ea5c15d9dd1ebc9`.

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
