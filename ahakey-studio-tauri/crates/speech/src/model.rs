use crate::Result;
use anyhow::{bail, Context};
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
const BASE_URL: &str = "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/2365baeacb507f821a0c8120fcee3d484dba7a07/";
const FILES: [(&str, &str, u64); 2] = [
    ("model.int8.onnx", MODEL_SHA256, MODEL_BYTES),
    ("tokens.txt", TOKENS_SHA256, TOKENS_BYTES),
];

#[derive(Clone, Default)]
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

#[derive(Clone, Debug)]
pub struct ModelStore {
    directory: PathBuf,
}
impl ModelStore {
    pub fn new(directory: PathBuf) -> Self {
        Self { directory }
    }
    pub fn directory(&self) -> &Path {
        &self.directory
    }
    /// Fast settings-page readiness hint. Initialization still verifies hashes.
    pub fn is_installed(&self) -> bool {
        FILES.iter().all(|(name, _, size)| {
            fs::metadata(self.directory.join(name)).is_ok_and(|m| m.is_file() && m.len() == *size)
        })
    }
    pub fn verify(&self) -> Result<()> {
        for (name, hash, size) in FILES {
            validate(
                &self.directory.join(name),
                hash,
                size,
                &CancellationToken::new(),
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
                for (name, hash, size) in FILES {
                    cancel.check()?;
                    let target = self.directory.join(name);
                    if validate(&target, hash, size, cancel).is_ok() {
                        completed += size;
                        progress(completed as f64 / total() as f64);
                        continue;
                    }
                    cancel.check()?;
                    let request = client.get(format!("{BASE_URL}{name}")).send();
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
                        if count > size {
                            bail!("Model download exceeds pinned size");
                        }
                        digest.update(&chunk);
                        temp.write_all(&chunk)?;
                        progress((completed + count) as f64 / total() as f64);
                    }
                    check_digest(count, digest, hash, size)?;
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
        // Validate both sources before replacing any destination file.
        for (name, hash, size) in FILES {
            validate(&source.join(name), hash, size, cancel)?;
        }
        fs::create_dir_all(&self.directory)?;
        let mut completed = 0;
        for (name, hash, size) in FILES {
            cancel.check()?;
            let target = self.directory.join(name);
            if validate(&target, hash, size, cancel).is_ok() {
                completed += size;
                progress(completed as f64 / total() as f64);
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
                if count > size {
                    bail!("Imported model exceeds pinned size");
                }
                digest.update(&buffer[..length]);
                temp.write_all(&buffer[..length])?;
                progress((completed + count) as f64 / total() as f64);
            }
            check_digest(count, digest, hash, size)?;
            cancel.check()?;
            temp.as_file().sync_all()?;
            temp.persist(&target).map_err(|error| error.error)?;
            completed += size;
        }
        Ok(self.directory.clone())
    }
}
fn total() -> u64 {
    MODEL_BYTES + TOKENS_BYTES
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
fn validate(path: &Path, hash: &str, size: u64, cancel: &CancellationToken) -> Result<()> {
    cancel.check()?;
    let mut file =
        File::open(path).context("SenseVoice model missing; download or import it in Settings")?;
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
        assert!(ModelStore::new(dest.path().into())
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
        assert!(ModelStore::new(path.clone())
            .download(&cancel, |_| panic!("No progress expected"))
            .is_err());
        assert!(!path.exists());
    }
    #[test]
    fn hash_is_required_even_for_matching_size() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("small");
        fs::write(&path, b"wrong").unwrap();
        assert!(validate(&path, "bad", 5, &CancellationToken::new()).is_err());
    }
}
