//! Explicitly selected cloud ASR. No microphone capture or automatic cloud fallback.
mod credentials;
pub mod protocol;
mod session;
pub use credentials::{CredentialStore, SecretToken};
pub use session::{CloudConfig, CloudEvent, CloudSession, ENDPOINT};

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum CloudError {
    #[error("Cloud speech configuration is incomplete or invalid")]
    InvalidConfig,
    #[error("Cloud connection or authentication failed")]
    Connection,
    #[error("Cloud speech operation timed out")]
    Timeout,
    #[error("Cloud speech response is invalid")]
    Protocol,
    #[error("Cloud speech response exceeds the size limit")]
    TooLarge,
    #[error("Cloud speech service returned code {0}")]
    Service(u32),
    #[error("Cloud audio queue is full; start a new recording")]
    QueueFull,
    #[error("Cloud speech session has ended")]
    Ended,
    #[error("Cloud speech session was cancelled")]
    Cancelled,
    #[error("Cloud audio must contain 1 to 3200 samples of 16 kHz mono PCM")]
    InvalidAudio,
    #[error("Cloud recording exceeds the five minute limit")]
    RecordingLimit,
    #[error("Secure credential storage is unavailable")]
    CredentialStore,
    #[error("No cloud speech credential is saved")]
    MissingCredential,
}
