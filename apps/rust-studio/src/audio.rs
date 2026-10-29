use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

#[derive(Clone)]
pub struct State {
    pub frequencies: [f32; 3],
    pub volume: f32,
    pub buzzer_volume: f32,
    pub last_packet: Instant,
    pub enabled: bool,
}
impl Default for State {
    fn default() -> Self {
        Self {
            frequencies: [0.; 3],
            volume: 0.,
            buzzer_volume: 0.,
            last_packet: Instant::now() - Duration::from_secs(2),
            enabled: true,
        }
    }
}
impl State {
    pub fn packet(&mut self, kind: u8, body: &[u8]) {
        self.last_packet = Instant::now();
        if kind != 3 || body.len() != 11 {
            return;
        }
        let word = |i| u16::from_be_bytes([body[i], body[i + 1]]);
        let amplitude = word(4);
        let divider = word(6);
        self.frequencies = [
            if amplitude != 0 {
                word(0) as f32 / 4.
            } else {
                0.
            },
            if amplitude != 0 {
                word(2) as f32 / 4.
            } else {
                0.
            },
            if body[8] != 0 && divider != 0 {
                13_000_000. / divider as f32
            } else {
                0.
            },
        ];
        self.volume = body[10].min(10) as f32 / 10.;
        self.buzzer_volume = body[9] as f32 / 255.;
    }
}
fn synth(state: &State, phase: &mut [f32; 3], rate: f32) -> f32 {
    if !state.enabled || state.last_packet.elapsed() > Duration::from_millis(700) {
        return 0.;
    }
    let mut value = 0.;
    for (i, hz) in state.frequencies.iter().copied().enumerate() {
        if (20. ..=11000.).contains(&hz) && hz < rate / 2. {
            phase[i] = (phase[i] + hz / rate).fract();
            value += if i == 2 {
                (if phase[i] < 0.5 { 1. } else { -1. }) * 0.067 * state.buzzer_volume
            } else {
                (phase[i] * std::f32::consts::TAU).sin() * 0.067
            };
        }
    }
    (value * state.volume).clamp(-1., 1.)
}
pub fn start(state: Arc<Mutex<State>>) -> Result<(cpal::Stream, String), String> {
    let device = cpal::default_host()
        .default_output_device()
        .ok_or("No default audio output")?;
    let supported = device.default_output_config().map_err(|e| e.to_string())?;
    let format = supported.sample_format();
    let config: cpal::StreamConfig = supported.into();
    let output = format!(
        "{} / {} Hz / {} channels / {:?}",
        device
            .name()
            .unwrap_or_else(|_| "Default audio device".into()),
        config.sample_rate.0,
        config.channels,
        format
    );
    let channels = config.channels as usize;
    let rate = config.sample_rate.0 as f32;
    let mut phase = [0.; 3];
    let on_error = |e| eprintln!("Audio output: {e}");
    let stream = match format {
        cpal::SampleFormat::F32 => device.build_output_stream(
            &config,
            move |out: &mut [f32], _| {
                let s = state.lock().unwrap().clone();
                for frame in out.chunks_mut(channels) {
                    let v = synth(&s, &mut phase, rate);
                    frame.fill(v);
                }
            },
            on_error,
            None,
        ),
        cpal::SampleFormat::I16 => device.build_output_stream(
            &config,
            move |out: &mut [i16], _| {
                let s = state.lock().unwrap().clone();
                for frame in out.chunks_mut(channels) {
                    let v = (synth(&s, &mut phase, rate) * 32767.) as i16;
                    frame.fill(v);
                }
            },
            on_error,
            None,
        ),
        cpal::SampleFormat::U16 => device.build_output_stream(
            &config,
            move |out: &mut [u16], _| {
                let s = state.lock().unwrap().clone();
                for frame in out.chunks_mut(channels) {
                    let v = ((synth(&s, &mut phase, rate) * 0.5 + 0.5) * 65535.) as u16;
                    frame.fill(v);
                }
            },
            on_error,
            None,
        ),
        _ => return Err(format!("Unsupported audio sample format: {format:?}")),
    }
    .map_err(|e| e.to_string())?;
    stream.play().map_err(|e| e.to_string())?;
    Ok((stream, output))
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn ringtone_buzzer_obeys_phone_volume_and_enable() {
        let mut s = State::default();
        // No DSP tones; 13MHz / 13000 gives a 1kHz ringtone oscillator.
        let mut body = [0, 0, 0, 0, 0, 0, 0x32, 0xc8, 1, 255, 10];
        s.packet(3, &body);
        let mut phase = [0.; 3];
        let samples: Vec<f32> = (0..4800).map(|_| synth(&s, &mut phase, 48000.)).collect();
        let rises = samples
            .windows(2)
            .filter(|w| w[0] < 0. && w[1] > 0.)
            .count();
        assert!((99..=101).contains(&rises));
        assert!(samples.iter().any(|v| *v > 0.06));
        assert!(samples.iter().any(|v| *v < -0.06));
        body[9] = 0;
        s.packet(3, &body);
        assert_eq!(synth(&s, &mut phase, 48000.), 0.);
        body[9] = 255;
        body[8] = 0;
        s.packet(3, &body);
        assert_eq!(synth(&s, &mut phase, 48000.), 0.);
    }
    #[test]
    fn audio_uses_device_state_and_silences_on_timeout() {
        let mut s = State::default();
        s.packet(3, &[0x0f, 0xa0, 0, 0, 0, 1, 0, 0, 0, 0, 10]);
        assert_eq!(s.frequencies[0], 1000.);
        let mut p = [0.; 3];
        assert_ne!(synth(&s, &mut p, 48000.), 0.);
        s.last_packet = Instant::now() - Duration::from_secs(1);
        assert_eq!(synth(&s, &mut p, 48000.), 0.);
    }
}
