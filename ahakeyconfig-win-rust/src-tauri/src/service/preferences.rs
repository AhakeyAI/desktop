//! 用户偏好服务
//!
//! 对应原 Java 项目的 `~/.ahakey/preferences.properties` 加载逻辑。

use std::collections::HashMap;
use std::path::PathBuf;

use crate::error::{AppError, AppResult};

pub struct PreferencesService {
    #[allow(dead_code)]
    path: PathBuf,
    cache: HashMap<String, String>,
}

impl PreferencesService {
    pub fn new() -> AppResult<Self> {
        let home = dirs::home_dir()
            .ok_or_else(|| AppError::Other("home dir not found".into()))?;
        let path = home.join(".ahakey").join("preferences.properties");
        let cache = if path.exists() {
            let content = std::fs::read_to_string(&path)?;
            Self::parse(&content)
        } else {
            HashMap::new()
        };
        Ok(Self { path, cache })
    }

    fn parse(content: &str) -> HashMap<String, String> {
        let mut map = HashMap::new();
        for line in content.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            if let Some((k, v)) = line.split_once('=') {
                map.insert(k.trim().to_string(), v.trim().to_string());
            }
        }
        map
    }

    pub fn get(&self, key: &str) -> Option<&String> {
        self.cache.get(key)
    }

    pub fn set(&mut self, key: &str, value: &str) -> AppResult<()> {
        self.cache.insert(key.to_string(), value.to_string());
        self.save()
    }

    pub fn save(&self) -> AppResult<()> {
        if let Some(parent) = self.path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let mut out = String::new();
        for (k, v) in &self.cache {
            out.push_str(&format!("{k}={v}\n"));
        }
        std::fs::write(&self.path, out)?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse() {
        let s = "lang=zh-CN\ndebug=true\n";
        let map = PreferencesService::parse(s);
        assert_eq!(map.get("lang"), Some(&"zh-CN".to_string()));
        assert_eq!(map.get("debug"), Some(&"true".to_string()));
    }
}

