use eframe::egui::{self, Color32, Sense, Vec2};
use sha2::{Digest, Sha256};
use std::{
    fs,
    io::{Read, Write},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::{
        atomic::{AtomicBool, AtomicU32, Ordering},
        mpsc, Arc,
    },
    thread,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

const FLASH_SIZE: u64 = 8 * 1024 * 1024;
fn packet(op: u8, value: u8) -> [u8; 3] {
    [0xa5, op, value]
}
fn decode(buf: &mut Vec<u8>, lcd: &mut [u8; 504]) -> bool {
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
    let mut child = Command::new(loader)
        .arg("-b")
        .arg("tangnano20k")
        .args(args)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| format!("Cannot start programmer: {e}"))?;
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
    rx: Option<mpsc::Receiver<Vec<u8>>>,
    events: mpsc::Receiver<String>,
    tx: mpsc::Sender<String>,
    installing: Arc<AtomicBool>,
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
            events,
            tx,
            installing: Arc::new(AtomicBool::new(false)),
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
        let (frame_tx, rx) = mpsc::sync_channel(2);
        self.stop = Some(stop);
        self.rx = Some(rx);
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
            let _ = p.write_all(&packet(5, 1));
            let mut buf = Vec::new();
            let mut lcd = [0; 504];
            let mut last = std::time::Instant::now() - Duration::from_secs(1);
            while !end.load(Ordering::Relaxed) {
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
                        if decode(&mut buf, &mut lcd) {
                            let _ = frame_tx.try_send(lcd.to_vec());
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
            tx.send("Disconnected".into()).ok();
            serial_busy.store(false, Ordering::SeqCst);
        });
    }
}
impl eframe::App for Studio {
    fn update(&mut self, ctx: &egui::Context, _: &mut eframe::Frame) {
        while let Ok(s) = self.events.try_recv() {
            self.log.push_str(&s);
            self.log.push('\n');
        }
        if let Some(rx) = &self.rx {
            while let Ok(v) = rx.try_recv() {
                self.lcd.copy_from_slice(&v);
            }
        }
        ctx.request_repaint_after(Duration::from_millis(50));
        egui::CentralPanel::default().show(ctx, |ui| {
            egui::ScrollArea::vertical().show(ui, |ui| {
                ui.heading("Open Nokia Studio");
                ui.label("Experimental desktop remote and installer · Tang Nano 20K");
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
                    if ui.button("List serial ports").clicked() {
                        match serialport::available_ports() {
                            Ok(ports) => {
                                for p in ports {
                                    self.log
                                        .push_str(&format!("{} {:?}\n", p.port_name, p.port_type));
                                }
                            }
                            Err(e) => self.log.push_str(&format!("{e}\n")),
                        }
                    }
                });
                let (rect, _) = ui.allocate_exact_size(Vec2::new(420., 240.), Sense::hover());
                ui.painter()
                    .rect_filled(rect, 0., Color32::from_rgb(190, 206, 145));
                for y in 0..48 {
                    for x in 0..84 {
                        if self.lcd[(y / 8) * 84 + x] & (1 << (y % 8)) != 0 {
                            let min = rect.min + Vec2::new(x as f32 * 5., y as f32 * 5.);
                            ui.painter().rect_filled(
                                egui::Rect::from_min_size(min, Vec2::splat(5.)),
                                0.,
                                Color32::from_rgb(35, 52, 29),
                            );
                        }
                    }
                }
                let mut pressed = 0u32;
                for row in [
                    [("1", 1), ("2", 2), ("3", 3), ("↑", 14)],
                    [("4", 4), ("5", 5), ("6", 6), ("↓", 15)],
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
                ui.separator();
                ui.heading("Complete installation");
                ui.label("Choose local files. Flash is backed up and both writes are verified.");
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
                egui::ScrollArea::vertical()
                    .max_height(150.)
                    .show(ui, |ui| {
                        ui.monospace(&self.log);
                    });
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
    eframe::run_native(
        "Open Nokia Studio",
        eframe::NativeOptions {
            renderer: eframe::Renderer::Wgpu,
            ..Default::default()
        },
        Box::new(|_| Ok(Box::<Studio>::default())),
    )
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
