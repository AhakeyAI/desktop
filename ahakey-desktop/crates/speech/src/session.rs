use crate::{
    CancellationToken, MicrophoneCapture, Recognizer, RecognizerConfig, Result, SAMPLE_RATE,
};
use anyhow::{bail, Context};
use std::{
    path::PathBuf,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex, OnceLock,
    },
    thread,
    time::{Duration, Instant},
};

#[derive(Clone, Debug)]
pub struct SessionConfig {
    pub recognizer: RecognizerConfig,
    pub device_name: Option<String>,
    pub preview_interval: Duration,
    pub max_duration: Duration,
}
impl SessionConfig {
    pub fn new(model_dir: PathBuf) -> Self {
        Self {
            recognizer: RecognizerConfig {
                model_dir,
                threads: 4,
            },
            device_name: None,
            preview_interval: Duration::from_millis(800),
            max_duration: Duration::from_secs(120),
        }
    }
}

#[derive(Clone, Debug)]
pub enum SpeechEvent {
    Loading,
    Recording,
    /// Provisional rolling recognition; may be corrected by later updates.
    Partial(String),
    Recognizing,
    /// Only this event is eligible for insertion, after checking the UI's
    /// active-session generation and target window. This crate never injects.
    Final(String),
    Error(String),
    Cancelled,
}

struct Control {
    finish: AtomicBool,
    cancel: CancellationToken,
    done: AtomicBool,
    capture: Mutex<Option<MicrophoneCapture>>,
}
impl Control {
    fn stop_capture(&self) {
        let capture = self.capture.lock().ok().and_then(|mut slot| slot.take());
        if let Some(mut capture) = capture {
            capture.stop();
        }
    }
}

/// A single press/hold or toggle utterance. Its worker owns the recognizer.
/// `finish()` releases capture immediately, then finalizes off the UI thread.
/// `cancel()` suppresses pending recognition and releases capture immediately;
/// native inference already in flight may finish, but its result is discarded.
pub struct SpeechSession {
    control: Arc<Control>,
}
impl SpeechSession {
    pub fn start(
        config: SessionConfig,
        callback: impl Fn(SpeechEvent) + Send + Sync + 'static,
    ) -> Result<Self> {
        if config.max_duration < Duration::from_secs(1)
            || config.max_duration > Duration::from_secs(300)
        {
            bail!("Speech duration must be between 1 and 300 seconds");
        }
        if config.preview_interval < Duration::from_millis(300) {
            bail!("Preview interval must be at least 300 ms");
        }
        let control = Arc::new(Control {
            finish: AtomicBool::new(false),
            cancel: CancellationToken::new(),
            done: AtomicBool::new(false),
            capture: Mutex::new(None),
        });
        let worker_control = Arc::clone(&control);
        thread::Builder::new()
            .name("ahakey-local-speech".into())
            .spawn(move || {
                let emit = |event| {
                    if !worker_control.cancel.is_cancelled() {
                        callback(event);
                    }
                };
                let outcome = run_session(config, &worker_control, &emit);
                worker_control.stop_capture();
                if worker_control.cancel.is_cancelled() {
                    callback(SpeechEvent::Cancelled);
                } else {
                    match outcome {
                        Ok(text) => emit(SpeechEvent::Final(text)),
                        Err(error) => emit(SpeechEvent::Error(format!("{error:#}"))),
                    }
                }
                worker_control.done.store(true, Ordering::Release);
            })?;
        Ok(Self { control })
    }
    pub fn finish(&self) {
        self.control.finish.store(true, Ordering::Release);
        self.control.stop_capture();
    }
    pub fn cancel(&self) {
        self.control.cancel.cancel();
        self.finish();
    }
    pub fn is_finished(&self) -> bool {
        self.control.done.load(Ordering::Acquire)
    }
}
impl Drop for SpeechSession {
    fn drop(&mut self) {
        if !self.is_finished() {
            self.cancel();
        }
    }
}

