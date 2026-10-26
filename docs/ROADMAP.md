# Original Nokia compatibility goal

The target is original Nokia 3310 firmware running on Tang Nano 20K, with a
virtual cellular environment inside FPGA. Real RF service is outside this
target. A recreated menu is not a substitute for original firmware behavior.

| Area | Acceptance evidence | Current state |
| --- | --- | --- |
| Boot | Full ROM CRC after SPI→SDRAM; repeated cold/warm boots; original standby | Blocked by corrupted ROM transfer; registered SPI CS fix awaits hardware |
| Original UI | Original Phonebook, Settings, languages, clock and games exercised | Older build reached original menus; current regression under diagnosis |
| Input | DS2, Windows and Android press/hold/release in original menus | DS2 previously confirmed; N4 system menu checked on Tang |
| Display | Matching original 84×48 framebuffer on HDMI, ST7735S and apps | Framebuffer logic passes; physical ST7735 appearance not yet confirmed |
| Audio | Original keypad, alerts, ringtone and game tones; HDMI and app playback | Register synthesis and PC playback tests pass; original ringtone not verified |
| SIM | ATR/APDU, phonebook/SMS records, PIN lifecycle and no SIM errors | Synthetic card with file/record tests; phone integration incomplete |
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
