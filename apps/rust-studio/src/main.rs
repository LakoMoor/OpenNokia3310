mod audio;
use eframe::egui::{self, Color32, Sense, Vec2};
use sha2::{Digest, Sha256};
use std::{
    fs,
    io::{Read, Write},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::{
        atomic::{AtomicBool, AtomicU32, Ordering},
        mpsc, Arc, Mutex,
    },
    thread,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

const FLASH_SIZE: u64 = 8 * 1024 * 1024;
fn tang_port_candidates(ports: &[serialport::SerialPortInfo]) -> Vec<String> {
    ports
        .iter()
        .filter_map(|port| match &port.port_type {
            serialport::SerialPortType::UsbPort(usb) if usb.vid == 0x0403 && usb.pid == 0x6010 => {
                Some(port.port_name.clone())
            }
            _ => None,
        })
        .collect()
}
fn packet(op: u8, value: u8) -> [u8; 3] {
    [0xa5, op, value]
}
fn decode(buf: &mut Vec<u8>, lcd: &mut [u8; 504]) -> bool {
    decode_with(buf, lcd, |_, _| {})
}
fn decode_with<F: FnMut(u8, &[u8])>(
    buf: &mut Vec<u8>,
    lcd: &mut [u8; 504],
    mut on_packet: F,
) -> bool {
    let mut changed = false;
    while buf.len() >= 5 {
        if &buf[..2] != b"N4" {
            buf.remove(0);
            continue;
        }
        let n = u16::from_be_bytes([buf[3], buf[4]]) as usize;
        if n > 1024 {
            buf.remove(0);
            continue;
        }
        let size = n + 6;
        if buf.len() < size {
            break;
        }
        if buf[..size].iter().fold(0, |x, b| x ^ b) != 0 {
            buf.remove(0);
            continue;
        }
        if buf[2] == 1 && n == 504 {
            lcd.copy_from_slice(&buf[5..509]);
            changed = true;
        }
        on_packet(buf[2], &buf[5..size - 1]);
        buf.drain(..size);
    }
    changed
}
fn validate(fpga: &Path, rom: &Path, ee: Option<&Path>) -> Result<Vec<u8>, String> {
    let bit = fs::read(fpga).map_err(|e| format!("FPGA image: {e}"))?;
    if fpga
        .extension()
        .and_then(|s| s.to_str())
        .map(|s| s.eq_ignore_ascii_case("fs"))
        != Some(true)
        || bit.len() <= 1000
        || bit.len() >= 16 * 1024 * 1024
    {
        return Err("Select a valid .fs image".into());
    }
    let lines: Vec<_> = bit.split(|b| *b == b'\n').collect();
    if !lines.iter().take(100).any(|l| l.starts_with(b"00111011")) {
        return Err("Unrecognized Gowin FS image".into());
    }
    let bits: usize = lines
        .iter()
        .map(|l| l.iter().filter(|b| **b == b'0' || **b == b'1').count())
        .sum();
    if bits / 8 > 0x200000 {
        return Err("FPGA image overlaps ROM region".into());
    }
    let mut data = fs::read(rom).map_err(|e| format!("ROM: {e}"))?;
    if data.len() != 0x1d0000 && data.len() != 0x200000 {
        return Err("Expected raw 3310 MCU+PPM or 2 MiB full flash".into());
    }
    if !data.windows(5).any(|w| w == b"NHM-5") {
        return Err("ROM is not marked NHM-5".into());
    }
    if let Some(path) = ee {
        let part = fs::read(path).map_err(|e| format!("EEPROM: {e}"))?;
        if part.len() != 0x30000 {
            return Err("EEPROM must be 192 KiB".into());
        }
        data.truncate(0x1d0000);
        data.extend(part);
    }
    if data.len() != 0x200000 {
        return Err("MCU+PPM needs an EEPROM partition".into());
    }
    Ok(data)
}
fn run(loader: &str, args: &[&str], log: &mpsc::Sender<String>) -> Result<(), String> {
    log.send(format!("Programmer: {}", args.join(" "))).ok();
    let mut command = Command::new(loader);
    // Bundled Windows programmers load DLLs from bin and the sibling lib.
    // Preserve the user's PATH for system-installed tools on every platform.
    if let Some(base) = Path::new(loader)
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
    {
        let mut paths = vec![
            base.to_path_buf(),
            base.parent().unwrap_or(base).join("lib"),
        ];
        if let Some(existing) = std::env::var_os("PATH") {
            paths.extend(std::env::split_paths(&existing));
        }
        command.env(
            "PATH",
            std::env::join_paths(paths).map_err(|e| e.to_string())?,
        );
    }
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        command.creation_flags(0x08000000); // CREATE_NO_WINDOW
    }
    let mut child = command
        .arg("-b")
        .arg("tangnano20k")
        .args(args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("Cannot start programmer: {e}"))?;
    // Drain both pipes concurrently: the programmer can emit enough output to
    // fill a pipe while waiting on USB, and the watchdog must keep running.
    for mut pipe in [
        Box::new(child.stdout.take().unwrap()) as Box<dyn Read + Send>,
        Box::new(child.stderr.take().unwrap()) as Box<dyn Read + Send>,
    ] {
        let log = log.clone();
        thread::spawn(move || {
            let mut chunk = [0u8; 4096];
            loop {
                match pipe.read(&mut chunk) {
                    Ok(0) | Err(_) => break,
                    Ok(n) => {
                        let _ = log.send(String::from_utf8_lossy(&chunk[..n]).into_owned());
                    }
                }
            }
        });
    }
    let start = std::time::Instant::now();
    loop {
        if let Some(status) = child.try_wait().map_err(|e| e.to_string())? {
            if !status.success() {
                return Err("Programmer failed; remaining steps were not run. Flash may be incomplete; retain the backup.".into());
            }
            return Ok(());
        }
        if start.elapsed() > Duration::from_secs(600) {
            let _ = child.kill();
            let _ = child.wait();
            return Err("Programmer timed out; flash may be incomplete. Retain the backup.".into());
        }
        thread::sleep(Duration::from_millis(100));
    }
}
fn install(
    loader: String,
    fpga: String,
    rom: String,
    eeprom: String,
    dir: String,
    tx: mpsc::Sender<String>,
) -> Result<(), String> {
    install_with(loader, fpga, rom, eeprom, dir, tx, run)
}

