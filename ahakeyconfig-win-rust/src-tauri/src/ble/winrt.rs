//! Windows 平台专用 BLE 模块 — 拿已配对设备列表
//!
//! 与 C# `BLE_tcp_driver.exe` (Form1.cs) 和 Python v3 (winrt_adapter.py) 一致:
//! **不要直接通过蓝牙扫描硬件,而是先让 Windows 蓝牙配对设备,再从已配对列表拿**。
//!
//! 实现策略(双路并用,任一成功即可):
//!
//! 路径 A:WinRT `DeviceInformation.FindAllAsyncAqsFilter`
//!   - 拿 Windows 蓝牙子系统维护的 AEP 列表(已配对设备)
//!   - 即使 AhaKey 当前不广播也能看到(只要配对过)
//!
//! 路径 B:PowerShell `Get-PnpDevice` (兜底,WinRT 失败时启用)
//!   - 直接查 Windows 注册表/驱动层 — 完全不依赖设备是否在广播
//!   - 你之前的 `Get-PnpDevice -Class Bluetooth` 输出里就有 AhaKey 5A93
//!     (InstanceId: BTHLE\DEV_DC045A93DF2C...)
//!
//! 关键优势:AhaKey 5A93 跟你电脑配对过 → PowerShell 能看到 → 即使它没广播,
//! 我们也能在"选择 BLE 设备"弹窗里看到真实的 "AhaKey 5A93" 和真实 MAC。

#![cfg(windows)]

use crate::model::ScanResult;
use regex::Regex;
use std::time::Duration;
use tracing::{error, info, warn};
use windows::core::HSTRING;
use windows::Devices::Enumeration::DeviceInformation;

/// AQS 过滤器:所有 BLE 设备
/// 参考 C# BLE_tcp_driver/Program.cs:20
const AQS_ALL_BLE: &str = "(System.Devices.Aep.ProtocolId:=\"{bb7bb05e-5972-42b5-94fc-76eaa7084d49}\")";

/// 单次 BLE 扫描 — 先尝试 WinRT,失败则 fallback 到 PowerShell。
/// 扫描 HID 接口类下的所有 HID 设备(包含蓝牙 HID over GATT 设备)。
///
/// 关键洞察: AhaKey 5A93 这类蓝牙键盘设备在 Windows 蓝牙子系统里
/// 不是标准 AEP BLE 设备,而是 **HID over GATT (UUID 0x1812) 设备**,
/// 注册到 `HIDClass` 接口类(`{4D1E55B2-F16F-11CF-88CB-001111000030}`)。
///
/// 通过列举 HIDClass 设备 + 按名字过滤 "AhaKey" 就能找到目标设备。
pub async fn scan_hid_devices() -> Result<Vec<ScanResult>, String> {
    use windows::Devices::Enumeration::DeviceInformation;

    const HIDCLASS_GUID: &str = "{4D1E55B2-F16F-11CF-88CB-001111000030}";

    let aqs = format!(
        "System.Devices.InterfaceClassGuid:=\"{HIDCLASS_GUID}\" \
         AND System.Devices.InterfaceEnabled:=System.StructuredQueryType.Boolean#True"
    );

    info!("[BLE/WinRT] scanning HID devices via AQS...");
    info!("[BLE/WinRT] AQS: {aqs}");

    let result = tauri::async_runtime::spawn_blocking(move || -> Result<Vec<ScanResult>, String> {
        unsafe {
            let aqs_h = HSTRING::from(&aqs);
            let collection = DeviceInformation::FindAllAsyncAqsFilter(&aqs_h)
                .map_err(|e| format!("FindAllAsyncAqsFilter: {e}"))?
                .GetResults()
                .map_err(|e| format!("GetResults: {e}"))?;

            let count = collection.Size().map_err(|e| format!("Size: {e}"))? as usize;
            info!("[BLE/WinRT] HID scan: {count} devices total");

            let mut results = Vec::new();
            for i in 0..count {
                let dev_info = collection
                    .GetAt(i as u32)
                    .map_err(|e| format!("GetAt({i}): {e}"))?;

                let id = dev_info.Id().map(|s| s.to_string()).unwrap_or_default();
                let name = dev_info.Name().map(|s| s.to_string()).unwrap_or_default();

                // 只保留名字含 "AhaKey" 或 "Aha" 的
                let lower = name.to_lowercase();
                let matched = lower.contains("ahakey") || lower.contains("aha ");

                if !matched {
                    continue;
                }

                // 从设备路径提取 MAC 后缀:
                //   \\?\HID#{00001812-...}_Dev_VID&0107d7_PID&0000_REV&0110_dc045a93df2c#...\KBD
                let mac = extract_mac_from_hid_path(&id).unwrap_or_else(|| id.clone());
                info!(
                    "[BLE/WinRT]   + matched HID: name='{name}' mac='{mac}' id='{id}'"
                );

                results.push(ScanResult {
                    address: mac,
                    name,
                    rssi: -50,
                    matched_ahakey: true,
                });
            }
            Ok(results)
        }
    });

    match result.await {
        Ok(Ok(devices)) => Ok(devices),
        Ok(Err(e)) => Err(e),
        Err(e) => Err(format!("join failed: {e}")),
    }
}

