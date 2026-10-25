# Credits and provenance

| Component | Source / pinned revision | Use |
| --- | --- | --- |
| Board, HDMI, ST7735S | [LakoMoor/open-pocket-gbc](https://github.com/LakoMoor/open-pocket-gbc), `5e743424a308fb06b7de0923c02e6d0d1434b30b` | HDMI RTL, LCD driver, color buffer, font8x8, PLL/primitive wrappers, placement helper and selected pin constraints |
| Companion app bootstrap / interface study | Open Pocket GBC, `46fea7708ca76c988ad74b646d18184403c031b1` | Android Gradle bootstrap, FTDI UART port-B approach, menu/audio reference; Nokia UI and N4 protocol are new |
| ARM7TDMI-S | [birdybro/arm7tdmi-sv](https://github.com/birdybro/arm7tdmi-sv), `2b350d9c3902062329d9fdc55432fd4080bd88c9` | RTL CPU, canonical arm7tdmi_mister wrapper, BIG_ENDIAN=1; debug/coprocessor disabled |
| Nokia device behavior | [djr-747/nokia-dct3-emulator](https://github.com/djr-747/nokia-dct3-emulator), `2b4c10ffd6b22a2d021c7f515f27ceb2fb6c78cd` | Model 3310, key matrix, MAD2, LCD and CCONT behavior studied as device specifications |
| Firmware checksums | [MAME nokia_3310.cpp](https://github.com/mamedev/mame/blob/master/src/mame/nokia/nokia_3310.cpp) | v5.79/v6.07 dump verification and v6.39 MCU comparison |

The integration and new HDL are GPL-3.0-or-later; see [LICENSE](../LICENSE).
Third-party license texts are retained under `third_party/`.

HDMI in Open Pocket GBC originates from [hdl-util/hdmi](https://github.com/hdl-util/hdmi)
by Sameer Puri. Its MIT license is retained at
`third_party/open-pocket-gbc/rtl/hdmi/LICENSE-MIT`. Font8x8 originates from the
public-domain `font8x8_basic.h`; its original attribution is retained.

The ARM CPU includes a local interrupt-boundary fix, documented with its
reproducer in [LOCAL_CHANGES.md](../third_party/arm7tdmi-sv/LOCAL_CHANGES.md).
The upstream CPU is prerelease software. Successful synthesis and these tests
do not establish full architectural or phone compatibility.

The DS2 driver in `rtl/nokia/ds2_pad.sv` is a new implementation. The legacy
`dualshock_controller.v` is not incorporated. The revised driver uses the
conservative select/inter-byte timing observed in Open Pocket GBC.

Board changes retain the required pin groups and use 27/135 MHz HDMI clocks
and 16.875 MHz ARM/SDRAM clocks. PLL and CLKDIV names are preserved for placement
near the HDMI serializers. The copied SDRAM controller remains in `third_party/`.

Ignored `reference/` checkouts are research material and are not needed to build.
Required RTL dependencies are vendored in `third_party/`; ARM `files.f` paths
are adapted to that directory. Proprietary Nokia ROMs, backups and local build
logs are not part of this repository. Nokia and other product names remain
the trademarks of their respective owners.
