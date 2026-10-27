# Companion applications

## Rust desktop preview

`rust-studio/` is an experimental cross-platform Rust desktop application using
egui and wgpu. Build with `cargo run --manifest-path apps/rust-studio/Cargo.toml`.
It supports the N4 live LCD and on-screen keypad, and invokes an installed
`openFPGALoader` for a backup-first combined FPGA/ROM installation. Enter the
UART port and local file paths explicitly. It is a development preview: Windows
hardware programming and other operating systems have not yet been qualified,
and it does not yet provide Android installation. The existing Windows
application remains available below. On Linux, building the audio backend
requires ALSA development headers.
ROM files and backups must not be committed to the repository.
On Windows, `cargo run --manifest-path apps/rust-studio/Cargo.toml --
--probe-serial COM6` received 21 checksum-valid LCD frames from the connected
Tang. This diagnostic does not test key input or flash writes. Installer tests
use a simulated programmer and cover step failures and incomplete backups;
the full Rust installation flow has not yet been tested on hardware.
The refresh button selects an FT2232 candidate only if exactly one matches;
when multiple candidates are present the user must choose the UART port.
The Windows Rust enumerator identified the attached Tang as COM6. A key probe
sent digit 1 followed by release and observed a subsequent LCD change; this
observation alone does not prove that the key caused that change.
Rust audio synthesizes the N4 device oscillator state on the default output and
falls silent after 700 ms without valid packets. `--probe-audio COM6` opened
the Windows output and received the FPGA 1 kHz test state; actual audibility
has not been confirmed. Closing the app window is cancelled during installation;
unexpected process termination or power loss can still interrupt a flash write.
The remote also offers system-menu, palette and volume commands; the LCD uses
the palette reported by the board and the slider tracks reported volume. On
Windows, `--probe-palette COM6` switched the connected Tang palette and verified
the changed N4 status, then restored and verified the original setting. Physical
display color, menu and volume controls still need separate hardware checks.

## Android (USB-C OTG)

`android/` builds **Open Nokia 3310**, an installable Android application (Android
7.0 or newer). Connect the phone to the Tang USB-C connector using a data-capable
OTG cable, then allow USB access. The app opens the FTDI UART **channel B** at
115200 baud. It does not open channel A (JTAG).

- Remote: live 84×48 LCD, full 17-key Nokia keyboard, hold/release, FPGA menu.
- Board: volume, palette, audio output test, restart confirmation and diagnostics.
- Audio: firmware-reported buzzer / DSP oscillator state played on Android.
- Calls: explicitly opens the Android dialer or SMS app. Calls use the Android
  phone's modem, SIM and audio. There is no cellular RF modem in the Tang design.
- About: connection instructions and project source.

No phone, SMS, contacts, microphone or Internet permissions are requested.
The user completes any actual call or message in Android's own app. USB input
releases on app backgrounding, disconnect and FPGA timeout. Sub-60ms taps are
held long enough to reach the original phone's key scan.

The current N4 FPGA image is needed for live LCD, audio and system settings.
Legacy N3 images still accept keypad input, but do not stream the screen.

### Build

Use JDK 17, Android SDK 34 and Gradle 8.9 (or the included wrapper). Set
`ANDROID_HOME`, or create an ignored `android/local.properties` with `sdk.dir`.

```powershell
cd apps/android
./gradlew.bat testDebugUnitTest assembleRelease
```

APK: `app/build/outputs/apk/release/app-release.apk`. Development releases are
signed with a local Android debug key; use your own protected release keystore
for a production distribution. Do not commit keystores or local SDK settings.