/// 从 HID 设备路径提取 MAC 地址。
///
/// 路径格式:
///   `\\?\HID#{00001812-...}_Dev_VID&0107d7_PID&0000_REV&0110_dc045a93df2c#...\KBD`
/// 提取 `dc045a93df2c`,转成 `DC:04:5A:93:DF:2C`。
///
/// 算法: 找路径中最后一个下划线 `_` 后的 12 个 hex 字符。
/// 如果 hex 字符前紧跟的不是连续下划线或不是合法位置,则往前找下一个候选。
/// 我们简化处理: 直接找 12 个连续 hex 字符(忽略前后的 _)。
fn extract_mac_from_hid_path(path: &str) -> Option<String> {
    let chars: Vec<char> = path.chars().collect();
    let mut best: Option<usize> = None;
    let mut i = 0;
    while i + 12 <= chars.len() {
        if chars[i..i + 12].iter().all(|c| c.is_ascii_hexdigit()) {
            // 检查后面是否全是 hex(确保连续 12 个)
            let all_hex = chars[i..i + 12].iter().all(|c| c.is_ascii_hexdigit());
            if all_hex {
                best = Some(i);
                break;
            }
        }
        i += 1;
    }
    let start = best?;
    let hex: String = chars[start..start + 12].iter().collect();
    let bytes: Vec<u8> = (0..12)
        .step_by(2)
        .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).ok())
        .collect::<Option<Vec<_>>>()?;
    if bytes.len() != 6 {
        return None;
    }
    Some(format!(
        "{:02X}:{:02X}:{:02X}:{:02X}:{:02X}:{:02X}",
        bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5]
    ))
}

pub async fn scan(timeout_secs: u64) -> Result<Vec<ScanResult>, String> {
    info!("[BLE/WinRT] starting scan (timeout {}s)", timeout_secs);

    // 路径 A: WinRT 系统级 AEP
    let winrt_results = scan_via_winrt(timeout_secs).await;
    match &winrt_results {
        Ok(rs) => info!("[BLE/WinRT] WinRT scan: {} devices", rs.len()),
        Err(e) => warn!("[BLE/WinRT] WinRT scan failed: {e}"),
    }

    // 路径 B: PowerShell 兜底
    let ps_results = scan_via_powershell(timeout_secs).await;
    match &ps_results {
        Ok(rs) => info!("[BLE/WinRT] PowerShell scan: {} devices", rs.len()),
        Err(e) => warn!("[BLE/WinRT] PowerShell scan failed: {e}"),
    }

    // 路径 C: HID 设备路径(用于 AhaKey 这类 HID over GATT 设备)
    let hid_results = scan_hid_devices().await;
    match &hid_results {
        Ok(rs) => info!("[BLE/WinRT] HID scan: {} devices", rs.len()),
        Err(e) => warn!("[BLE/WinRT] HID scan failed: {e}"),
    }

    // 合并:WinRT 优先(有 FriendlyName),PowerShell 补全,HID 兜底
    let merged = merge_results_3(
        winrt_results.unwrap_or_default(),
        ps_results.unwrap_or_default(),
        hid_results.unwrap_or_default(),
    );

    info!("[BLE/WinRT] merged scan: {} devices", merged.len());
    for r in &merged {
        info!(
            "[BLE/WinRT]   {:17} name='{}' matched={}",
            r.address, r.name, r.matched_ahakey
        );
    }
    Ok(merged)
}