fn run_session(
    config: SessionConfig,
    control: &Arc<Control>,
    emit: &dyn Fn(SpeechEvent),
) -> Result<String> {
    control.cancel.check()?;
    if control.finish.load(Ordering::Acquire) {
        return Ok(String::new());
    }
    emit(SpeechEvent::Loading);
    let limit = (config.max_duration.as_secs_f64() * SAMPLE_RATE as f64) as usize;
    let audio = Arc::new(Mutex::new(RecordingBuffer {
        samples: Vec::new(),
        limit,
    }));
    let input_error = Arc::new(Mutex::new(None));
    let audio_sink = Arc::clone(&audio);
    let error_sink = Arc::clone(&input_error);
    let audio_control = Arc::clone(control);
    let mut capture = MicrophoneCapture::start(
        config.device_name.as_deref(),
        move |chunk| {
            if audio_control.finish.load(Ordering::Acquire) || audio_control.cancel.is_cancelled() {
                return;
            }
            if let Ok(mut buffer) = audio_sink.lock() {
                if buffer.append(&chunk) {
                    audio_control.finish.store(true, Ordering::Release);
                }
            }
        },
        move |error| {
            if let Ok(mut slot) = error_sink.lock() {
                *slot = Some(error);
            }
        },
    )?;
    {
        let mut slot = control
            .capture
            .lock()
            .map_err(|_| anyhow::anyhow!("Capture state poisoned"))?;
        if control.finish.load(Ordering::Acquire) || control.cancel.is_cancelled() {
            capture.stop();
            return Ok(String::new());
        }
        *slot = Some(capture);
    }
    emit(SpeechEvent::Recording);
    // Capture begins before model initialization, so a cold load does not lose
    // the first words. finish/cancel can close the independent capture owner.
    let recognizer = cached_recognizer(config.recognizer)?;
    control.cancel.check()?;
    let mut previous = String::new();
    let mut last_preview = Instant::now()
        .checked_sub(config.preview_interval)
        .unwrap_or_else(Instant::now);
    while !control.finish.load(Ordering::Acquire) {
        control.cancel.check()?;
        if let Some(error) = input_error
            .lock()
            .map_err(|_| anyhow::anyhow!("Capture error state poisoned"))?
            .take()
        {
            bail!("{error}");
        }
        if last_preview.elapsed() >= config.preview_interval {
            let (window, rolling) = {
                let buffer = audio
                    .lock()
                    .map_err(|_| anyhow::anyhow!("Audio buffer poisoned"))?;
                let start = buffer
                    .samples
                    .len()
                    .saturating_sub(12 * SAMPLE_RATE as usize);
                (buffer.samples[start..].to_vec(), start > 0)
            };
            if window.len() >= SAMPLE_RATE as usize / 2 {
                let text = recognizer.decode(&window, SAMPLE_RATE)?;
                control.cancel.check()?;
                if !control.finish.load(Ordering::Acquire) && !text.is_empty() && text != previous {
                    previous = text.clone();
                    emit(SpeechEvent::Partial(if rolling {
                        format!("…{text}")
                    } else {
                        text
                    }));
                }
            }
            last_preview = Instant::now();
        }
        thread::sleep(Duration::from_millis(20));
    }
    control.stop_capture();
    control.cancel.check()?;
    if let Some(error) = input_error
        .lock()
        .map_err(|_| anyhow::anyhow!("Capture error state poisoned"))?
        .take()
    {
        bail!("{error}");
    }
    emit(SpeechEvent::Recognizing);
    let samples = {
        let mut buffer = audio
            .lock()
            .map_err(|_| anyhow::anyhow!("Audio buffer poisoned"))?;
        std::mem::take(&mut buffer.samples)
    };
    decode_final(&samples, &control.cancel, |chunk| {
        recognizer.decode(chunk, SAMPLE_RATE)
    })
}

// Retain one verified model after first use. Loading/hash verification per key
// press creates multi-second latency and repeated large allocations. Replacing
// the configuration replaces the cache, while an in-flight session owns its Arc.
type CachedRecognizer = Option<(RecognizerConfig, Arc<Recognizer>)>;
static MODEL_CACHE: OnceLock<Mutex<CachedRecognizer>> = OnceLock::new();
fn cached_recognizer(config: RecognizerConfig) -> Result<Arc<Recognizer>> {
    let mut cache = MODEL_CACHE
        .get_or_init(|| Mutex::new(None))
        .lock()
        .map_err(|_| anyhow::anyhow!("Local model cache poisoned"))?;
    if let Some((existing, recognizer)) = cache.as_ref() {
        if existing == &config {
            return Ok(Arc::clone(recognizer));
        }
    }
    let recognizer = Arc::new(Recognizer::new(config.clone())?);
    *cache = Some((config, Arc::clone(&recognizer)));
    Ok(recognizer)
}

