# Nokia 3310 firmware images

Proprietary firmware is not included in this repository. Local images and
downloaded archives are ignored by Git. Use a legally obtained dump.

## Supported input

`tools/prepare_firmware.py` accepts a raw full 2 MiB NHM-5 flash dump. It also
accepts a raw 0x1D0000-byte MCU+PPM dump with an explicit 0x30000-byte EEPROM/PM
partition. Service update containers such as `.390` must be unpacked first;
renaming a service container to `.bin` does not make it a linear flash image.

```powershell
python tools/prepare_firmware.py path/to/full-dump.fls
python tools/prepare_firmware.py path/to/mcu-ppm.fls --eeprom path/to/eeprom.bin --output firmware/nokia3310.bin
```

The output includes a JSON manifest with source and output hashes, mapping and
the explicit EEPROM override. A known checksum/model marker is an input check;
it does not establish that a particular image will boot correctly.

| Phone address | Contents |
| --- | --- |
| 0x200000–0x3FFFFF | Full flash image |
| 0x200040 | Firmware entry point |
| 0x3D0000–0x3FFFFF | EEPROM/PM partition |

The full image is stored at **board SPI offset 0x200000**. `nokia_top` clears RAM,
copies the image from SPI flash into SDRAM and starts the CPU. Flash operations
performed by the emulated phone modify that SDRAM copy only; they are not yet
persisted to the physical SPI flash.

## Images verified during development

The MAME archive was obtained from [Planet Emulation](https://www.planetemu.net/en/rom/mame-roms-merged/noki3310).
Source SHA-1 values were checked against
[MAME's Nokia driver](https://github.com/mamedev/mame/blob/master/src/mame/nokia/nokia_3310.cpp).

| Image | Source SHA-1 |
| --- | --- |
| v5.79 PPM N, full raw flash | `649de05ed88205a080693b918cd1295ac691dff1` |
| v6.07 PPM C, full raw flash | `0e80b5f1698909c9850be770c1289566582aa77a` |
| v6.39 PPM W, raw MCU+PPM | `9051623c7864410ce1f68d3b854ce578bd251711` |

v5.79 and v6.39 W reached their original menus on the real FPGA.
Repeated boot reliability is still under investigation; see [STATUS.md](../docs/STATUS.md).

## English and Russian: v6.39 W

A v6.39 W MCU+PPM image was retrieved from the archival source
`https://nokia-moding.narod.ru/download/3310w639.rar` on October 22, 2026.
It contains English, Estonian, Russian and German. Its 1,248,256 populated MCU
bytes match the unpacked MAME service image `nhm5ny06.390` byte for byte.
The raw MCU+PPM SHA256 is
`11f86ac4f350d279a536963f8834ddc5eae064f5e615d396875d85229c58cc96`.

An explicit EEPROM/PM partition from the backed-up v5.79 full dump was appended
for testing. The resulting 2 MiB development image SHA256 is
`5cd18ff08b40f44c9dbe155bc09efbcea15b5037234fa9d54b3e43bac8fcc8a2`.
The physical SPI image matched this hash when read back in full.

Language selection: **Menu → Settings (6) → Phone settings (2) → Language (1)**.
English menus and applying Russian were captured directly from HDMI. The
current implementation loses changed language/settings after a restart.