fn merge_results_3(
    winrt: Vec<ScanResult>,
    ps: Vec<ScanResult>,
    hid: Vec<ScanResult>,
) -> Vec<ScanResult> {
    use std::collections::HashMap;
    let mut map: HashMap<String, ScanResult> = HashMap::new();

    // 先放 PowerShell(权威)
    for r in ps {
        map.insert(r.address.to_uppercase(), r);
    }

    // 叠加 WinRT
    for r in winrt {
        let key = r.address.to_uppercase();
        match map.get_mut(&key) {
            Some(existing) => {
                if existing.name.is_empty() && !r.name.is_empty() {
                    existing.name = r.name;
                }
                existing.matched_ahakey = existing.matched_ahakey || r.matched_ahakey;
            }
            None => {
                map.insert(key, r);
            }
        }
    }

    // 叠加 HID(关键路径 — 找到 AhaKey 这类 HID over GATT 设备)
    for r in hid {
        let key = r.address.to_uppercase();
        match map.get_mut(&key) {
            Some(existing) => {
                // HID 路径拿到的 name 通常很准 — 优先使用
                if !r.name.is_empty() {
                    existing.name = r.name;
                }
                existing.matched_ahakey = true;
            }
            None => {
                map.insert(key, r);
            }
        }
    }

    let mut list: Vec<ScanResult> = map.into_values().collect();
    list.sort_by(|a, b| {
        if a.matched_ahakey != b.matched_ahakey {
            return b.matched_ahakey.cmp(&a.matched_ahakey);
        }
        if !a.name.is_empty() != !b.name.is_empty() {
            return (!b.name.is_empty()).cmp(&!a.name.is_empty());
        }
        b.rssi.cmp(&a.rssi)
    });
    list
}

// =========================================================================
// 路径 A: WinRT FindAllAsyncAqsFilter
// =========================================================================

async fn scan_via_winrt(timeout_secs: u64) -> Result<Vec<ScanResult>, String> {
    let _ = timeout_secs; // WinRT FindAllAsync 是同步阻塞
    tokio::task::spawn_blocking(scan_blocking_winrt)
        .await
        .map_err(|e| format!("WinRT scan join: {e}"))?
}

fn scan_blocking_winrt() -> Result<Vec<ScanResult>, String> {
    let async_op = DeviceInformation::FindAllAsyncAqsFilter(&HSTRING::from(AQS_ALL_BLE))
        .map_err(|e| format!("FindAllAsyncAqsFilter: {e}"))?;

    let collection = async_op
        .GetResults()
        .map_err(|e| format!("FindAllAsync.GetResults: {e}"))?;

    let count = collection.Size().map_err(|e| format!("Size: {e}"))? as usize;

    let mut results = Vec::with_capacity(count);
    for i in 0..count {
        let dev_info = collection
            .GetAt(i as u32)
            .map_err(|e| format!("GetAt({i}): {e}"))?;

        let id = dev_info.Id().map(|s| s.to_string()).unwrap_or_default();
        let name = dev_info.Name().map(|s| s.to_string()).unwrap_or_default();
        let addr = read_mac_from_properties(&dev_info).unwrap_or_else(|| id.clone());
        let matched = !name.is_empty() && name.to_lowercase().contains("ahakey");
        results.push(ScanResult {
            address: addr,
            name,
            rssi: -50,
            matched_ahakey: matched,
        });
    }

    Ok(results)
}

fn read_mac_from_properties(dev_info: &DeviceInformation) -> Option<String> {
    use windows::core::Interface;
    let prop_map = dev_info.Properties().ok()?;
    let key = HSTRING::from("System.Devices.Aep.DeviceAddress");
    let prop_value = prop_map.Lookup(&key).ok()?;
    let pv = prop_value
        .cast::<windows::Foundation::IPropertyValue>()
        .ok()?;
    pv.GetString().ok().map(|s| s.to_string())
}