struct RecordingBuffer {
    samples: Vec<f32>,
    limit: usize,
}
impl RecordingBuffer {
    fn append(&mut self, chunk: &[f32]) -> bool {
        let count = chunk
            .len()
            .min(self.limit.saturating_sub(self.samples.len()));
        self.samples.extend_from_slice(&chunk[..count]);
        self.samples.len() == self.limit
    }
}

// Limit final inference tensors to about 20 seconds. Prefer a quiet 100 ms
// boundary in the last three seconds, preserving every recorded sample. Longer
// continuous speech can still split a word, a documented offline-model limit.
fn final_boundary(samples: &[f32]) -> usize {
    let maximum = 20 * SAMPLE_RATE as usize;
    if samples.len() <= maximum {
        return samples.len();
    }
    let window = SAMPLE_RATE as usize / 10;
    let mut best = maximum;
    let mut energy = f32::MAX;
    for start in ((maximum - 3 * SAMPLE_RATE as usize)..maximum).step_by(window) {
        let current = samples[start..start + window]
            .iter()
            .map(|sample| sample * sample)
            .sum::<f32>();
        if current <= energy {
            energy = current;
            best = start + window / 2;
        }
    }
    if energy / (window as f32) < 0.0004 {
        best
    } else {
        maximum
    }
}
fn decode_final(
    samples: &[f32],
    cancel: &CancellationToken,
    mut decode: impl FnMut(&[f32]) -> Result<String>,
) -> Result<String> {
    let mut remaining = samples;
    let mut result = String::new();
    while !remaining.is_empty() {
        cancel.check()?;
        let boundary = final_boundary(remaining);
        let text = decode(&remaining[..boundary]).context("Final local transcription failed")?;
        cancel.check()?;
        if !result.is_empty()
            && !text.is_empty()
            && result
                .chars()
                .last()
                .is_some_and(|c| c.is_ascii_alphanumeric())
            && text
                .chars()
                .next()
                .is_some_and(|c| c.is_ascii_alphanumeric())
        {
            result.push(' ');
        }
        result.push_str(&text);
        remaining = &remaining[boundary..];
    }
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn recording_is_bounded_without_truncating_prior_audio() {
        let mut buffer = RecordingBuffer {
            samples: vec![],
            limit: 5,
        };
        assert!(!buffer.append(&[1., 2., 3.]));
        assert!(buffer.append(&[4., 5., 6.]));
        assert!(buffer.append(&[7.]));
        assert_eq!(buffer.samples, [1., 2., 3., 4., 5.]);
    }
    #[test]
    fn final_segments_are_bounded_and_cover_every_sample() {
        let samples = vec![0.2; SAMPLE_RATE as usize * 65];
        let mut lengths = vec![];
        let text = decode_final(&samples, &CancellationToken::new(), |chunk| {
            lengths.push(chunk.len());
            Ok("word".into())
        })
        .unwrap();
        assert_eq!(lengths.iter().sum::<usize>(), samples.len());
        assert!(lengths
            .iter()
            .all(|length| *length <= SAMPLE_RATE as usize * 20));
        assert_eq!(text, "word word word word");
    }
    #[test]
    fn cancellation_during_native_decode_discards_result_and_stops_followups() {
        let cancel = CancellationToken::new();
        let mut calls = 0;
        let result = decode_final(&vec![0.1; 40 * SAMPLE_RATE as usize], &cancel, |_| {
            calls += 1;
            cancel.cancel();
            Ok("must not be inserted".into())
        });
        assert!(result.is_err());
        assert_eq!(calls, 1);
    }
    #[test]
    fn final_segmentation_prefers_silence() {
        let mut samples = vec![0.2; SAMPLE_RATE as usize * 25];
        let start = 18 * SAMPLE_RATE as usize;
        samples[start..start + SAMPLE_RATE as usize / 10].fill(0.);
        assert_eq!(final_boundary(&samples), start + SAMPLE_RATE as usize / 20);
    }
}
