//! Local slot notes are separate from the strict legacy voice/profile schema.
use std::{fs, path::Path};
pub fn validate(notes: &[String; 2]) -> Result<(), String> {
    if notes.iter().any(|s| {
        s.chars().count() > 32 || s.chars().any(|c| {
            c.is_control()
                || matches!(c,'\u{200e}'|'\u{200f}'|'\u{202a}'..='\u{202e}'|'\u{2066}'..='\u{2069}')
        })
    }) {
        return Err("槽位备注限 32 字符，不支持控制字符".into());
    }
    Ok(())
}
pub fn load(path: &Path) -> Result<[String; 2], String> {
    let bytes = match fs::read(path) {
        Ok(bytes) => bytes,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(Default::default()),
        Err(_) => return Err("备注文件读取失败，原文件已保留".into()),
    };
    if bytes.len() > 4096 {
        return Err("备注文件过大，原文件已保留".into());
    }
    let notes = serde_json::from_slice(&bytes).map_err(|_| "备注文件无效，原文件已保留")?;
    validate(&notes)?;
    Ok(notes)
}
pub fn save(path: &Path, notes: &[String; 2]) -> Result<(), String> {
    validate(notes)?;
    load(path)?; // Never overwrite unknown/corrupt content.
    let bytes = serde_json::to_vec_pretty(notes).map_err(|_| "备注编码失败")?;
    crate::settings::write_atomic(path, &bytes)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn notes_roundtrip_preserves_legacy_settings_and_rejects_bad_content() {
        let folder = tempfile::tempdir().unwrap();
        let settings = folder.path().join("settings.json");
        crate::settings::save(&settings, &Default::default()).unwrap();
        let before = fs::read(&settings).unwrap();
        let path = folder.path().join("host-notes.json");
        assert_eq!(load(&path).unwrap(), ["", ""]);
        let notes = ["办公电脑".into(), "MacBook".into()];
        save(&path, &notes).unwrap();
        assert_eq!(load(&path).unwrap(), notes);
        save(&path, &["新备注".into(), "".into()]).unwrap();
        assert_eq!(load(&path).unwrap(), ["新备注", ""]);
        assert_eq!(before, fs::read(&settings).unwrap());
        assert!(validate(&["x".repeat(33), "".into()]).is_err());
        assert!(validate(&["bad\u{202e}".into(), "".into()]).is_err());
        fs::write(&path, b"invalid").unwrap();
        assert!(save(&path, &notes).is_err());
        assert_eq!(fs::read(&path).unwrap(), b"invalid");
    }
}