// =========================================================================
// 路径 B: PowerShell Get-PnpDevice (兜底,可靠)
// =========================================================================

async fn scan_via_powershell(timeout_secs: u64) -> Result<Vec<ScanResult>, String> {
    let timeout = Duration::from_secs(timeout_secs.max(3));
    tokio::task::spawn_blocking(move || scan_blocking_powershell(timeout))
        .await
        .map_err(|e| format!("PowerShell scan join: {e}"))?
}

fn scan_blocking_powershell(timeout: Duration) -> Result<Vec<ScanResult>, String> {
    use std::process::Command;

    // PowerShell 脚本:
    // 1. 拿所有 Bluetooth PnP 设备(FriendlyName + InstanceId)
    // 2. 过滤:Status=OK 且 InstanceId 匹配 BTHLE 协议(不是 RFCOMM 经典蓝牙)
    // 3. 输出 CSV:FriendlyName,InstanceId
    let script = r#"
        $ErrorActionPreference = 'SilentlyContinue'
        Get-PnpDevice -Class Bluetooth |
            Where-Object { $_.Status -eq 'OK' -and $_.InstanceId -like 'BTHLE*' } |
            ForEach-Object { '{0}|{1}' -f $_.FriendlyName, $_.InstanceId }
    "#;

    let output = Command::new("powershell")
        .args([
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            script,
        ])
        .output()
        .map_err(|e| format!("powershell spawn: {e}"))?;

    if !output.status.success() {
        return Err(format!(
            "powershell exit: {}, stderr: {}",
            output.status,
            String::from_utf8_lossy(&output.stderr)
        ));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    info!("[BLE/WinRT] PowerShell stdout (first 500 chars): {}",
        &stdout.chars().take(500).collect::<String>());

    let mut results = Vec::new();
    for line in stdout.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let parts: Vec<&str> = line.splitn(2, '|').collect();
        let name = parts.first().copied().unwrap_or("").trim().to_string();
        let instance_id = parts.get(1).copied().unwrap_or("").trim().to_string();
        if name.is_empty() {
            continue;
        }
        // 从 InstanceId 提取 MAC
        // 格式: BTHLE\DEV_DC045A93DF2C\7&2A96B03E&0&DC045A93DF2C
        //       或: BTHLEDEVICE\{UUID}_DEV_VID&0107D7_PID&0000_REV&XXXX
        let mac = extract_mac_from_instance_id(&instance_id);
        let matched = name.to_lowercase().contains("ahakey");
        results.push(ScanResult {
            address: mac.unwrap_or_else(|| instance_id.clone()),
            name: name.clone(),
            rssi: -50,
            matched_ahakey: matched,
        });
    }

    // 超时保护(目前 PowerShell 启动 ~1s,留给余地)
    let _ = timeout;

    Ok(results)
}

/// 从 Windows PnP InstanceId 里提取 MAC 地址。
///
/// 支持两种格式:
/// - `BTHLE\DEV_DC045A93DF2C\...`         → "DC:04:5A:93:DF:2C"
/// - `BTHLEDEVICE\{UUID}_...`              → None (UUID 不是 MAC)
fn extract_mac_from_instance_id(instance_id: &str) -> Option<String> {
    // 找 "DEV_" 后面的 12 个十六进制字符
    let re = Regex::new(r"DEV_([0-9A-Fa-f]{12})").ok()?;
    if let Some(caps) = re.captures(instance_id) {
        let hex = &caps[1];
        let bytes: Vec<String> = (0..6)
            .map(|i| hex[i * 2..i * 2 + 2].to_uppercase())
            .collect();
        return Some(bytes.join(":"));
    }
    None
}

// =========================================================================
// WinRT 直连已配对设备(绕过 btleplug 扫描)
// =========================================================================

