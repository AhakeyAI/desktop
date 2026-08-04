//! BLE 扫描结果

use serde::{Deserialize, Serialize};

/// BLE 扫描发现的设备
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScanResult {
    /// MAC 地址,如 "DC:04:5A:93:DF:2C"
    pub address: String,
    /// 本地名称(可能为空,很多 BLE 设备不广播名称)
    pub name: String,
    /// 信号强度 dBm(越大越好,如 -42 比 -80 好)
    pub rssi: i8,
    /// 是否匹配 AhaKey 设备(通过 service UUID 或特征判断)
    pub matched_ahakey: bool,
}
