//! Native, explicit opt-in audio capture and local speech recognition.
//! No microphone, model download, or helper process is started on library load.

mod audio;
mod model;
mod recognizer;
mod session;

pub use audio::{input_devices, MicrophoneCapture};
pub use model::{
    CancellationToken, ModelStore, MODEL_BYTES, MODEL_SHA256, TOKENS_BYTES, TOKENS_SHA256,
};
pub use recognizer::{Recognizer, RecognizerConfig};
pub use session::{SessionConfig, SpeechEvent, SpeechSession};
pub type Result<T> = anyhow::Result<T>;
pub const SAMPLE_RATE: u32 = 16_000;