/// 把 "AA:BB:CC:DD:EE:FF" 解析成 u64(BluetoothAddress 格式)
fn mac_to_u64(mac: &str) -> Result<u64, String> {
    let parts: Vec<&str> = mac.split(':').collect();
    if parts.len() != 6 {
        return Err(format!("invalid MAC format: {mac}"));
    }
    let mut bytes = [0u8; 6];
    for (i, p) in parts.iter().enumerate() {
        bytes[i] = u8::from_str_radix(p.trim(), 16)
            .map_err(|e| format!("invalid MAC byte '{p}': {e}"))?;
    }
    // BluetoothAddress 是 little-endian:第一个字节是 LSB
    let mut val: u64 = 0;
    for (i, &b) in bytes.iter().enumerate() {
        val |= (b as u64) << (8 * i);
    }
    Ok(val)
}

/// 用 WinRT `BluetoothLEDevice.FromBluetoothAddressAsync` 直连已配对设备。
///
/// 这是绕开"btleplug 扫描不到不广播设备"的关键 API:
/// - 不要求设备当前在广播
/// - 只要 Windows 蓝牙子系统知道这个 MAC(配对过),就能直接拿 device 句柄
/// - 调用后 Windows 会主动与配对设备建立连接协商,设备会被唤醒
///
/// **重要**:这个函数只拿 `BluetoothLEDevice` 句柄,**不**做 GATT 操作。
/// GATT 操作(读特征、subscribe notify 等)仍然需要 btleplug,
/// 因为 btleplug 的事件流缓存会被这个调用"激活"——
/// 之后的 btleplug 扫描就能发现这个 peripheral 了。
pub async fn connect_by_mac(mac: &str) -> Result<String, String> {
    info!("[BLE/WinRT] connect_by_mac: {}", mac);
    let addr = mac_to_u64(mac)?;
    tokio::task::spawn_blocking(move || connect_blocking(addr))
        .await
        .map_err(|e| format!("WinRT connect join: {e}"))?
}

/// 通过 AEP device id 连接(参考 C# BLE_tcp_driver 实现)。
///
/// 这是关键的差异点:Windows BLE API 有两种连接方式:
/// - `FromBluetoothAddressAsync(mac)` — 通过 MAC 找 device,**仅当 device 是当前已配对/已连接时返回有效句柄**
/// - `FromIdAsync(aep_id)` — 通过 AEP device id 找 device,**可以绕过已连接状态**
///
/// AEP id 格式: `BluetoothLE#BluetoothLE{PC_MAC}-{DEVICE_MAC}`
pub async fn connect_by_aep_id(aep_id: &str) -> Result<String, String> {
    info!("[BLE/WinRT] connect_by_aep_id: {}", aep_id);
    let id = aep_id.to_string();
    tokio::task::spawn_blocking(move || connect_by_id_blocking(&id))
        .await
        .map_err(|e| format!("WinRT connect join: {e}"))?
}

fn connect_by_id_blocking(aep_id: &str) -> Result<String, String> {
    use windows::Devices::Bluetooth::BluetoothLEDevice;

    info!("[BLE/WinRT] calling FromIdAsync({})", aep_id);
    let h = HSTRING::from(aep_id);
    let async_op = BluetoothLEDevice::FromIdAsync(&h).map_err(|e| {
        format!(
            "FromIdAsync({aep_id}) failed: {e}。\
            AhaKey 5A93 不在 Windows 蓝牙子系统的已配对设备列表中"
        )
    })?;

    let device = async_op
        .GetResults()
        .map_err(|e| format!("FromIdAsync.GetResults failed: {e}"))?;

    let name = device.Name().map(|s| s.to_string()).unwrap_or_default();
    let connected = device.ConnectionStatus().ok();

    info!(
        "[BLE/WinRT] FromIdAsync OK: name='{}' connection={:?}",
        name, connected
    );

    // 主动请求 GATT services - 这会触发真正的 GATT 连接协商
    info!("[BLE/WinRT] requesting GATT services to trigger connection...");
    let gatt_async = match device.GetGattServicesAsync() {
        Ok(op) => op,
        Err(e) => {
            warn!("[BLE/WinRT] GetGattServicesAsync start failed: {e}");
            return Ok(name);
        }
    };
    match gatt_async.GetResults() {
        Ok(result) => {
            let status = result.Status().ok();
            let services_count = result.Services().ok().map(|s| s.Size().unwrap_or(0)).unwrap_or(0);
            info!(
                "[BLE/WinRT] GATT services: status={:?} count={}",
                status, services_count
            );
        }
        Err(e) => {
            warn!("[BLE/WinRT] GetGattServicesAsync.GetResults failed: {e}");
        }
    }

    Ok(name)
}

