use crate::Result;
use anyhow::{bail, Context};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    fs::{self, File},
    io::{Read, Write},
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
    time::Duration,
};

pub const MODEL_SHA256: &str = "c71f0ce00bec95b07744e116345e33d8cbbe08cef896382cf907bf4b51a2cd51";
pub const TOKENS_SHA256: &str = "f449eb28dc567533d7fa59be34e2abca8784f771850c78a47fb731a31429a1dc";
pub const MODEL_BYTES: u64 = 239_233_841;
pub const TOKENS_BYTES: u64 = 315_894;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
#[serde(rename_all = "kebab-case")]
pub enum WhisperSize {
    Tiny,
    #[default]
    Base,
    Small,
    Turbo,
}

impl WhisperSize {
    pub const fn file_prefix(&self) -> &'static str {
        match self {
            Self::Tiny => "tiny",
            Self::Base => "base",
            Self::Small => "small",
            Self::Turbo => "turbo",
        }
    }

    pub const fn id(&self) -> &'static str {
        match self {
            Self::Tiny => "whisper-tiny",
            Self::Base => "whisper-base",
            Self::Small => "whisper-small",
            Self::Turbo => "whisper-turbo",
        }
    }

    pub const fn display_name(&self) -> &'static str {
        match self {
            Self::Tiny => "Whisper Tiny",
            Self::Base => "Whisper Base",
            Self::Small => "Whisper Small",
            Self::Turbo => "Whisper Large V3 Turbo",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
#[serde(rename_all = "kebab-case")]
pub enum ModelKind {
    #[default]
    SenseVoice,
    Whisper(WhisperSize),
}

impl ModelKind {
    pub const fn id(&self) -> &'static str {
        match self {
            Self::SenseVoice => "sensevoice-2024-07-17",
            Self::Whisper(size) => size.id(),
        }
    }

    pub const fn display_name(&self) -> &'static str {
        match self {
            Self::SenseVoice => "SenseVoice Small INT8",
            Self::Whisper(size) => size.display_name(),
        }
    }

    pub const fn base_url(&self) -> &'static str {
        match self {
            Self::SenseVoice => {
                "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/2365baeacb507f821a0c8120fcee3d484dba7a07/"
            }
            Self::Whisper(WhisperSize::Tiny) => {
                "https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny/resolve/65176e2deb88badc814a94058666cadccc29b61c/"
            }
            Self::Whisper(WhisperSize::Base) => {
                "https://huggingface.co/csukuangfj/sherpa-onnx-whisper-base/resolve/bb53ee204431c90d314c1cc08d28d23e5b7927cc/"
            }
            Self::Whisper(WhisperSize::Small) => {
                "https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small/resolve/8f3c18b358db4d1f2fc1eae49d75cd20989e4309/"
            }
            Self::Whisper(WhisperSize::Turbo) => {
                "https://huggingface.co/csukuangfj/sherpa-onnx-whisper-turbo/resolve/2ca6ff69fc878651b770880507669577ac41c2ff/"
            }
        }
    }

    pub const fn files(&self) -> &'static [(&'static str, &'static str, u64)] {
        match self {
            Self::SenseVoice => &[
                ("model.int8.onnx", MODEL_SHA256, MODEL_BYTES),
                ("tokens.txt", TOKENS_SHA256, TOKENS_BYTES),
            ],
            Self::Whisper(WhisperSize::Tiny) => &[
                (
                    "tiny-encoder.int8.onnx",
                    "d24fb083ae3b1041fc24e97971d60e280c9342201fbb67b0ab428a8b4a51a434",
                    12_937_772,
                ),
                (
                    "tiny-decoder.int8.onnx",
                    "d2fece8dd42771f1df975c6c0445770d0c292bf7547c2cae04a6c0cc57540925",
                    89_855_401,
                ),
                (
                    "tiny-tokens.txt",
                    "b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126",
                    816_730,
                ),
            ],
            Self::Whisper(WhisperSize::Base) => &[
                (
                    "base-encoder.int8.onnx",
                    "0b8fb1304b6109976038efff5ace81720e00386f3ff6b54ee8c75291ca0a1e11",
                    29_120_534,
                ),
                (
                    "base-decoder.int8.onnx",
                    "9759d217388a01b3a4c7c15533201067b48ae819c4daafc8624e64b9409dc02d",
                    130_672_026,
                ),
                (
                    "base-tokens.txt",
                    "b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126",
                    816_730,
                ),
            ],
            Self::Whisper(WhisperSize::Small) => &[
                (
                    "small-encoder.int8.onnx",
                    "4cbe7b22fa9026b843b60a68640c747de05bafb1a11b57edc0e66c232d9f33a9",
                    112_442_483,
                ),
                (
                    "small-decoder.int8.onnx",
                    "acad50b5c782696e91b55914cc5ab4f756f1532f76e22aa6fc615f39fb69a8ee",
                    262_226_114,
                ),
                (
                    "small-tokens.txt",
                    "b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126",
                    816_730,
                ),
            ],
            Self::Whisper(WhisperSize::Turbo) => &[
                (
                    "turbo-encoder.int8.onnx",
                    "b02dcdf54f348741e93fe732b67d933c8dcb6735655f710640143081db38878b",
                    674_716_297,
                ),
                (
                    "turbo-decoder.int8.onnx",
                    "20accd02388482eb3a46bd615631adfdc85e1eb2c7db9ea3f02a40ffe6b81547",
                    361_080_764,
                ),
                (
                    "turbo-tokens.txt",
                    "b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126",
                    816_730,
                ),
            ],
        }
    }

    pub fn total_bytes(&self) -> u64 {
        self.files().iter().map(|(_, _, size)| *size).sum()
    }
}

