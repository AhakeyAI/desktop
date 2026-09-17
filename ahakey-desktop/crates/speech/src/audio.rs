use crate::{Result, SAMPLE_RATE};
use anyhow::{anyhow, bail, Context};
use cpal::{
    traits::{DeviceTrait, HostTrait, StreamTrait},
    FromSample, SampleFormat, SizedSample,
};
use std::{
    collections::VecDeque,
    sync::{mpsc, Arc},
    thread::{self, JoinHandle},
    time::Duration,
};

pub fn input_devices() -> Result<Vec<String>> {
    Ok(cpal::default_host()
        .input_devices()?
        .filter_map(|device| device.name().ok())
        .collect())
}

/// Native audio stream owned entirely by its capture thread (also on platforms
/// where cpal::Stream is !Send). Callbacks must be quick, bounded and nonblocking.
/// Dropping/stopping the handle releases the microphone without a helper process.
pub struct MicrophoneCapture {
    stop: mpsc::Sender<()>,
    worker: Option<JoinHandle<()>>,
}

impl MicrophoneCapture {
    pub fn start(
        device_name: Option<&str>,
        on_audio: impl Fn(Vec<f32>) + Send + Sync + 'static,
        on_error: impl Fn(String) + Send + Sync + 'static,
    ) -> Result<Self> {
        let name = device_name.map(str::to_owned);
        let (stop, stop_rx) = mpsc::channel();
        let (ready_tx, ready_rx) = mpsc::sync_channel(1);
        let worker = thread::Builder::new()
            .name("ahakey-microphone".into())
            .spawn(move || {
                let result = open_stream(name.as_deref(), Arc::new(on_audio), Arc::new(on_error));
                match result {
                    Ok(stream) => {
                        if ready_tx.send(Ok(())).is_ok() {
                            let _ = stop_rx.recv();
                        }
                        let _ = stream.pause();
                        drop(stream);
                    }
                    Err(error) => {
                        let _ = ready_tx.send(Err(format!("{error:#}")));
                    }
                }
            })?;
        match ready_rx.recv_timeout(Duration::from_secs(10)) {
            Ok(Ok(())) => Ok(Self {
                stop,
                worker: Some(worker),
            }),
            result => {
                let _ = stop.send(());
                // A platform API may be stuck opening a device: detach instead
                // of hanging the UI. Its next successful open will close itself.
                bail!(
                    "{}",
                    match result {
                        Ok(Err(message)) => message,
                        _ => "Microphone initialization timed out".into(),
                    }
                )
            }
        }
    }
    pub fn stop(&mut self) {
        let _ = self.stop.send(());
        if let Some(worker) = self.worker.take() {
            if worker.thread().id() != thread::current().id() {
                let _ = worker.join();
            }
        }
    }
}
impl Drop for MicrophoneCapture {
    fn drop(&mut self) {
        self.stop();
    }
}

type AudioCallback = Arc<dyn Fn(Vec<f32>) + Send + Sync>;
type ErrorCallback = Arc<dyn Fn(String) + Send + Sync>;
fn open_stream(
    name: Option<&str>,
    audio: AudioCallback,
    error: ErrorCallback,
) -> Result<cpal::Stream> {
    let host = cpal::default_host();
    let device = if let Some(name) = name {
        host.input_devices()?
            .find(|device| device.name().is_ok_and(|value| value == name))
            .context("Selected microphone is not available")?
    } else {
        host.default_input_device()
            .context("No default microphone is available")?
    };
    let supported = device
        .default_input_config()
        .context("Microphone has no supported input configuration")?;
    let config: cpal::StreamConfig = supported.clone().into();
    let stream = match supported.sample_format() {
        SampleFormat::F32 => build_stream::<f32>(&device, &config, audio, error),
        SampleFormat::F64 => build_stream::<f64>(&device, &config, audio, error),
        SampleFormat::I8 => build_stream::<i8>(&device, &config, audio, error),
        SampleFormat::I16 => build_stream::<i16>(&device, &config, audio, error),
        SampleFormat::I32 => build_stream::<i32>(&device, &config, audio, error),
        SampleFormat::I64 => build_stream::<i64>(&device, &config, audio, error),
        SampleFormat::U8 => build_stream::<u8>(&device, &config, audio, error),
        SampleFormat::U16 => build_stream::<u16>(&device, &config, audio, error),
        SampleFormat::U32 => build_stream::<u32>(&device, &config, audio, error),
        SampleFormat::U64 => build_stream::<u64>(&device, &config, audio, error),
        format => Err(anyhow!("Unsupported microphone sample format {format:?}")),
    }?;
    stream
        .play()
        .context("Cannot start microphone; check system microphone permissions")?;
    Ok(stream)
}
fn build_stream<T>(
    device: &cpal::Device,
    config: &cpal::StreamConfig,
    audio: AudioCallback,
    error: ErrorCallback,
) -> Result<cpal::Stream>
where
    T: SizedSample,
    f32: FromSample<T>,
{
    let mut normalizer = MonoResampler::new(config.sample_rate.0, config.channels as usize)?;
    Ok(device.build_input_stream(
        config,
        move |data: &[T], _: &cpal::InputCallbackInfo| {
            let samples = normalizer.push(data.iter().map(|sample| sample.to_sample::<f32>()));
            if !samples.is_empty() {
                audio(samples);
            }
        },
        move |err| error(format!("Microphone stream failed: {err}")),
        None,
    )?)
}