USB driver: [usb-serial-for-android](https://github.com/mik3y/usb-serial-for-android).
Gradle bootstrap and FTDI port selection are adapted from Open Pocket GBC
revision `46fea7708ca76c988ad74b646d18184403c031b1`. The Nokia UI and N4 transport
are new GPL-3.0-or-later code. Proprietary Nokia firmware is not bundled.

## Desktop

Download **OpenNokia3310-Windows-preview.zip** from the
[Windows preview release](https://github.com/LakoMoor/OpenNokia3310/releases/tag/v0.2.3-preview),
extract the entire folder, and run **OpenNokia3310.exe**. Python and OSS CAD Suite
are not required: the Windows build includes the programmer and its DLLs.
The Tang FTDI USB driver must be installed. The interface is in English.
The experimental Nokia FPGA image is included and selected by default for
temporary SRAM testing. Proprietary Nokia ROM is supplied separately by you.

The **Firmware** tab offers board detection, temporary FPGA SRAM testing,
persistent FPGA installation, Nokia ROM installation and full-flash backup.
Select a `.fs` for FPGA operations, or a raw `.bin`/`.fls` for Nokia ROM.
MCU+PPM dumps also need a separate 192 KiB EEPROM/PM partition. ROM validation
uses the same checks as `prepare_firmware.py`. ROM is written only at 0x200000;
FPGA configuration stays below it. Flash installation first saves the complete
8 MiB device and a SHA256 file to the selected backup folder, then programs with
read-back verification. A failed/incomplete backup blocks writing. SRAM tests
do not change persistent flash. JTAG operations interrupt the running FPGA.

Windows preview 0.2.3 adds **Install complete Nokia (FPGA + ROM)**: choose the
FPGA image and a local Nokia ROM once, then run this action. It validates both,
backs up flash once, writes/verifies ROM, writes/verifies FPGA and starts it.
If ROM programming fails, FPGA replacement is not attempted. This new combined
flow passes backend tests but still needs full hardware qualification.
ROM/EEPROM/backup choices are remembered locally for the next run; the current
release's bundled FPGA and programmer take precedence over obsolete paths.

UART disconnects before programming. Reconnect after loading the FPGA image.
To set up a board: install your ROM, test the Nokia `.fs` in SRAM, then install
the FPGA image persistently when satisfied. Original Nokia boot remains
unreliable in the current experimental integration; a successful upload alone
does not establish a working phone.

Run `python apps/desktop/opennokia.py` (Python 3 with Tk, `pyserial` and `sounddevice`), or
`apps/desktop/run.cmd` on Windows. Select the UART port and connect. The live LCD,
keyboard, system menu, volume and explicit hardware audio test use the same
protocol as Android. Keyboard: arrows, digits, Enter=Menu, Backspace/Esc=C.

**Play Tang audio on PC speakers** is enabled by default. Audio test requests
the actual Tang test tone; N4 audio-state packets drive local oscillator playback
on the default Windows audio output. Firmware buzzer/DSP tones use the same path.
Playback silences on USB data timeout or disconnect and can be disabled with
the checkbox. This reproduces reported oscillator state, rather than streaming
PCM from the FPGA. HDMI and pins 76/75 remain separate audio outputs.
The desktop app does not implement a cellular modem.

Build Windows portable ZIP with Python 3, PyInstaller, pefile, pyserial, sounddevice and a
local OSS CAD Suite (`OSS_CAD_SUITE`, default `E:/tools/oss-cad-suite`):
```powershell
python tools/package_desktop.py --fpga path/to/qualified.fs --fpga-sha256 EXPECTED_SHA256
```

The image must be selected explicitly and match its expected SHA256 before
packaging starts. `images/manifest.json` records the bundled image hash and
qualification limits. A recent failed build must not silently replace a
qualified image. Run flasher tests with
`python tests/test_desktop_flasher.py`. The executable also supports
`--smoke-test output.json` to construct/check both UI pages without USB writes.
`--audio-smoke-test output.json` plays a one-second local diagnostic tone and
reports actual audio callback frames. Audio tests: `python tests/test_pc_audio.py`.


If the original phone standby shows numbered diagnostics and repeated `x` fields,
it may be running Nokia Net Monitor. In the current v6.39 RTL simulation, opening
**Menu -> Net monitor**, selecting **test 0** and confirming restores normal
standby. This uses the phone's own menu; it does not change the LCD renderer.
See the verification log for the simulation capture and hardware limitations.
