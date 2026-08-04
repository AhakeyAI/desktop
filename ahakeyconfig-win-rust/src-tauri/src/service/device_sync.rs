//! 设备配置同步服务

use serde::{Deserialize, Serialize};
use std::path::PathBuf;

use crate::error::AppResult;
use crate::model::ModeSlot;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceSnapshot {
    pub slot: ModeSlot,
    pub version: u32,
    pub timestamp: i64,
}

pub struct DeviceSyncService {
    #[allow(dead_code)]
    config_path: PathBuf,
}

impl DeviceSyncService {
    pub fn new(config_path: PathBuf) -> Self {
        Self { config_path }
    }

    /// 加载本地配置
    pub fn load(&self) -> AppResult<DeviceSnapshot> {
        if !self.config_path.exists() {
            return Ok(DeviceSnapshot {
                slot: ModeSlot::default(),
                version: 0,
                timestamp: 0,
            });
        }
        let bytes = std::fs::read(&self.config_path)?;
        let snapshot: DeviceSnapshot = serde_json::from_slice(&bytes)?;
        Ok(snapshot)
    }

    /// 保存配置
    pub fn save(&self, snapshot: &DeviceSnapshot) -> AppResult<()> {
        if let Some(parent) = self.config_path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let bytes = serde_json::to_vec_pretty(snapshot)?;
        std::fs::write(&self.config_path, bytes)?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_roundtrip() {
        let dir = tempdir();
        let path = dir.join("config.json");
        let s = DeviceSyncService::new(path.clone());
        let snapshot = DeviceSnapshot {
            slot: ModeSlot::default(),
            version: 1,
            timestamp: 1234567890,
        };
        s.save(&snapshot).unwrap();
        let loaded = s.load().unwrap();
        assert_eq!(loaded.version, 1);
    }

    fn tempdir() -> PathBuf {
        let mut p = std::env::temp_dir();
        p.push(format!("ahakey-test-{}", uuid::Uuid::new_v4()));
        p
    }
}

