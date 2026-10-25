# Companion applications

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

Run `python apps/desktop/opennokia.py` (Python 3 with Tk and `pyserial`), or
`apps/desktop/run.cmd` on Windows. Select the UART port and connect. The live LCD,
keyboard, system menu, volume and explicit hardware audio test use the same
protocol as Android. Keyboard: arrows, digits, Enter=Menu, Backspace/Esc=C.

The desktop app does not implement a cellular modem or local speaker playback;
FPGA audio is output through HDMI and pins 76/75.