#[derive(Clone, Default, Debug)]
pub struct CancellationToken(Arc<AtomicBool>);
impl CancellationToken {
    pub fn new() -> Self {
        Self::default()
    }
    pub fn cancel(&self) {
        self.0.store(true, Ordering::Release);
    }
    pub fn is_cancelled(&self) -> bool {
        self.0.load(Ordering::Acquire)
    }
    pub(crate) fn check(&self) -> Result<()> {
        if self.is_cancelled() {
            bail!("Operation cancelled");
        }
        Ok(())
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ModelStore {
    directory: PathBuf,
    kind: ModelKind,
}
impl ModelStore {
    pub fn new(directory: PathBuf, kind: ModelKind) -> Self {
        Self { directory, kind }
    }
    pub fn sense_voice(directory: PathBuf) -> Self {
        Self::new(directory, ModelKind::SenseVoice)
    }
    pub fn directory(&self) -> &Path {
        &self.directory
    }
    pub fn kind(&self) -> ModelKind {
        self.kind
    }
    /// Fast settings-page readiness hint. Initialization still verifies hashes.
    pub fn is_installed(&self) -> bool {
        self.kind.files().iter().all(|(name, _, size)| {
            fs::metadata(self.directory.join(name)).is_ok_and(|m| m.is_file() && m.len() == *size)
        })
    }
    pub fn verify(&self) -> Result<()> {
        for (name, hash, size) in self.kind.files() {
            validate(
                &self.directory.join(name),
                hash,
                *size,
                &CancellationToken::new(),
                self.kind,
            )?;
        }
        Ok(())
    }
    /// Caller runs this on a worker only after an explicit download action.
    /// Files use pinned revision + length + SHA256 and atomic per-file publish.
    /// Cancellation is polled even while waiting for network data.
    pub fn download(&self, cancel: &CancellationToken, progress: impl Fn(f64)) -> Result<PathBuf> {
        cancel.check()?;
        fs::create_dir_all(&self.directory)?;
        let base_url = self.kind.base_url();
        let files = self.kind.files();
        let total = self.kind.total_bytes();
        tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()?
            .block_on(async {
                let client = reqwest::Client::builder()
                    .https_only(true)
                    .connect_timeout(Duration::from_secs(20))
                    .timeout(Duration::from_secs(900))
                    .build()?;
                let mut completed = 0;
                for (name, hash, size) in files {
                    cancel.check()?;
                    let target = self.directory.join(name);
                    if validate(&target, hash, *size, cancel, self.kind).is_ok() {
                        completed += size;
                        if total > 0 {
                            progress(completed as f64 / total as f64);
                        }
                        continue;
                    }
                    cancel.check()?;
                    let request = client.get(format!("{base_url}{name}")).send();
                    tokio::pin!(request);
                    let mut response = loop {
                        tokio::select! {
                            result = &mut request => break result?.error_for_status()?,
                            _ = tokio::time::sleep(Duration::from_millis(100)) => cancel.check()?,
                        }
                    };
                    let mut temp = tempfile::NamedTempFile::new_in(&self.directory)?;
                    let mut count = 0u64;
                    let mut digest = Sha256::new();
                    loop {
                        cancel.check()?;
                        let chunk = tokio::select! {
                            chunk = response.chunk() => chunk?,
                            _ = tokio::time::sleep(Duration::from_millis(100)) => continue,
                        };
                        let Some(chunk) = chunk else {
                            break;
                        };
                        count += chunk.len() as u64;
                        if count > *size {
                            bail!("Model download exceeds pinned size");
                        }
                        digest.update(&chunk);
                        temp.write_all(&chunk)?;
                        if total > 0 {
                            progress((completed + count) as f64 / total as f64);
                        }
                    }
                    check_digest(count, digest, hash, *size)?;
                    cancel.check()?;
                    temp.as_file().sync_all()?;
                    temp.persist(&target).map_err(|error| error.error)?;
                    completed += size;
                }
                Ok(self.directory.clone())
            })
    }
    pub fn import_from(
        &self,
        source: &Path,
        cancel: &CancellationToken,
        progress: impl Fn(f64),
    ) -> Result<PathBuf> {
        cancel.check()?;
        let files = self.kind.files();
        let total = self.kind.total_bytes();
        // Validate all sources before replacing any destination file.
        for (name, hash, size) in files {
            validate(&source.join(name), hash, *size, cancel, self.kind)?;
        }
        fs::create_dir_all(&self.directory)?;
        let mut completed = 0;
        for (name, hash, size) in files {
            cancel.check()?;
            let target = self.directory.join(name);
            if validate(&target, hash, *size, cancel, self.kind).is_ok() {
                completed += size;
                if total > 0 {
                    progress(completed as f64 / total as f64);
                }
                continue;
            }
            let mut input = File::open(source.join(name))?;
            let mut temp = tempfile::NamedTempFile::new_in(&self.directory)?;
            let mut count = 0;
            let mut digest = Sha256::new();
            let mut buffer = [0; 65536];
            loop {
                cancel.check()?;
                let length = input.read(&mut buffer)?;
                if length == 0 {
                    break;
                }
                count += length as u64;
                if count > *size {
                    bail!("Imported model exceeds pinned size");
                }
                digest.update(&buffer[..length]);
                temp.write_all(&buffer[..length])?;
                if total > 0 {
                    progress((completed + count) as f64 / total as f64);
                }
            }
            check_digest(count, digest, hash, *size)?;
            cancel.check()?;
            temp.as_file().sync_all()?;
            temp.persist(&target).map_err(|error| error.error)?;
            completed += size;
        }
        Ok(self.directory.clone())
    }
}

fn check_digest(count: u64, digest: Sha256, hash: &str, size: u64) -> Result<()> {
    if count != size {
        bail!("Model file size does not match pinned version");
    }
    if format!("{:x}", digest.finalize()) != hash {
        bail!("Model SHA256 does not match pinned version");
    }
    Ok(())
}

fn validate(
    path: &Path,
    hash: &str,
    size: u64,
    cancel: &CancellationToken,
    kind: ModelKind,
) -> Result<()> {
    cancel.check()?;
    let mut file = File::open(path).with_context(|| {
        format!(
            "{} model file missing ({}); download or import it in Settings",
            kind.display_name(),
            path.file_name()
                .and_then(|f| f.to_str())
                .unwrap_or_default()
        )
    })?;
    if file.metadata()?.len() != size {
        bail!("Model size does not match pinned version");
    }
    let mut digest = Sha256::new();
    let mut count = 0;
    let mut buffer = [0; 65536];
    loop {
        cancel.check()?;
        let length = file.read(&mut buffer)?;
        if length == 0 {
            break;
        }
        count += length as u64;
        digest.update(&buffer[..length]);
    }
    check_digest(count, digest, hash, size)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn invalid_import_preserves_existing_files() {
        let source = tempfile::tempdir().unwrap();
        let dest = tempfile::tempdir().unwrap();
        fs::write(dest.path().join("tokens.txt"), b"keep existing").unwrap();
        fs::write(source.path().join("model.int8.onnx"), b"invalid").unwrap();
        assert!(ModelStore::sense_voice(dest.path().into())
            .import_from(source.path(), &CancellationToken::new(), |_| {})
            .is_err());
        assert_eq!(
            fs::read(dest.path().join("tokens.txt")).unwrap(),
            b"keep existing"
        );
        assert_eq!(fs::read_dir(dest.path()).unwrap().count(), 1);
    }

    #[test]
    fn cancellation_prevents_any_download_or_directory_creation() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("unused");
        let cancel = CancellationToken::new();
        cancel.cancel();
        assert!(ModelStore::sense_voice(path.clone())
            .download(&cancel, |_| panic!("No progress expected"))
            .is_err());
        assert!(!path.exists());
    }

    #[test]
    fn hash_is_required_even_for_matching_size() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("small");
        fs::write(&path, b"wrong").unwrap();
        assert!(validate(
            &path,
            "bad",
            5,
            &CancellationToken::new(),
            ModelKind::SenseVoice
        )
        .is_err());
    }

    #[test]
    fn whisper_model_metadata_and_files_are_consistent() {
        for size in [
            WhisperSize::Tiny,
            WhisperSize::Base,
            WhisperSize::Small,
            WhisperSize::Turbo,
        ] {
            let kind = ModelKind::Whisper(size);
            assert!(kind.id().starts_with("whisper-"));
            assert!(kind.base_url().starts_with("https://huggingface.co/"));
            let files = kind.files();
            assert_eq!(
                files.len(),
                3,
                "Whisper must have encoder, decoder, and tokens"
            );
            let prefix = size.file_prefix();
            assert_eq!(files[0].0, format!("{prefix}-encoder.int8.onnx"));
            assert_eq!(files[1].0, format!("{prefix}-decoder.int8.onnx"));
            assert_eq!(files[2].0, format!("{prefix}-tokens.txt"));
            assert!(kind.total_bytes() > 0);
        }
    }
}