fn install_with<F>(
    loader: String,
    fpga: String,
    rom: String,
    eeprom: String,
    dir: String,
    tx: mpsc::Sender<String>,
    mut program: F,
) -> Result<(), String>
where
    F: FnMut(&str, &[&str], &mpsc::Sender<String>) -> Result<(), String>,
{
    let data = validate(
        Path::new(&fpga),
        Path::new(&rom),
        if eeprom.is_empty() {
            None
        } else {
            Some(Path::new(&eeprom))
        },
    )?;
    let folder = PathBuf::from(dir);
    fs::create_dir_all(&folder).map_err(|e| e.to_string())?;
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| e.to_string())?
        .as_nanos();
    let backup = folder.join(format!("tang-flash-{stamp}.bin"));
    let prepared = folder.join(format!("nokia-rom-{stamp}.bin"));
    fs::write(&prepared, &data).map_err(|e| e.to_string())?;
    let b = backup.to_str().ok_or("Invalid backup path")?;
    let p = prepared.to_str().ok_or("Invalid ROM path")?;
    program(
        &loader,
        &["--dump-flash", "-o", "0", "--file-size", "8388608", b],
        &tx,
    )?;
    if fs::metadata(&backup).map_err(|e| e.to_string())?.len() != FLASH_SIZE {
        return Err("Incomplete backup; no write attempted".into());
    }
    let hash = format!(
        "{:x}",
        Sha256::digest(fs::read(&backup).map_err(|e| e.to_string())?)
    );
    fs::write(
        backup.with_extension("sha256"),
        format!(
            "{hash}  {}\n",
            backup.file_name().unwrap().to_string_lossy()
        ),
    )
    .map_err(|e| e.to_string())?;
    tx.send(format!("Backup: {b}\nSHA-256: {hash}")).ok();
    program(
        &loader,
        &["-f", "--verify", "-o", "0x200000", "--file-type", "bin", p],
        &tx,
    )?;
    program(&loader, &["-f", "--verify", &fpga], &tx)?;
    program(&loader, &[&fpga], &tx)?;
    tx.send(
        "Flash verified and FPGA loaded. Phone boot and network require separate verification."
            .into(),
    )
    .ok();
    Ok(())
}
struct Studio {
    port: String,
    loader: String,
    fpga: String,
    rom: String,
    eeprom: String,
    folder: String,
    log: String,
    lcd: [u8; 504],
    keys: Arc<AtomicU32>,
    key_until: [Option<std::time::Instant>; 17],
    stop: Option<Arc<AtomicBool>>,
    serial_busy: Arc<AtomicBool>,
    rx: Option<mpsc::Receiver<(Vec<u8>, bool, Option<u8>)>>,
    gray: bool,
    events: mpsc::Receiver<String>,
    tx: mpsc::Sender<String>,
    installing: Arc<AtomicBool>,
    ports: Vec<String>,
    page: u8,
    audio: Arc<Mutex<audio::State>>,
    audio_test: Arc<AtomicBool>,
    commands: Option<mpsc::Sender<[u8; 3]>>,
    volume: u8,
}
impl Default for Studio {
    fn default() -> Self {
        let (tx, events) = mpsc::channel();
        Self {
            port: String::new(),
            loader: "openFPGALoader".into(),
            fpga: String::new(),
            rom: String::new(),
            eeprom: String::new(),
            folder: "backups".into(),
            log: String::new(),
            lcd: [0; 504],
            keys: Arc::new(AtomicU32::new(0)),
            key_until: [None; 17],
            stop: None,
            serial_busy: Arc::new(AtomicBool::new(false)),
            rx: None,
            gray: false,
            events,
            tx,
            installing: Arc::new(AtomicBool::new(false)),
            ports: Vec::new(),
            page: 0,
            audio: Arc::new(Mutex::new(audio::State::default())),
            audio_test: Arc::new(AtomicBool::new(false)),
            commands: None,
            volume: 5,
        }
    }
}
impl Studio {
    fn disconnect(&mut self) {
        self.keys.store(0, Ordering::Relaxed);
        self.key_until = [None; 17];
        if let Some(stop) = self.stop.take() {
            stop.store(true, Ordering::Relaxed);
        }
        self.rx = None;
        self.commands = None;
    }
    fn connect(&mut self) {
        if self.serial_busy.swap(true, Ordering::SeqCst) {
            return;
        }
        self.disconnect();
        let serial_busy = self.serial_busy.clone();
        let name = self.port.clone();
        let keys = self.keys.clone();
        let stop = Arc::new(AtomicBool::new(false));
        let end = stop.clone();
        let tx = self.tx.clone();
        let audio = self.audio.clone();
        let audio_test = self.audio_test.clone();
        let (frame_tx, rx) = mpsc::sync_channel(2);
        let (command_tx, command_rx) = mpsc::channel::<[u8; 3]>();
        self.stop = Some(stop);
        self.rx = Some(rx);
        self.commands = Some(command_tx);
        thread::spawn(move || {
            let mut p = match serialport::new(&name, 115200)
                .timeout(Duration::from_millis(30))
                .open()
            {
                Ok(p) => p,
                Err(e) => {
                    tx.send(format!("Connection failed: {e}")).ok();
                    serial_busy.store(false, Ordering::SeqCst);
                    return;
                }
            };
            tx.send(format!("Connected {name}")).ok();
            let _audio_stream = match audio::start(audio.clone()) {
                Ok(stream) => Some(stream),
                Err(error) => {
                    let _ = tx.send(format!("Audio unavailable: {error}"));
                    None
                }
            };
            let _ = p.write_all(&packet(5, 1));
            let mut buf = Vec::new();
            let mut lcd = [0; 504];
            let mut gray = false;
            let mut board_volume = None;
            let mut last = std::time::Instant::now() - Duration::from_secs(1);
            while !end.load(Ordering::Relaxed) {
                while let Ok(command) = command_rx.try_recv() {
                    if let Err(error) = p.write_all(&command) {
                        let _ = tx.send(format!("Command failed: {error}"));
                        end.store(true, Ordering::Relaxed);
                        break;
                    }
                }
                if audio_test.swap(false, Ordering::Relaxed) {
                    if let Err(error) = p.write_all(&packet(8, 1)) {
                        let _ = tx.send(format!("Audio test failed: {error}"));
                        break;
                    }
                }
                if last.elapsed() >= Duration::from_millis(100) {
                    let k = keys.load(Ordering::Relaxed);
                    for i in 0..3 {
                        if p.write_all(&packet(2 + i, (k >> (8 * i)) as u8)).is_err() {
                            end.store(true, Ordering::Relaxed);
                            break;
                        }
                    }
                    last = std::time::Instant::now();
                }
                let mut chunk = [0; 1024];
                match p.read(&mut chunk) {
                    Ok(n) => {
                        buf.extend_from_slice(&chunk[..n]);
                        if decode_with(&mut buf, &mut lcd, |kind, payload| {
                            if kind == 2 && payload.len() >= 10 {
                                gray = payload[8] & 2 != 0;
                                board_volume = Some(payload[7].min(10));
                            }
                            if let Ok(mut state) = audio.lock() {
                                state.packet(kind, payload);
                            }
                        }) {
                            let _ = frame_tx.try_send((lcd.to_vec(), gray, board_volume));
                        }
                    }
                    Err(e) if e.kind() == std::io::ErrorKind::TimedOut => {}
                    Err(e) => {
                        tx.send(format!("Serial error: {e}")).ok();
                        break;
                    }
                }
            }
            for i in 0..3 {
                let _ = p.write_all(&packet(2 + i, 0));
            }
            let _ = p.write_all(&packet(5, 0));
            // Release the OS handle before allowing JTAG programming.
            drop(p);
            if let Ok(mut state) = audio.lock() {
                state.frequencies = [0.; 3];
            }
            tx.send("Disconnected".into()).ok();
            serial_busy.store(false, Ordering::SeqCst);
        });
    }
}
impl eframe::App for Studio {
    fn update(&mut self, ctx: &egui::Context, _: &mut eframe::Frame) {
        if self.installing.load(Ordering::SeqCst) && ctx.input(|i| i.viewport().close_requested()) {
            ctx.send_viewport_cmd(egui::ViewportCommand::CancelClose);
            self.log
                .push_str("Installation is still running; wait for it to finish before closing.\n");
        }
        while let Ok(s) = self.events.try_recv() {
            self.log.push_str(&s);
            self.log.push('\n');
        }
        if let Some(rx) = &self.rx {
            while let Ok((v, gray, volume)) = rx.try_recv() {
                self.lcd.copy_from_slice(&v);
                self.gray = gray;
                if !ctx.input(|i| i.pointer.any_down()) {
                    if let Some(volume) = volume {
                        self.volume = volume;
                    }
                }
            }
        }
        ctx.request_repaint_after(Duration::from_millis(50));
        egui::CentralPanel::default().show(ctx, |ui| {
            egui::ScrollArea::vertical().show(ui, |ui| {
                ui.add_space(14.);
                ui.horizontal(|ui| {
                    ui.vertical(|ui| {
                        ui.label(egui::RichText::new("OPEN NOKIA  /  STUDIO").size(14.).strong().color(Color32::from_rgb(184, 217, 143)));
                        ui.label(egui::RichText::new("A little phone. A bigger idea.").size(26.).strong());
                        ui.label(egui::RichText::new("TANG NANO 20K    •    EXPERIMENTAL BUILD").size(11.).color(Color32::from_gray(150)));
                    });
                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        let (label, color) = if self.installing.load(Ordering::Relaxed) { ("INSTALLING", Color32::from_rgb(224,184,100)) } else if self.serial_busy.load(Ordering::Relaxed) { ("CONNECTED / OPENING", Color32::from_rgb(184,217,143)) } else { ("DISCONNECTED", Color32::from_gray(165)) };
                        ui.label(egui::RichText::new(label).size(12.).color(color));
                    });
                });
                ui.add_space(20.);
                ui.horizontal(|ui| {
                    for (index, label) in [(0, "  Remote  "), (1, "  Install  "), (2, "  Activity  ")] {
                        if ui.selectable_label(self.page == index, label).clicked() {
                            self.page = index;
                            self.keys.store(0, Ordering::Relaxed);
                            self.key_until = [None; 17];
                        }
                    }
                });
                ui.add_space(12.); ui.separator(); ui.add_space(18.);
                if self.page == 0 {
                ui.label(egui::RichText::new("YOUR DEVICE").size(11.).color(Color32::from_gray(145)));
                ui.heading("Remote control");
                ui.label(egui::RichText::new("Connect your Tang to see and control the original phone screen.").color(Color32::from_gray(165)));
                ui.add_space(12.);
                ui.horizontal(|ui| {
                    ui.label("UART port");
                    ui.text_edit_singleline(&mut self.port);
                    if ui
                        .add_enabled(
                            !self.installing.load(Ordering::Relaxed)
                                && !self.serial_busy.load(Ordering::SeqCst),
                            egui::Button::new("Connect"),
                        )
                        .clicked()
                    {
                        self.connect()
                    }
                    if ui.button("Disconnect").clicked() {
                        self.disconnect()
                    }
                });
                ui.horizontal_wrapped(|ui| {
                    if ui.button("Find Tang / refresh ports").clicked() {
                        match serialport::available_ports() {
                            Ok(ports) => {
                                let candidates = tang_port_candidates(&ports);
                                self.ports = ports.iter().map(|p| p.port_name.clone()).collect();
                                if candidates.len() == 1 {
                                    self.port = candidates[0].clone();
                                    self.log.push_str(&format!("Found FT2232 UART candidate: {}.\n", self.port));
                                } else {
                                    self.log.push_str(&format!("Found {} FT2232 candidates; choose the UART port manually.\n", candidates.len()));
                                }
                            }
                            Err(e) => self.log.push_str(&format!("{e}\n")),
                        }
                    }
                    egui::ComboBox::from_label("Available ports")
                        .selected_text(if self.port.is_empty() { "Select a port" } else { &self.port })
                        .show_ui(ui, |ui| {
                            for name in &self.ports {
                                ui.selectable_value(&mut self.port, name.clone(), name);
                            }
                        });
                });
                ui.horizontal(|ui| {
                    if let Ok(mut state) = self.audio.lock() { ui.checkbox(&mut state.enabled, "Play device audio"); }
                    if ui.add_enabled(self.serial_busy.load(Ordering::SeqCst), egui::Button::new("Audio test")).clicked() {
                        self.audio_test.store(true, Ordering::Relaxed);
                    }
                });
                ui.horizontal_wrapped(|ui| {
                    let connected = self.serial_busy.load(Ordering::SeqCst);
                    if ui.add_enabled(connected, egui::Button::new("Device menu")).clicked() {
                        if let Some(tx) = &self.commands { let _ = tx.send(packet(5, 3)); }
                    }
                    if ui.add_enabled(connected, egui::Button::new("Green display")).clicked() {
                        if let Some(tx) = &self.commands { let _ = tx.send(packet(7, 0)); }
                    }
                    if ui.add_enabled(connected, egui::Button::new("Gray display")).clicked() {
                        if let Some(tx) = &self.commands { let _ = tx.send(packet(7, 1)); }
                    }
                    if ui.add_enabled(connected, egui::Slider::new(&mut self.volume, 0..=10).text("Volume")).changed() {
                        if let Some(tx) = &self.commands { let _ = tx.send(packet(6, self.volume)); }
                    }
                });
                ui.add_space(14.);
                ui.label(egui::RichText::new("LIVE DISPLAY  /  84 × 48").size(11.).color(Color32::from_gray(145)));
                    let scale = (ui.available_width() / 84.).clamp(2., 4.);
                let (rect, _) = ui.allocate_exact_size(Vec2::new(84.*scale, 48.*scale), Sense::hover());
                let (light, dark) = if self.gray { (Color32::from_rgb(214,217,203), Color32::from_rgb(37,43,36)) } else { (Color32::from_rgb(190,206,145), Color32::from_rgb(35,52,29)) };
                ui.painter().rect_filled(rect, 0., light);
                for y in 0..48 {
                    for x in 0..84 {
                        if self.lcd[(y / 8) * 84 + x] & (1 << (y % 8)) != 0 {
                            let min = rect.min + Vec2::new(x as f32 * scale, y as f32 * scale);
                            ui.painter().rect_filled(
                                egui::Rect::from_min_size(min, Vec2::splat(scale)),
                                0.,
                                dark,
                            );
                        }
                    }
                }
                ui.add_space(14.); ui.label(egui::RichText::new("KEYPAD").size(11.).color(Color32::from_gray(145)));
                let mut pressed = 0u32;
                for row in [
                        [("1", 1), ("2", 2), ("3", 3), ("Up", 14)],
                        [("4", 4), ("5", 5), ("6", 6), ("Down", 15)],
                    [("7", 7), ("8", 8), ("9", 9), ("OK", 12)],
                    [("*", 10), ("0", 0), ("#", 11), ("C", 13)],
                ] {
                    ui.horizontal(|ui| {
                        for (name, bit) in row {
                            let response =
                                ui.add(egui::Button::new(name).min_size(Vec2::new(45., 30.)));
                            if response.is_pointer_button_down_on() {
                                pressed |= 1 << bit;
                            }
                            if response.clicked() {
                                self.key_until[bit] =
                                    Some(std::time::Instant::now() + Duration::from_millis(150));
                            }
                        }
                    });
                }
                let power = ui.add(egui::Button::new("Power"));
                if power.is_pointer_button_down_on() {
                    pressed |= 1 << 16;
                }
                if power.clicked() {
                    self.key_until[16] =
                        Some(std::time::Instant::now() + Duration::from_millis(150));
                }
                let now = std::time::Instant::now();
                for (bit, deadline) in self.key_until.iter_mut().enumerate() {
                    if deadline.is_some_and(|until| now < until) {
                        pressed |= 1 << bit;
                    } else {
                        *deadline = None;
                    }
                }
                self.keys.store(pressed, Ordering::Relaxed);
                } else if self.page == 1 {
                ui.label(egui::RichText::new("FIRMWARE  /  FLASH").size(11.).color(Color32::from_gray(145)));
                ui.heading("Install your phone");
                ui.label(egui::RichText::new("One guided operation: back up, write and verify.").color(Color32::from_gray(165)));
                ui.add_space(18.);
                ui.label("Choose your local files and backup destination.");
                for (label, value) in [
                    ("openFPGALoader", &mut self.loader),
                    ("FPGA .fs", &mut self.fpga),
                    ("Nokia ROM", &mut self.rom),
                    ("EEPROM (optional)", &mut self.eeprom),
                    ("Backup directory", &mut self.folder),
                ] {
                    ui.horizontal(|ui| {
                        ui.label(label);
                        ui.text_edit_singleline(value);
                        if ui.button("Browse…").clicked() {
                            let dialog = rfd::FileDialog::new();
                            let selected = if label == "Backup directory" {
                                dialog.pick_folder()
                            } else {
                                dialog.pick_file()
                            };
                            if let Some(path) = selected {
                                *value = path.to_string_lossy().into_owned();
                            }
                        }
                    });
                }
                if ui
                    .add_enabled(
                        !self.installing.load(Ordering::Relaxed)
                            && !self.serial_busy.load(Ordering::SeqCst),
                        egui::Button::new("Back up and install"),
                    )
                    .clicked()
                {
                    let args = (
                        self.loader.clone(),
                        self.fpga.clone(),
                        self.rom.clone(),
                        self.eeprom.clone(),
                        self.folder.clone(),
                    );
                    let tx = self.tx.clone();
                    let busy = self.installing.clone();
                    busy.store(true, Ordering::Relaxed);
                    thread::spawn(move || {
                        if let Err(e) = install(args.0, args.1, args.2, args.3, args.4, tx.clone())
                        {
                            tx.send(format!("Installation failed: {e}")).ok();
                        }
                        busy.store(false, Ordering::Relaxed);
                    });
                }
                ui.label(
                    "Disconnect UART before programming. Experimental image; keep the backup.",
                );
                } else {
                ui.label(egui::RichText::new("SESSION LOG").size(11.).color(Color32::from_gray(145)));
                ui.heading("Activity");
                ui.label(egui::RichText::new("Connection and installation messages appear here.").color(Color32::from_gray(165)));
                ui.add_space(12.);
                egui::ScrollArea::vertical()
                    .max_height(450.)
                    .show(ui, |ui| {
                        ui.monospace(&self.log);
                    });
                }
            });
        });
    }
}
impl Drop for Studio {
    fn drop(&mut self) {
        self.disconnect();
    }
}
fn main() -> eframe::Result {
    let args: Vec<String> = std::env::args().collect();
    if args.len() == 3 && args[1] == "--probe-serial" {
        if let Err(error) = probe_serial(&args[2]) {
            eprintln!("Serial probe failed: {error}");
            std::process::exit(1);
        }
        return Ok(());
    }
    if args.len() == 3 && args[1] == "--probe-key" {
        if let Err(error) = probe_key(&args[2]) {
            eprintln!("Key probe failed: {error}");
            std::process::exit(1);
        }
        return Ok(());
    }
    if args.len() == 3 && args[1] == "--probe-audio" {
        if let Err(error) = probe_audio(&args[2]) {
            eprintln!("Audio probe failed: {error}");
            std::process::exit(1);
        }
        return Ok(());
    }
    if args.len() == 3 && args[1] == "--probe-palette" {
        if let Err(error) = probe_palette(&args[2]) {
            eprintln!("Palette probe failed: {error}");
            std::process::exit(1);
        }
        return Ok(());
    }
    if args.len() == 3 && args[1] == "--probe-menu" {
        if let Err(error) = probe_menu(&args[2]) {
            eprintln!("Menu probe failed: {error}");
            std::process::exit(1);
        }
        return Ok(());
    }
    if args.len() == 2 && args[1] == "--list-tang" {
        match serialport::available_ports() {
            Ok(ports) => {
                for port in tang_port_candidates(&ports) {
                    println!("{port}");
                }
            }
            Err(error) => {
                eprintln!("Port enumeration failed: {error}");
                std::process::exit(1);
            }
        }
        return Ok(());
    }
    eframe::run_native(
        "Open Nokia Studio",
        eframe::NativeOptions {
            renderer: eframe::Renderer::Wgpu,
            viewport: egui::ViewportBuilder::default()
                .with_inner_size([900., 900.])
                .with_min_inner_size([480., 480.]),
            ..Default::default()
        },
        Box::new(|cc| {
            let mut visuals = egui::Visuals::dark();
            visuals.panel_fill = Color32::from_rgb(16, 21, 18);
            visuals.override_text_color = Some(Color32::from_rgb(226, 235, 219));
            visuals.window_fill = Color32::from_rgb(25, 32, 26);
            visuals.extreme_bg_color = Color32::from_rgb(21, 28, 22);
            visuals.widgets.inactive.bg_fill = Color32::from_rgb(38, 48, 39);
            visuals.widgets.hovered.bg_fill = Color32::from_rgb(58, 73, 55);
            visuals.widgets.active.bg_fill = Color32::from_rgb(95, 121, 71);
            visuals.selection.bg_fill = Color32::from_rgb(81, 110, 54);
            cc.egui_ctx.set_visuals(visuals);
            cc.egui_ctx.style_mut(|style| {
                style.spacing.item_spacing = Vec2::new(10., 9.);
                style.spacing.button_padding = Vec2::new(14., 9.);
            });
            Ok(Box::<Studio>::default())
        }),
    )
}