/// Streaming 64-tap Hann-windowed sinc, normalized for DC gain. Downmixing and
/// fractional resampling state survive callback boundaries. The anti-alias
/// cutoff scales for downsampling (e.g. 48 kHz -> 16 kHz); latency is 32 input
/// samples. Stop may discard this sub-millisecond filter tail.
struct MonoResampler {
    input_rate: u32,
    channels: usize,
    partial_sum: f32,
    partial_channels: usize,
    buffer: VecDeque<f32>,
    position: f64,
}
impl MonoResampler {
    fn new(input_rate: u32, channels: usize) -> Result<Self> {
        if !(8_000..=384_000).contains(&input_rate) || !(1..=32).contains(&channels) {
            bail!("Unsupported microphone sample rate or channel count");
        }
        Ok(Self {
            input_rate,
            channels,
            partial_sum: 0.,
            partial_channels: 0,
            buffer: std::iter::repeat_n(0., 32).collect(),
            position: 32.,
        })
    }
    fn push(&mut self, samples: impl Iterator<Item = f32>) -> Vec<f32> {
        let mut output = Vec::new();
        for sample in samples {
            self.partial_sum += if sample.is_finite() {
                sample.clamp(-1., 1.)
            } else {
                0.
            };
            self.partial_channels += 1;
            if self.partial_channels == self.channels {
                let mono = self.partial_sum / self.channels as f32;
                if self.input_rate == SAMPLE_RATE {
                    output.push(mono);
                } else {
                    self.buffer.push_back(mono);
                }
                self.partial_channels = 0;
                self.partial_sum = 0.;
            }
        }
        if self.input_rate == SAMPLE_RATE {
            return output;
        }
        let cutoff = (SAMPLE_RATE as f64 / self.input_rate as f64).min(1.) * 0.94;
        while self.position.floor() as usize + 32 < self.buffer.len() {
            let center = self.position.floor() as usize;
            let mut weighted = 0.;
            let mut gain = 0.;
            for index in center - 31..=center + 32 {
                let distance = index as f64 - self.position;
                let angle = std::f64::consts::PI * distance * cutoff;
                let sinc = if angle.abs() < 1e-10 {
                    1.
                } else {
                    angle.sin() / angle
                };
                let window = 0.5 + 0.5 * (std::f64::consts::PI * distance / 32.).cos();
                let weight = sinc * window * cutoff;
                weighted += self.buffer[index] as f64 * weight;
                gain += weight;
            }
            output.push((weighted / gain).clamp(-1., 1.) as f32);
            self.position += self.input_rate as f64 / SAMPLE_RATE as f64;
        }
        let discard = (self.position.floor() as usize)
            .saturating_sub(32)
            .min(self.buffer.len());
        self.buffer.drain(..discard);
        self.position -= discard as f64;
        output
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn stereo_downmix_and_partial_frames_are_preserved() {
        let mut resampler = MonoResampler::new(16000, 2).unwrap();
        assert!(resampler.push([1.].into_iter()).is_empty());
        assert_eq!(
            resampler.push([-1., 0.8, 0.2, f32::NAN, 0.].into_iter()),
            vec![0., 0.5, 0.]
        );
    }
    #[test]
    fn chunk_boundaries_do_not_change_resampled_audio() {
        let input: Vec<f32> = (0..88200).map(|i| ((i / 2) as f32 * 0.1).sin()).collect();
        let expected = MonoResampler::new(44100, 2)
            .unwrap()
            .push(input.iter().copied());
        let mut resampler = MonoResampler::new(44100, 2).unwrap();
        let actual: Vec<f32> = input
            .chunks(317)
            .flat_map(|chunk| resampler.push(chunk.iter().copied()))
            .collect();
        assert!((15980..=16000).contains(&actual.len()));
        assert_eq!(actual.len(), expected.len());
        let max_error = actual
            .iter()
            .zip(&expected)
            .map(|(a, b)| (a - b).abs())
            .fold(0., f32::max);
        assert!(max_error < 0.00001, "{max_error}");
        assert!(resampler.buffer.len() < 100);
    }
    #[test]
    fn resampling_rejects_out_of_band_tone() {
        let energy = |frequency: f32| {
            let signal = (0..48000)
                .map(|i| (2. * std::f32::consts::PI * frequency * i as f32 / 48000.).sin());
            let output = MonoResampler::new(48000, 1).unwrap().push(signal);
            output[100..].iter().map(|x| x * x).sum::<f32>() / (output.len() - 100) as f32
        };
        let voice = energy(1000.);
        let alias = energy(12000.);
        assert!(voice > 0.45);
        assert!(alias < 0.001, "Aliased energy: {alias}");
    }
}
