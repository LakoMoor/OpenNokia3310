# Rust Studio interface

The desktop interface uses persistent Remote, Install and Activity navigation.
Remote groups the 84 by 48 device display and keypad inside a phone enclosure;
connection, palette and audio controls remain above it. All labels are English.
The initial window is 1120 by 940, with a 700 by 600 minimum and vertical scrolling.

Validation: Windows `cargo check --locked`, `cargo build --locked` and all five
existing Rust tests passed. These checks do not establish visual usability or
hardware behavior. The updated executable is in the local
`build/rust-probe/debug/open-nokia-studio.exe` output directory.

## Network regression observation

The local `build/trace-runs/ring-delays-call/run.json` records a completed
820,000,000-cycle original-ROM run with virtual networking at 16,875,000 Hz.
Initial and final key-script SHA256 hashes match. The trace reports 292 virtual
packets and 595 MDI consumer changes. DSP message 119 contains
`008001a809032a` at cycle 775,784,675 and message 122 contains
`0080015301` at cycle 787,697,511, matching the prior release/disconnect path.
This is simulation evidence only: it does not prove speech, SMS, FPGA resource
fit, or physical network operation. The network-enabled bitstream remains
unqualified.