fn read_status_flag(
    port: &mut dyn serialport::SerialPort,
    mask: u8,
    wanted: Option<bool>,
    timeout: Duration,
) -> Result<bool, String> {
    let mut buf = Vec::new();
    let mut lcd = [0; 504];
    let start = std::time::Instant::now();
    while start.elapsed() < timeout {
        let mut bytes = [0; 1024];
        match port.read(&mut bytes) {
            Ok(n) => {
                buf.extend_from_slice(&bytes[..n]);
                let mut palette = None;
                decode_with(&mut buf, &mut lcd, |kind, body| {
                    if kind == 2 && body.len() >= 10 {
                        palette = Some(body[8] & mask != 0);
                    }
                });
                if let Some(value) = palette {
                    if wanted.is_none() || wanted == Some(value) {
                        return Ok(value);
                    }
                }
            }
            Err(e) if e.kind() == std::io::ErrorKind::TimedOut => (),
            Err(e) => return Err(e.to_string()),
        }
    }
    Err("No matching N4 status received".into())
}
fn probe_palette(name: &str) -> Result<(), String> {
    let mut port = serialport::new(name, 115200)
        .timeout(Duration::from_millis(100))
        .open()
        .map_err(|e| e.to_string())?;
    let original = read_status_flag(&mut *port, 2, None, Duration::from_secs(4))?;
    port.write_all(&packet(7, u8::from(!original)))
        .map_err(|e| e.to_string())?;
    let observed = read_status_flag(&mut *port, 2, Some(!original), Duration::from_secs(4));
    let restore_write = port
        .write_all(&packet(7, u8::from(original)))
        .map_err(|e| e.to_string());
    let restore = restore_write.and_then(|_| {
        read_status_flag(&mut *port, 2, Some(original), Duration::from_secs(4)).map(|_| ())
    });
    restore.map_err(|e| format!("Could not confirm restoring original palette: {e}"))?;
    observed?;
    println!("Tang palette switched and original palette was restored and confirmed on {name}.");
    Ok(())
}

