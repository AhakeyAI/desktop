use crate::CloudError;
use std::path::{Path, PathBuf};
use zeroize::Zeroizing;

/// Backend-only secret. Not serializable; Debug intentionally redacts it.
pub struct SecretToken(Zeroizing<String>);
impl std::fmt::Debug for SecretToken {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("SecretToken([REDACTED])")
    }
}
impl SecretToken {
    pub fn new(value: impl Into<String>) -> Result<Self, CloudError> {
        let value = Zeroizing::new(value.into());
        if value.is_empty() || value.len() > 8192 || !value.bytes().all(|b| b.is_ascii_graphic()) {
            return Err(CloudError::InvalidConfig);
        }
        Ok(Self(value))
    }
    pub(crate) fn expose(&self) -> &str {
        &self.0
    }
}

/// Windows encrypts a blob with current-user DPAPI; macOS uses Keychain and Linux
/// uses Secret Service. A locked/unavailable native store returns an error.
/// `directory` must be the application's private local data directory, not its executable directory.
#[derive(Clone)]
pub struct CredentialStore {
    directory: PathBuf,
}
impl CredentialStore {
    pub fn new(directory: impl AsRef<Path>) -> Self {
        Self {
            directory: directory.as_ref().to_owned(),
        }
    }
    pub fn has_token(&self) -> Result<bool, CloudError> {
        match self.load() {
            Ok(_) => Ok(true),
            Err(CloudError::MissingCredential) => Ok(false),
            Err(e) => Err(e),
        }
    }
    pub fn save(&self, token: &str) -> Result<(), CloudError> {
        let token = SecretToken::new(token.to_owned())?;
        platform::save(&self.directory, token.expose())
    }
    pub fn load(&self) -> Result<SecretToken, CloudError> {
        platform::load(&self.directory)
    }
    pub fn clear(&self) -> Result<(), CloudError> {
        platform::clear(&self.directory)
    }
}

#[cfg(windows)]
mod platform {
    use super::*;
    use std::{
        fs::{self, OpenOptions},
        io::{Read, Write},
    };
    use windows_sys::Win32::{
        Foundation::LocalFree,
        Security::Cryptography::{
            CryptProtectData, CryptUnprotectData, CRYPTPROTECT_UI_FORBIDDEN, CRYPT_INTEGER_BLOB,
        },
    };
    const FILE: &str = "doubao-token.dpapi";
    const MAX_BLOB: u64 = 65536;
    fn crypt(bytes: &[u8], protect: bool) -> Result<Zeroizing<Vec<u8>>, CloudError> {
        let input = CRYPT_INTEGER_BLOB {
            cbData: bytes.len() as u32,
            pbData: bytes.as_ptr() as *mut u8,
        };
        let mut output = CRYPT_INTEGER_BLOB {
            cbData: 0,
            pbData: std::ptr::null_mut(),
        };
        let ok = unsafe {
            if protect {
                CryptProtectData(
                    &input,
                    std::ptr::null(),
                    std::ptr::null(),
                    std::ptr::null(),
                    std::ptr::null(),
                    CRYPTPROTECT_UI_FORBIDDEN,
                    &mut output,
                )
            } else {
                CryptUnprotectData(
                    &input,
                    std::ptr::null_mut(),
                    std::ptr::null(),
                    std::ptr::null(),
                    std::ptr::null(),
                    CRYPTPROTECT_UI_FORBIDDEN,
                    &mut output,
                )
            }
        };
        if ok == 0 {
            return Err(CloudError::CredentialStore);
        }
        // DPAPI owns this allocation. Copy, wipe, then release on every successful call.
        let result = unsafe {
            let raw = std::slice::from_raw_parts_mut(output.pbData, output.cbData as usize);
            let copied = Zeroizing::new(raw.to_vec());
            zeroize::Zeroize::zeroize(raw);
            LocalFree(output.pbData as *mut _);
            copied
        };
        Ok(result)
    }
    pub fn save(directory: &Path, token: &str) -> Result<(), CloudError> {
        let encrypted = crypt(token.as_bytes(), true)?;
        fs::create_dir_all(directory).map_err(|_| CloudError::CredentialStore)?;
        let temporary = directory.join(format!("doubao-token-{}.tmp", uuid::Uuid::new_v4()));
        let result = (|| {
            let mut f = OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&temporary)
                .map_err(|_| CloudError::CredentialStore)?;
            f.write_all(&encrypted)
                .and_then(|_| f.sync_all())
                .map_err(|_| CloudError::CredentialStore)?;
            drop(f);
            fs::rename(&temporary, directory.join(FILE)).map_err(|_| CloudError::CredentialStore)
        })();
        if result.is_err() {
            let _ = fs::remove_file(&temporary);
        }
        result
    }
    pub fn load(directory: &Path) -> Result<SecretToken, CloudError> {
        let f = fs::File::open(directory.join(FILE)).map_err(|e| {
            if e.kind() == std::io::ErrorKind::NotFound {
                CloudError::MissingCredential
            } else {
                CloudError::CredentialStore
            }
        })?;
        let mut encrypted = Zeroizing::new(Vec::new());
        f.take(MAX_BLOB + 1)
            .read_to_end(&mut encrypted)
            .map_err(|_| CloudError::CredentialStore)?;
        if encrypted.len() > MAX_BLOB as usize {
            return Err(CloudError::CredentialStore);
        }
        let plaintext = crypt(&encrypted, false)?;
        let text = std::str::from_utf8(&plaintext).map_err(|_| CloudError::CredentialStore)?;
        SecretToken::new(text.to_owned()).map_err(|_| CloudError::CredentialStore)
    }
    pub fn clear(directory: &Path) -> Result<(), CloudError> {
        match fs::remove_file(directory.join(FILE)) {
            Ok(()) => Ok(()),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(_) => Err(CloudError::CredentialStore),
        }
    }
}

