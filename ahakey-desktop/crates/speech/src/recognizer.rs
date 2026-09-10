use crate::{ModelStore, Result, SAMPLE_RATE};
use anyhow::{bail, Context};
use sherpa_onnx::{OfflineRecognizer, OfflineRecognizerConfig, OfflineSenseVoiceModelConfig};
use std::path::PathBuf;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RecognizerConfig {
    pub model_dir: PathBuf,
    pub threads: usize,
}

/// Owns an in-process sherpa-onnx C API recognizer via its official Rust wrapper.
/// Calls are synchronous; keep this on a recognition worker, not the UI thread.
pub struct Recognizer {
    inner: OfflineRecognizer,
}

impl Recognizer {
    pub fn new(config: RecognizerConfig) -> Result<Self> {
        ModelStore::new(config.model_dir.clone()).verify()?;
        let path = |file: &str| -> Result<String> {
            let path = config.model_dir.join(file);
            let text = path.to_str().context("Model path must be valid UTF-8")?;
            if text.contains('\0') {
                bail!("Model path contains a NUL character");
            }
            Ok(text.to_owned())
        };
        let mut settings = OfflineRecognizerConfig::default();
        settings.feat_config.sample_rate = SAMPLE_RATE as i32;
        settings.feat_config.feature_dim = 80;
        settings.model_config.sense_voice = OfflineSenseVoiceModelConfig {
            model: Some(path("model.int8.onnx")?),
            language: Some("auto".into()),
            use_itn: true,
        };
        settings.model_config.tokens = Some(path("tokens.txt")?);
        settings.model_config.num_threads = config.threads.clamp(1, 8) as i32;
        settings.model_config.provider = Some("cpu".into());
        settings.model_config.debug = false;
        Ok(Self {
            inner: OfflineRecognizer::create(&settings)
                .context("Cannot initialize native SenseVoice")?,
        })
    }

    /// Decode at most 30 seconds. Session recording uses bounded segments for
    /// long utterances rather than feeding an unbounded tensor to the engine.
    pub fn decode(&self, samples: &[f32], sample_rate: u32) -> Result<String> {
        if sample_rate != SAMPLE_RATE {
            bail!("Recognizer requires 16000 Hz mono audio");
        }
        if samples.len() > SAMPLE_RATE as usize * 30 {
            bail!("Decode segment exceeds 30 seconds");
        }
        if samples.iter().any(|sample| !sample.is_finite()) {
            bail!("Audio contains non-finite samples");
        }
        if samples.len() < 800 || samples.iter().all(|sample| sample.abs() < 0.00001) {
            return Ok(String::new());
        }
        let stream = self.inner.create_stream();
        stream.accept_waveform(sample_rate as i32, samples);
        self.inner.decode(&stream);
        let result = stream
            .get_result()
            .context("SenseVoice returned no recognition result")?;
        Ok(result.text.trim().to_string())
    }
}