fn probe_menu(name: &str) -> Result<(), String> {
    let mut port = serialport::new(name, 115200)
        .timeout(Duration::from_millis(100))
        .open()
        .map_err(|e| e.to_string())?;
    let original = read_status_flag(&mut *port, 1, None, Duration::from_secs(4))?;
    port.write_all(&packet(5, 3)).map_err(|e| e.to_string())?;
    let observed = read_status_flag(&mut *port, 1, Some(!original), Duration::from_secs(4));
    // Only issue the second toggle if the first was confirmed; otherwise the
    // resulting state is unknown and a blind toggle could change it again.
    observed?;
    port.write_all(&packet(5, 3))
        .map_err(|e| format!("Could not restore menu: {e}"))?;
    read_status_flag(&mut *port, 1, Some(original), Duration::from_secs(4))
        .map_err(|e| format!("Could not confirm restoring menu: {e}"))?;
    port.write_all(&packet(5, 0)).map_err(|e| e.to_string())?;
    println!("Tang menu toggled and original menu state restored on {name}.");
    Ok(())
}

fn probe_audio(name: &str) -> Result<(), String> {
    let audio = Arc::new(Mutex::new(audio::State::default()));
    let _stream = audio::start(audio.clone())?;
    let mut port = serialport::new(name, 115200)
        .timeout(Duration::from_millis(50))
        .open()
        .map_err(|e| e.to_string())?;
    port.write_all(&packet(5, 1)).map_err(|e| e.to_string())?;
    port.write_all(&packet(8, 1)).map_err(|e| e.to_string())?;
    let mut lcd = [0; 504];
    let mut buf = Vec::new();
    let mut seen = false;
    let start = std::time::Instant::now();
    while start.elapsed() < Duration::from_secs(3) {
        let mut bytes = [0; 1024];
        match port.read(&mut bytes) {
            Ok(n) => {
                buf.extend_from_slice(&bytes[..n]);
                decode_with(&mut buf, &mut lcd, |kind, body| {
                    if let Ok(mut state) = audio.lock() {
                        state.packet(kind, body);
                        if kind == 3 && state.frequencies[0] == 1000. {
                            seen = true;
                        }
                    }
                });
            }
            Err(e) if e.kind() == std::io::ErrorKind::TimedOut => (),
            Err(e) => return Err(e.to_string()),
        }
    }
    port.write_all(&packet(5, 0)).map_err(|e| e.to_string())?;
    if !seen {
        return Err("No 1 kHz test tone state received".into());
    }
    println!("Opened default audio output and received 1 kHz FPGA test state on {name}; audibility is not verified.");
    Ok(())
}

