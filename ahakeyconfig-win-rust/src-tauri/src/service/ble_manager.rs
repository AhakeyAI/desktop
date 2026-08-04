//! BLE 管理服务(包装 ble::BleManager)

use std::sync::Arc;

use parking_lot::Mutex;
use tracing::info;

use crate::ble::BleManager;
use crate::error::AppResult;
use crate::model::DeviceStatus;

/// BLE 管理服务
pub struct BleManagerService {
    pub manager: Arc<BleManager>,
    #[allow(dead_code)]
    pub state: Arc<Mutex<DeviceStatus>>,
}

impl BleManagerService {
    pub fn new() -> Self {
        let manager = Arc::new(BleManager::new());
        let state = Arc::new(Mutex::new(DeviceStatus::default()));
        // 启动心跳
        manager.start_heartbeat();
        Self { manager, state }
    }

    pub async fn scan(&self) -> AppResult<Vec<String>> {
        self.manager.start_scan().await
    }

    pub async fn connect(&self, address: &str) -> AppResult<()> {
        self.manager.connect(address).await?;
        let status = self.manager.status();
        *self.state.lock() = status;
        info!("connected to {address}");
        Ok(())
    }

    pub async fn disconnect(&self) -> AppResult<()> {
        self.manager.disconnect().await?;
        *self.state.lock() = self.manager.status();
        Ok(())
    }

    pub fn status(&self) -> DeviceStatus {
        self.state.lock().clone()
    }

    pub async fn force_cleanup(&self) {
        self.manager.force_cleanup().await;
    }
}

impl Default for BleManagerService {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new() {
        let s = BleManagerService::new();
        assert!(!s.status().connected);
    }
}