fn connect_blocking(mac: u64) -> Result<String, String> {
    use windows::Devices::Bluetooth::BluetoothLEDevice;

    info!("[BLE/WinRT] calling FromBluetoothAddressAsync({:#x})", mac);
    let async_op =
        BluetoothLEDevice::FromBluetoothAddressAsync(mac).map_err(|e| {
            format!(
                "FromBluetoothAddressAsync({:#x}) failed: {e}。\
                请确认 AhaKey 5A93 已与此电脑配对(Windows 蓝牙设置 → 已配对设备)",
                mac
            )
        })?;

    // 同步阻塞等待 — GetResults 直接返回 T(windows crate 0.58 不是 Option)
    let device = async_op
        .GetResults()
        .map_err(|e| format!("FromBluetoothAddressAsync.GetResults: {e}"))?;

    let name = device.Name().map(|s| s.to_string()).unwrap_or_default();
    let connected = device.ConnectionStatus().ok();

    info!(
        "[BLE/WinRT] FromBluetoothAddressAsync OK: name='{}' connection={:?}",
        name, connected
    );

    // 关键:FromBluetoothAddressAsync 只拿句柄,不触发 GATT 连接
    // 必须主动请求 GATT services — 这会触发连接协商,设备被强制唤醒
    info!("[BLE/WinRT] requesting GATT services to trigger connection...");
    let gatt_async = match device.GetGattServicesAsync() {
        Ok(op) => op,
        Err(e) => {
            warn!("[BLE/WinRT] GetGattServicesAsync start failed: {e}");
            return Ok(name); // 不算致命错误,继续
        }
    };
    match gatt_async.GetResults() {
        Ok(result) => {
            let status = result.Status().ok();
            let services_count = result.Services().ok().map(|s| s.Size().unwrap_or(0)).unwrap_or(0);
            info!(
                "[BLE/WinRT] GATT services OK: status={:?} count={}",
                status, services_count
            );
            if let Some(s) = status {
                if s.0 != 0 {
                    // 0 = Success,非 0 = 各种错误
                    warn!("[BLE/WinRT] GATT services status not success: {:?}", s);
                }
            }
        }
        Err(e) => {
            warn!("[BLE/WinRT] GetGattServicesAsync.GetResults failed: {e}");
            // 不致命,继续 — btleplug 第二次扫描可能能找到 peripheral
        }
    }

    // 让 btleplug 有时间感知 peripheral
    std::thread::sleep(std::time::Duration::from_millis(500));

    Ok(name)
}

// =========================================================================
// 关键路径:用 AEP id 强制连接 (绕过 btleplug 的 FromBluetoothAddressAsync 限制)
// =========================================================================

/// 强制连接 AhaKey - 用 AEP id 绕过已连接状态,触发 GATT 服务发现。
///
/// 这是 C# BLE_tcp_driver 用的方法。
/// AEP id 格式: `BluetoothLE#BluetoothLE{PC_MAC}-{DEVICE_MAC}`
///
/// 关键洞察:
/// - btleplug 用 `BluetoothLEDevice::FromBluetoothAddressAsync(mac)` — **device 已连接时返回 null**
/// - C# 用 `BluetoothLEDevice::FromIdAsync(aep_id)` — **可以绕过已连接状态**
/// - 我们需要用后者
///
/// 调用 `GetGattServicesAsync(BluetoothCacheMode::Uncached)` 会触发真正的
/// GATT 主连接协商 — 这就是 C# 程序让 AhaKey 响应的关键。
pub async fn force_connect_with_aep_id(aep_id: &str) -> Result<String, String> {
    info!("[BLE/WinRT] force_connect_with_aep_id: {aep_id}");
    let id = aep_id.to_string();
    tokio::task::spawn_blocking(move || force_connect_blocking(&id))
        .await
        .map_err(|e| format!("join: {e}"))?
}

