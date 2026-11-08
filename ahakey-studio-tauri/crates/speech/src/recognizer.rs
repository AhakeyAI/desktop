use crate::{ModelKind, ModelStore, Result, SAMPLE_RATE};
use anyhow::{bail, Context};
use sherpa_onnx::{
    OfflineRecognizer, OfflineRecognizerConfig, OfflineSenseVoiceModelConfig,
    OfflineWhisperModelConfig,
};
use std::path::PathBuf;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RecognizerConfig {
    pub model_dir: PathBuf,
    pub threads: usize,
    pub model_kind: ModelKind,
}

impl RecognizerConfig {
    pub fn new(model_dir: PathBuf, model_kind: ModelKind) -> Self {
        Self {
            model_dir,
            threads: 4,
            model_kind,
        }
    }

    pub fn sense_voice(model_dir: PathBuf) -> Self {
        Self::new(model_dir, ModelKind::SenseVoice)
    }
}

/// Owns an in-process sherpa-onnx C API recognizer via its official Rust wrapper.
/// Calls are synchronous; keep this on a recognition worker, not the UI thread.
pub struct Recognizer {
    inner: OfflineRecognizer,
}

impl Recognizer {
    pub fn new(config: RecognizerConfig) -> Result<Self> {
        ModelStore::new(config.model_dir.clone(), config.model_kind).verify()?;
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
        settings.model_config.num_threads = config.threads.clamp(1, 8) as i32;
        settings.model_config.provider = Some("cpu".into());
        settings.model_config.debug = false;

        match config.model_kind {
            ModelKind::SenseVoice => {
                settings.model_config.sense_voice = OfflineSenseVoiceModelConfig {
                    model: Some(path("model.int8.onnx")?),
                    language: Some("auto".into()),
                    use_itn: true,
                };
                settings.model_config.tokens = Some(path("tokens.txt")?);
            }
            ModelKind::Whisper(size) => {
                let prefix = size.file_prefix();
                settings.model_config.whisper = OfflineWhisperModelConfig {
                    encoder: Some(path(&format!("{prefix}-encoder.int8.onnx"))?),
                    decoder: Some(path(&format!("{prefix}-decoder.int8.onnx"))?),
                    language: Some(String::new()),
                    task: Some("transcribe".into()),
                    tail_paddings: 0,
                    enable_token_timestamps: false,
                    enable_segment_timestamps: false,
                };
                settings.model_config.tokens = Some(path(&format!("{prefix}-tokens.txt"))?);
            }
        }

        Ok(Self {
            inner: OfflineRecognizer::create(&settings)
                .with_context(|| format!("Cannot initialize native {}", config.model_kind.display_name()))?,
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
            .context("Recognizer returned no recognition result")?;
        Ok(result.text.trim().to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::WhisperSize;

    #[test]
    fn whisper_config_and_path_verification() {
        let dir = tempfile::tempdir().unwrap();
        let config = RecognizerConfig::new(
            dir.path().to_path_buf(),
            ModelKind::Whisper(WhisperSize::Base),
        );
        assert_eq!(config.model_kind, ModelKind::Whisper(WhisperSize::Base));
        assert_eq!(config.threads, 4);

        // Verification should fail indicating missing Whisper model files
        let result = Recognizer::new(config);
        assert!(result.is_err());
        let err = format!("{:#}", result.err().unwrap());
        assert!(
            err.contains("Whisper Base") && err.contains("missing"),
            "Error should identify missing Whisper Base model files: {err}"
        );
    }
}