#[cfg(any(target_os = "macos", target_os = "linux"))]
mod platform {
    use super::*;
    fn entry() -> Result<keyring::Entry, CloudError> {
        keyring::Entry::new("AhaKey Studio", "doubao-access-token")
            .map_err(|_| CloudError::CredentialStore)
    }
    pub fn save(_: &Path, token: &str) -> Result<(), CloudError> {
        entry()?
            .set_password(token)
            .map_err(|_| CloudError::CredentialStore)
    }
    pub fn load(_: &Path) -> Result<SecretToken, CloudError> {
        let value = entry()?.get_password().map_err(|e| match e {
            keyring::Error::NoEntry => CloudError::MissingCredential,
            _ => CloudError::CredentialStore,
        })?;
        SecretToken::new(value).map_err(|_| CloudError::CredentialStore)
    }
    pub fn clear(_: &Path) -> Result<(), CloudError> {
        match entry()?.delete_credential() {
            Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
            Err(_) => Err(CloudError::CredentialStore),
        }
    }
}
#[cfg(not(any(windows, target_os = "macos", target_os = "linux")))]
mod platform {
    use super::*;
    pub fn save(_: &Path, _: &str) -> Result<(), CloudError> {
        Err(CloudError::CredentialStore)
    }
    pub fn load(_: &Path) -> Result<SecretToken, CloudError> {
        Err(CloudError::CredentialStore)
    }
    pub fn clear(_: &Path) -> Result<(), CloudError> {
        Err(CloudError::CredentialStore)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn secrets_are_redacted_and_headers_validated() {
        assert_eq!(
            format!("{:?}", SecretToken::new("fake-token").unwrap()),
            "SecretToken([REDACTED])"
        );
        assert!(SecretToken::new("token\r\nX-Evil: x").is_err());
    }
    #[cfg(windows)]
    #[test]
    fn real_dpapi_roundtrip_replacement_and_clear() {
        let dir = tempfile::tempdir().unwrap();
        let store = CredentialStore::new(dir.path());
        assert!(!store.has_token().unwrap());
        store.save("fake-isolated-test-token").unwrap();
        assert!(store.has_token().unwrap());
        assert_eq!(store.load().unwrap().expose(), "fake-isolated-test-token");
        let bytes = std::fs::read(dir.path().join("doubao-token.dpapi")).unwrap();
        assert!(!bytes
            .windows(b"fake-isolated-test-token".len())
            .any(|w| w == b"fake-isolated-test-token"));
        store.save("replacement-fake-token").unwrap();
        assert_eq!(store.load().unwrap().expose(), "replacement-fake-token");
        assert_eq!(std::fs::read_dir(dir.path()).unwrap().count(), 1);
        store.clear().unwrap();
        store.clear().unwrap();
        assert!(!store.has_token().unwrap());
    }
    #[cfg(windows)]
    #[test]
    fn corrupt_blob_does_not_fall_back_to_plaintext() {
        let dir = tempfile::tempdir().unwrap();
        let store = CredentialStore::new(dir.path());
        std::fs::write(
            dir.path().join("doubao-token.dpapi"),
            b"fake-plaintext-token",
        )
        .unwrap();
        assert_eq!(store.load().unwrap_err(), CloudError::CredentialStore);
    }
}