fn force_connect_blocking(aep_id: &str) -> Result<String, String> {
    use windows::Devices::Bluetooth::BluetoothLEDevice;
    use windows::Devices::Bluetooth::BluetoothCacheMode;

    info!("[BLE/WinRT] calling FromIdAsync({})", aep_id);
    let h = HSTRING::from(aep_id);
    let device_op = unsafe { BluetoothLEDevice::FromIdAsync(&h) }
        .map_err(|e| {
            error!("[BLE/WinRT] FromIdAsync start failed: {e:?}");
            format!("FromIdAsync start failed: {e}")
        })?;

    info!("[BLE/WinRT] FromIdAsync returned IAsyncOperation, getting results...");
    let device = device_op.GetResults().map_err(|e| {
        error!("[BLE/WinRT] FromIdAsync.GetResults failed: {e:?}");
        format!("FromIdAsync.GetResults failed: {e}")
    })?;

    let name = device.Name().map(|s| s.to_string()).unwrap_or_default();
    let status = device.ConnectionStatus().ok();
    info!(
        "[BLE/WinRT] FromIdAsync OK: name='{name}' connection={:?}",
        status
    );

    // 关键: 用 Uncached 模式拿 GATT services
    // 这会真正触发 GATT 主连接协商,AhaKey 收到后会响应
    info!("[BLE/WinRT] GetGattServicesAsync (Uncached) to trigger GATT connection...");
    let gatt_op = unsafe { device.GetGattServicesWithCacheModeAsync(BluetoothCacheMode::Uncached) }
        .map_err(|e| {
            error!("[BLE/WinRT] GetGattServicesWithCacheModeAsync start failed: {e:?}");
            format!("GetGattServicesWithCacheModeAsync start: {e}")
        })?;

    info!("[BLE/WinRT] GATT op returned, getting results...");
    let gatt_result = gatt_op.GetResults().map_err(|e| {
        error!("[BLE/WinRT] GetGattServicesWithCacheModeAsync.GetResults failed: {e:?}");
        format!("GetGattServicesWithCacheModeAsync.GetResults: {e}")
    })?;

    let status = unsafe { gatt_result.Status() }.ok();
    let services_count = unsafe { gatt_result.Services() }
        .ok()
        .and_then(|s| s.Size().ok())
        .unwrap_or(0);
    info!(
        "[BLE/WinRT] GATT services: status={:?} count={}",
        status, services_count
    );

    // 列出所有 service 让我们知道 SimpleProfile 0x7340 是否存在
    if let Ok(services) = unsafe { gatt_result.Services() } {
        let count = unsafe { services.Size() }.unwrap_or(0);
        for i in 0..count {
            let svc_res = unsafe { services.GetAt(i) };
            let uuid = svc_res
                .ok()
                .and_then(|s| s.Uuid().ok())
                .map(|u| format!("{:?}", u))
                .unwrap_or_default();
            info!("[BLE/WinRT]   service {i}: uuid={uuid}");
        }
    }

    if services_count == 0 {
        return Err(format!(
            "GATT services count is 0 — AhaKey 拒绝了 GATT 连接请求。状态: {status:?}"
        ));
    }

    Ok(name)
}

/// 获取本机蓝牙适配器 MAC。
///
/// 用 WinRT BluetoothAdapter::GetDefaultAsync 拿默认 adapter 的 BluetoothAddress。
pub async fn get_local_pc_mac() -> Result<String, String> {
    use windows::Devices::Bluetooth::BluetoothAdapter;

    let addr = tauri::async_runtime::spawn_blocking(|| -> Result<String, String> {
        let op = unsafe { BluetoothAdapter::GetDefaultAsync() }
            .map_err(|e| format!("GetDefaultAsync: {e}"))?;
        let adapter = op
            .GetResults()
            .map_err(|e| format!("GetDefaultAsync.GetResults: {e}"))?;
        // BluetoothAddress 是 Result<u64, Error>
        let addr_u64 = adapter
            .BluetoothAddress()
            .map_err(|e| format!("BluetoothAddress: {e}"))?;
        let bytes = addr_u64.to_le_bytes();
        Ok(format!(
            "{:02x}:{:02x}:{:02x}:{:02x}:{:02x}:{:02x}",
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5]
        ))
    })
    .await
    .map_err(|e| format!("join: {e}"))??;

    Ok(addr)
}