fn probe_key(name: &str) -> Result<(), String> {
    let mut port = serialport::new(name, 115200)
        .timeout(Duration::from_millis(30))
        .open()
        .map_err(|e| e.to_string())?;
    port.write_all(&packet(5, 1)).map_err(|e| e.to_string())?;
    let mut lcd = [0; 504];
    let mut before = None;
    let mut changed = false;
    let mut buf = Vec::new();
    let start = std::time::Instant::now();
    let mut last = start - Duration::from_secs(1);
    while start.elapsed() < Duration::from_secs(5) {
        if last.elapsed() >= Duration::from_millis(100) {
            let mask = if start.elapsed() >= Duration::from_secs(2)
                && start.elapsed() < Duration::from_millis(2400)
            {
                1u32 << 1
            } else {
                0
            };
            for i in 0..3 {
                port.write_all(&packet(2 + i, (mask >> (8 * i)) as u8))
                    .map_err(|e| e.to_string())?;
            }
            last = std::time::Instant::now();
        }
        let mut bytes = [0; 1024];
        match port.read(&mut bytes) {
            Ok(n) => {
                buf.extend_from_slice(&bytes[..n]);
                if decode(&mut buf, &mut lcd) {
                    if start.elapsed() < Duration::from_secs(2) {
                        before = Some(lcd);
                    } else if start.elapsed() >= Duration::from_millis(2400)
                        && before.is_some_and(|b| b != lcd)
                    {
                        changed = true;
                    }
                }
            }
            Err(e) if e.kind() == std::io::ErrorKind::TimedOut => (),
            Err(e) => return Err(e.to_string()),
        }
    }
    for i in 0..3 {
        port.write_all(&packet(2 + i, 0))
            .map_err(|e| e.to_string())?;
    }
    port.write_all(&packet(5, 0)).map_err(|e| e.to_string())?;
    if before.is_none() {
        return Err("No LCD frame before keypress".into());
    }
    if !changed {
        return Err("LCD did not change after key 1; phone state may not accept digits".into());
    }
    println!("LCD changed following a key 1 press on {name}; key release was sent.");
    Ok(())
}

fn probe_serial(name: &str) -> Result<(), String> {
    let mut port = serialport::new(name, 115200)
        .timeout(Duration::from_millis(100))
        .open()
        .map_err(|e| e.to_string())?;
    port.write_all(&packet(5, 1)).map_err(|e| e.to_string())?;
    let mut lcd = [0; 504];
    let mut buf = Vec::new();
    let mut frames = 0;
    let start = std::time::Instant::now();
    while start.elapsed() < Duration::from_secs(5) {
        let mut bytes = [0; 1024];
        match port.read(&mut bytes) {
            Ok(n) => {
                buf.extend_from_slice(&bytes[..n]);
                if decode(&mut buf, &mut lcd) {
                    frames += 1;
                }
            }
            Err(e) if e.kind() == std::io::ErrorKind::TimedOut => (),
            Err(e) => return Err(e.to_string()),
        }
    }
    port.write_all(&packet(5, 0)).map_err(|e| e.to_string())?;
    if frames == 0 {
        return Err("No valid N4 LCD frames received".into());
    }
    println!(
        "Received {frames} valid LCD frames over {name}; last frame SHA-256 {:x}",
        Sha256::digest(lcd)
    );
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn tang_detection_filters_usb_vendor_and_product() {
        use serialport::{SerialPortInfo, SerialPortType, UsbPortInfo};
        let usb = |name: &str, vid, pid| SerialPortInfo {
            port_name: name.into(),
            port_type: SerialPortType::UsbPort(UsbPortInfo {
                vid,
                pid,
                serial_number: None,
                manufacturer: None,
                product: None,
            }),
        };
        let ports = [
            usb("candidate", 0x0403, 0x6010),
            usb("other", 0x1a86, 0x6010),
            SerialPortInfo {
                port_name: "built-in".into(),
                port_type: SerialPortType::Unknown,
            },
        ];
        assert_eq!(tang_port_candidates(&ports), vec!["candidate"]);
    }
    #[test]
    fn packet_recovery() {
        let mut body = vec![0x4e, 0x34, 1, 1, 248];
        body.extend([0x55; 504]);
        let xor = body.iter().fold(0, |a, b| a ^ b);
        body.push(xor);
        let mut buf = vec![9, 8];
        buf.extend(body);
        let mut lcd = [0; 504];
        assert!(decode(&mut buf, &mut lcd));
        assert!(lcd.iter().all(|x| *x == 0x55));
        assert!(buf.is_empty());
    }
    #[test]
    fn malformed_packet_is_ignored() {
        let mut buf = vec![0x4e, 0x34, 1, 0xff, 0xff, 0];
        let mut lcd = [0; 504];
        assert!(!decode(&mut buf, &mut lcd));
        assert_eq!(lcd, [0; 504]);
    }
    #[test]
    fn installer_stops_at_each_failure_and_orders_verified_writes() {
        let root = std::env::temp_dir().join(format!(
            "nokia-test-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&root).unwrap();
        let fpga = root.join("test.fs");
        let rom = root.join("test.bin");
        fs::write(&fpga, format!("00111011\n{}", "0".repeat(1100))).unwrap();
        let mut rom_data = vec![0u8; 0x200000];
        rom_data[0..5].copy_from_slice(b"NHM-5");
        fs::write(&rom, rom_data).unwrap();
        for fail in 0..=4 {
            let mut calls = Vec::<Vec<String>>::new();
            let (tx, _) = mpsc::channel();
            let result = install_with(
                "fake-loader".into(),
                fpga.to_str().unwrap().into(),
                rom.to_str().unwrap().into(),
                "".into(),
                root.to_str().unwrap().into(),
                tx,
                |_, args, _| {
                    calls.push(args.iter().map(|s| s.to_string()).collect());
                    let step = calls.len();
                    if step == fail {
                        return Err("injected failure".into());
                    }
                    if step == 1 {
                        fs::write(args.last().unwrap(), vec![0x5au8; FLASH_SIZE as usize]).unwrap();
                    }
                    Ok(())
                },
            );
            assert_eq!(result.is_ok(), fail == 0);
            assert_eq!(calls.len(), if fail == 0 { 4 } else { fail });
            assert_eq!(calls[0][0], "--dump-flash");
            if calls.len() > 1 {
                assert_eq!(
                    &calls[1][..5],
                    ["-f", "--verify", "-o", "0x200000", "--file-type"]
                );
            }
            if calls.len() > 2 {
                assert_eq!(&calls[2][..2], ["-f", "--verify"]);
            }
            if calls.len() > 3 {
                assert_eq!(calls[3], vec![fpga.to_str().unwrap().to_string()]);
            }
        }
        let mut calls = 0;
        let (tx, _) = mpsc::channel();
        let result = install_with(
            "fake-loader".into(),
            fpga.to_str().unwrap().into(),
            rom.to_str().unwrap().into(),
            "".into(),
            root.to_str().unwrap().into(),
            tx,
            |_, args, _| {
                calls += 1;
                fs::write(args.last().unwrap(), [1u8; 16]).unwrap();
                Ok(())
            },
        );
        assert!(result.is_err());
        assert_eq!(calls, 1, "incomplete backup must block all writes");
        fs::remove_dir_all(root).unwrap();
    }
}
