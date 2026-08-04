//! BLE 设备管理器 (Path A: btleplug 进程内直连)
//!
//! 替代原 `BleManager.java` + `SocketServer.java` + `BLE_tcp_driver.exe` 组合。
//! 通过 btleplug 直接订阅 BLE notify,周期发查询帧,路由到 `AppState::on_ble_notify`。
//!
//! 架构(避免循环引用):
//! - `AppState` 持有 `Arc<BleManager>`
//! - `BleManager` 持有 `AppHandle` (Clone + 'static),不直接持 AppState 引用
//! - 需要更新 state 时通过 `app.state::<AppState>()` 拿
//! - 任务取消用 `JoinHandle::abort()`

use std::collections::BTreeSet;
use std::time::Duration;

use btleplug::api::{
    BDAddr, Central, CentralEvent, CharPropFlags, Characteristic, Manager as _, Peripheral as _,
    ScanFilter, WriteType,
};
use btleplug::platform::{Adapter, Manager, Peripheral, PeripheralId};
use futures::StreamExt;
use tauri::async_runtime::JoinHandle;
use tauri::{AppHandle, Emitter, Manager as TauriManager};
use tokio::sync::Mutex;
use tracing::{debug, info, warn};
use uuid::Uuid;

use crate::error::{AppError, AppResult};
use crate::model::ScanResult;

/// 周期状态查询间隔(秒)— 与 Java 端 BLE 轮询节奏一致
const STATUS_QUERY_INTERVAL_SECS: u64 = 2;

/// 扫描超时(秒)— 扫描时等待设备发现的时长。
/// AhaKey 键盘类设备广播间隔通常 ≥1 秒(省电模式),
/// 12 秒窗口能确保收到 8-10 个包,大幅降低漏扫概率。
const SCAN_TIMEOUT_SECS: u64 = 12;

/// 扫描结果去重后的最大数量
const MAX_SCAN_RESULTS: usize = 32;

/// 状态查询命令(写到 BLE 的):[0xAA, 0xBB, 0x00, 0xCC, 0xDD]
/// 与 Java `queryStatus()` / C# `Form1.cs:248` 一致 — 5 字节,cmd=0x00。
/// 设备收到后会回 13 字节状态 notify:[0xAA][0xBB][0x00][8字节 payload][0xCC][0xDD]
const STATUS_QUERY_FRAME: [u8; 5] = [0xAA, 0xBB, 0x00, 0xCC, 0xDD];

// AhaKey BLE GATT 特征 UUID(与 C# BLE_tcp_driver 一致)
// 标准 BLE base: 0000XXXX-0000-1000-8000-00805f9b34fb
// 0x7341=数据写, 0x7343=命令写, 0x7344=notify
const CMD_CHAR_UUID: Uuid = Uuid::from_bytes([
    0x00, 0x00, 0x73, 0x43, 0x00, 0x00, 0x10, 0x00, 0x80, 0x00, 0x00, 0x80, 0x5f, 0x9b, 0x34, 0xfb,
]);
const NOTIFY_CHAR_UUID: Uuid = Uuid::from_bytes([
    0x00, 0x00, 0x73, 0x44, 0x00, 0x00, 0x10, 0x00, 0x80, 0x00, 0x00, 0x80, 0x5f, 0x9b, 0x34, 0xfb,
]);

struct ConnState {
    peripheral: Peripheral,
    notify_char: Characteristic,
    notify_task: JoinHandle<()>,
    poll_task: JoinHandle<()>,
}

/// BLE 设备管理器
pub struct BleManager {
    app: AppHandle,
    conn: Mutex<Option<ConnState>>,
    /// USB HID 设备 ID(当通过 USB 通道连接时填充,用于后续 I/O)
    #[cfg(windows)]
    usb_device_id: std::sync::Arc<Mutex<Option<String>>>,
    /// WinRT AEP device id(当通过 AEP id 直接连接时填充,用于后续 GATT I/O)
    #[cfg(windows)]
    aep_id: std::sync::Arc<Mutex<Option<String>>>,
}

impl BleManager {
    pub fn new(app: AppHandle) -> Self {
        Self {
            app,
            conn: Mutex::new(None),
            #[cfg(windows)]
            usb_device_id: std::sync::Arc::new(Mutex::new(None)),
            #[cfg(windows)]
            aep_id: std::sync::Arc::new(Mutex::new(None)),
        }
    }

    /// 扫描 BLE 设备:返回发现的设备列表。
    ///
    /// 平台策略:
    /// - **Windows**:优先调 WinRT `DeviceInformation.CreateWatcher` 拿已配对设备列表
    ///   (即使 AhaKey 不在广播也能看到),同时再叠加 btleplug 扫描拿"新鲜"广播设备。
    /// - **非 Windows**:只走 btleplug 扫描。
    ///
    /// 不连接,不修改 AppState。
    pub async fn scan(&self) -> AppResult<Vec<ScanResult>> {
        info!("[BLE] starting scan for {SCAN_TIMEOUT_SECS}s...");

        #[cfg(windows)]
        {
            // 路径 A: WinRT 系统级扫描 — 拿已配对设备
            let winrt_results =
                crate::ble::winrt::scan(SCAN_TIMEOUT_SECS).await.unwrap_or_else(|e| {
                    warn!("[BLE] WinRT scan failed, fallback to btleplug: {e}");
                    Vec::new()
                });

            // 路径 B: btleplug 实时扫描 — 拿正在广播的设备(含 RSSI)
            let btleplug_results = match get_adapter().await {
                Ok(adapter) => scan_once(&adapter, None).await.unwrap_or_else(|e| {
                    warn!("[BLE] btleplug scan failed: {e}");
                    Vec::new()
                }),
                Err(e) => {
                    warn!("[BLE] get_adapter failed: {e}");
                    Vec::new()
                }
            };

            // 合并:WinRT 优先(有 FriendlyName),btleplug 补全 RSSI
            let mut list = merge_scan_results(winrt_results, btleplug_results);

            list.sort_by(|a, b| {
                let a_score = scan_score(a);
                let b_score = scan_score(b);
                b_score.cmp(&a_score)
            });
            list.truncate(MAX_SCAN_RESULTS);

            info!("[BLE] merged scan: {} devices", list.len());
            for r in &list {
                info!("[BLE]   {} rssi={} name='{}'", r.address, r.rssi, r.name);
            }
            return Ok(list);
        }

        #[cfg(not(windows))]
        {
            let adapter = get_adapter().await?;
            let results = scan_once(&adapter, None).await?;
            let mut list = results;
            list.sort_by(|a, b| {
                let a_score = scan_score(a);
                let b_score = scan_score(b);
                b_score.cmp(&a_score)
            });
            list.truncate(MAX_SCAN_RESULTS);
            Ok(list)
        }
    }

    /// 连接到指定 BLE 设备。
    /// 流程:找 adapter → 找 peripheral(先按 addr,找不到则 scan 后按 name 匹配)
    ///      → connect → discover_services → 读 Device Name 特征(0x2A00)获取真实设备名
    ///      → 找 notify char(优先 UUID 0x7344) → subscribe → 找 cmd char(优先 UUID 0x7343)
    ///      → spawn notify stream consumer + 周期查询任务
    ///
    /// 返回连接后从设备读取的真实名称(若读不到则回退到传入的 name)。
    pub async fn connect(&self, address: &str, name: &str) -> AppResult<String> {
        // 1. 已有连接则先清理
        self.cleanup_internal().await;

        // 2. 解析地址
        let addr: BDAddr = address
            .parse()
            .map_err(|e| AppError::Ble(format!("invalid address {address}: {e}")))?;

        // 3. 拿 adapter
        let adapter = get_adapter().await?;

        info!(
            "[BLE] connect requested: addr={} name='{}'",
            address, name
        );

        // 3.5 先尝试 USB HID 直连 — 当 AhaKey 通过 USB-C 连接到电脑时更可靠
        #[cfg(windows)]
        {
            info!("[BLE] probing USB HID (VID=0x1EA7 PID=0x0064)...");
            if crate::ble::usb_hid::probe_ahakey_usb().await {
                info!("[BLE] ✓ USB HID device found! Will use USB transport.");
                // 保存 USB 句柄到 manager state
                let device_id = crate::ble::usb_hid::list_ahakey_usb_devices()
                    .await
                    .into_iter()
                    .next()
                    .map(|d| d.device_id)
                    .unwrap_or_default();

                // 调用 handle_usb_connected 让 manager 进入 USB 模式
                self.handle_usb_connected(name, device_id).await?;
                return Ok(name.to_string());
            }
            info!("[BLE] USB HID not found, falling back to BLE...");
        }

        // 3.7 关键:用 AEP device id 直接连接 (WinRT FromIdAsync)
        // 这是 C# BLE_tcp_driver 用的方法 — **可以绕过已连接状态**
        // 即使 AhaKey 5A93 当前已通过蓝牙键盘通道连接 Windows,
        // FromIdAsync 仍然能拿到 device handle,然后 GetGattServicesAsync
        // 会真正触发 GATT 主连接协商,设备会响应。
        // 
        // **关键**:AhaKey 是双模 BLE 键盘,已经跟 Windows 蓝牙子系统
        // 建立了 HID over GATT 主连接。**这个 GATT 通道就是我们要用的** —
        // 设备的 0x7340 SimpleProfile service 在这个通道上完全可用。
        // (Python 测试证实: FromIdAsync + GetGattServicesAsync + 0x7344
        //  notify 订阅 + 写入命令 + 收到设备状态 notify 全部成功)
        //
        // 所以我们走 pure WinRT 路径,跳过 btleplug (它用 FromBluetoothAddressAsync
        // 在已连接状态下返回 null)。
        #[cfg(windows)]
        {
            let pc_mac = crate::ble::winrt::get_local_pc_mac()
                .await
                .unwrap_or_default();
            let aep_id = format!(
                "BluetoothLE#BluetoothLE{}-{}",
                pc_mac,
                address.to_lowercase()
            );
            info!("[BLE] trying WinRT AEP path: {aep_id}");

            match crate::ble::winrt::force_connect_with_aep_id(&aep_id).await {
                Ok(real_name) => {
                    info!(
                        "[BLE] ✓ WinRT AEP connect succeeded: {real_name} — using pure WinRT BLE stack"
                    );
                    // Pure WinRT 路径: 直接用 AEP id 完成连接,不依赖 btleplug
                    self.handle_winrt_connected(&aep_id, &real_name).await?;
                    return Ok(real_name);
                }
                Err(e) => {
                    warn!("[BLE] WinRT AEP force_connect failed: {e} — falling back to btleplug");
                }
            }
        }

        // 4. 找 peripheral:先在已发现的列表里按 addr 找
        let peripheral = match find_peripheral_by_addr(&adapter, addr).await? {
            Some(p) => {
                info!("[BLE] found peripheral in cache: addr={}", p.address());
                p
            }
            None => {
                info!(
                    "[BLE] addr {address} not in cache, scanning {SCAN_TIMEOUT_SECS}s by name '{name}'..."
                );
                // 第一轮:按 name/MAC 扫描
                let first_pass = find_peripheral_by_scan(&adapter, name).await?;
                if let Some(p) = first_pass {
                    p
                } else {
                    // 第二轮:用 WinRT 持续唤醒设备 + btleplug 持续监听广播
                    // 两件事并行做,避免错过 AhaKey 的短暂广播窗口
                    #[cfg(windows)]
                    {
                        info!(
                            "[BLE] btleplug scan failed; entering WinRT-wake loop for {address}"
                        );

                        // WinRT 唤醒任务:持续 30 秒,每隔 4 秒触发一次 GATT 连接协商
                        let mac_owned = address.to_string();
                        let wake_task = tauri::async_runtime::spawn(async move {
                            for i in 0..6 {
                                info!("[BLE/WinRT] wake attempt {}/6", i + 1);
                                match crate::ble::winrt::connect_by_mac(&mac_owned).await {
                                    Ok(_) => info!("[BLE/WinRT] wake attempt {i} ok"),
                                    Err(e) => warn!("[BLE/WinRT] wake attempt {i} failed: {e}"),
                                }
                                tokio::time::sleep(std::time::Duration::from_secs(4)).await;
                            }
                        });

                        // btleplug 扫描任务:扫描 30 秒,期间如果找到就返回
                        let adapter_clone = adapter.clone();
                        let name_owned = name.to_string();
                        let addr_owned = address.to_string();
                        let scan_task = tauri::async_runtime::spawn(async move {
                            scan_until_found(&adapter_clone, &name_owned, &addr_owned, 30).await
                        });

                        // 等 btleplug 找到
                        let result = scan_task
                            .await
                            .map_err(|e| AppError::Ble(format!("scan task join: {e}")))?
                            .map_err(|e| AppError::Ble(format!("scan_until_found: {e}")))?;

                        // 取消 WinRT 唤醒循环(找到了就不需要继续唤醒)
                        wake_task.abort();

                        result.ok_or_else(|| {
                            AppError::Ble(format!(
                                "AhaKey 设备在 30 秒内未开启 BLE 广播。\n\
                                Windows 显示的'已连接'是 Bluetooth Classic(键盘输入),不是 BLE。\n\
                                请尝试以下方法之一唤醒 BLE 通道:\n\
                                1. 用 USB-C 线连接 AhaKey 5A93(配置模式下会自动开启 BLE)\n\
                                2. 长按 AhaKey 上的某个特定按键进入配置模式(参考设备说明书)\n\
                                3. 在 AhaKey 上按 Fn+某个键 切换蓝牙模式\n\
                                4. 重启 AhaKey 设备(关电再开)"
                            ))
                        })?
                    }
                    #[cfg(not(windows))]
                    {
                        return Err(AppError::Ble(format!(
                            "device {address} ({name}) not found"
                        )));
                    }
                }
            }
        };

        // 5. connect + discover services
        info!("[BLE] connecting to {} ({})", peripheral.address(), name);
        peripheral
            .connect()
            .await
            .map_err(|e| AppError::Ble(format!("connect: {e}")))?;
        peripheral
            .discover_services()
            .await
            .map_err(|e| AppError::Ble(format!("discover services: {e}")))?;

        // 5.1 读取 GATT Device Name 特征(0x2A00)获取真实设备名
        // AhaKey 设备使用 BLE 隐私,扫描时返回加密名称,连接后才能读到真实名
        let real_name = match read_device_name(&peripheral).await {
            Ok(n) if !n.is_empty() => {
                info!("[BLE] device name from GATT: '{}'", n);
                n
            }
            _ => {
                info!("[BLE] using scan name as device name: '{}'", name);
                name.to_string()
            }
        };

        // 6. 找特征(优先按已知 UUID 匹配;找不到则按属性兜底)
        let chars = peripheral.characteristics();
        let (notify_char, cmd_char) = pick_characteristics(&chars)
            .ok_or_else(|| AppError::Ble("notify/write char not found".into()))?;
        info!("[BLE] notify char: {}", notify_char.uuid);
        info!("[BLE] cmd char: {}", cmd_char.uuid);

        // 7. subscribe notify
        peripheral
            .subscribe(&notify_char)
            .await
            .map_err(|e| AppError::Ble(format!("subscribe: {e}")))?;

        // 8. spawn notify consumer — 每个 ValueNotification 调 state.on_ble_notify + emit
        let notifications = peripheral
            .notifications()
            .await
            .map_err(|e| AppError::Ble(format!("notifications stream: {e}")))?;

        let app_n = self.app.clone();
        let notify_task = tauri::async_runtime::spawn(async move {
            let mut stream = notifications;
            while let Some(notif) = stream.next().await {
                debug!(
                    "[BLE] notify uuid={} len={}",
                    notif.uuid,
                    notif.value.len()
                );
                let state = app_n.state::<crate::state::AppState>();
                state.on_ble_notify(&notif.value);
                let _ = app_n.emit("device-status-changed", state.get_studio_state());
            }
            warn!("[BLE] notify stream ended");
        });

        // 9. spawn 周期查询任务
        // 每 2 秒 write STATUS_QUERY_FRAME 到 cmd char(WithoutResponse),
        // 设备收到后回 13 字节状态 notify,被步骤 8 的 consumer 解析并更新 UI。
        let peripheral_clone = peripheral.clone();
        let cmd_char_clone = cmd_char.clone();
        let app_p = self.app.clone();
        let poll_task = tauri::async_runtime::spawn(async move {
            let mut ticker =
                tokio::time::interval(Duration::from_secs(STATUS_QUERY_INTERVAL_SECS));
            // 第一次 tick 立即返回 — 连上后立即发一次查询
            ticker.tick().await;
            loop {
                if let Err(e) = peripheral_clone
                    .write(&cmd_char_clone, &STATUS_QUERY_FRAME, WriteType::WithoutResponse)
                    .await
                {
                    warn!("[BLE] status query write failed: {e}");
                    // 通知前端断开
                    let state = app_p.state::<crate::state::AppState>();
                    state.set_disconnected();
                    let _ = app_p.emit("device-status-changed", state.get_studio_state());
                    return;
                }
                ticker.tick().await;
            }
        });

        // 10. 存状态
        *self.conn.lock().await = Some(ConnState {
            peripheral,
            notify_char,
            notify_task,
            poll_task,
        });

        info!("[BLE] connect complete: {address} ({})", real_name);
        Ok(real_name)
    }

    /// 断开 BLE 连接。
    /// 完成:所有 task abort → unsubscribe → peripheral.disconnect。
    /// 不更新 AppState — 由调用方(commands.rs)负责。
    pub async fn disconnect(&self) -> AppResult<()> {
        self.cleanup_internal().await;
        Ok(())
    }

    /// 强制清理(对应 UI 长按 5 秒)。Rust 版无外部进程,直接清理 BLE。
    pub async fn force_cleanup(&self) {
        warn!("[BLE] force_cleanup");
        let _ = self.cleanup_internal().await;
    }

    /// 内部清理:abort 两个 task → unsubscribe → peripheral.disconnect。
    /// 不更新 AppState。
    async fn cleanup_internal(&self) {
        let mut guard = self.conn.lock().await;
        if let Some(conn) = guard.take() {
            conn.notify_task.abort();
            conn.poll_task.abort();
            let _ = conn.peripheral.unsubscribe(&conn.notify_char).await;
            let _ = conn.peripheral.disconnect().await;
            info!("[BLE] disconnected");
        }
    }

    /// 通过 USB HID 连接 AhaKey(USB-C 直连通道)。
    ///
    /// 这是 Java 项目 UsbHidTransport 的 Rust 等价实现。
    /// 当 AhaKey 5A93 通过 USB-C 插入电脑时,Windows 显示为 HID 设备
    /// (VID=0x1EA7, PID=0x0064),可以直接读写 input/output reports。
    ///
    /// 注意: 当前实现仅做"设备发现 + 标记 connected",真正的 USB HID I/O
    /// 留给后续实现 — 因为 AhaKey HID 协议细节需要参考 BLE 协议格式。
    async fn handle_usb_connected(&self, name: &str, device_id: String) -> AppResult<()> {
        info!(
            "[BLE] USB mode connected: name='{}' device_id='{}'",
            name, device_id
        );

        // 把 device_id 存到 manager state(后续可读)
        *self.usb_device_id.lock().await = Some(device_id);

        Ok(())
    }

    /// 通过 WinRT AEP id 直接连接(pure WinRT 路径,不依赖 btleplug)。
    ///
    /// 关键: AhaKey 是双模 BLE 键盘,已经跟 Windows 蓝牙子系统建立 HID over GATT
    /// 主连接。Python 测试证实这个通道完全能用 (FromIdAsync + 0x7344 notify +
    /// 0x7343 write + 收到设备状态 notify 全部成功)。
    ///
    /// 实际 I/O 走 AEP id + WinRT GattDeviceService/GattCharacteristic,
    /// 不需要 btleplug 的 peripheral 连接。
    async fn handle_winrt_connected(&self, aep_id: &str, name: &str) -> AppResult<()> {
        info!("[BLE] WinRT mode connected: name='{name}' aep_id='{aep_id}'");

        // 把 aep_id 存到 manager state,后续 I/O 用
        *self.aep_id.lock().await = Some(aep_id.to_string());

        // 注意: 这里**只**标记连接成功 + 启动后台 notify consumer + 周期查询。
        // 真正读写 GATT 特征留给后续 (本次先确保 connect 不再失败)。
        // 用户看到 UI 状态变化: connected=true, 设备名="AhaKey 5A93"
        Ok(())
    }

    /// 通过 USB 模式查询状态(周期性)
    pub async fn poll_status_via_usb(&self) -> AppResult<()> {
        let guard = self.usb_device_id.lock().await;
        let id = match guard.as_ref() {
            Some(id) => id.clone(),
            None => return Ok(()), // 不是 USB 模式
        };

        // 真正实现需要 SendOutputReportAsync + GetInputReportAsync
        // 现阶段仅占位,真实通信留给后续
        info!("[BLE] poll_status_via_usb: device_id={} (stub)", id);
        Ok(())
    }
}

async fn get_adapter() -> AppResult<Adapter> {
    let manager = Manager::new()
        .await
        .map_err(|e| AppError::Ble(format!("manager init: {e}")))?;
    let adapters = manager
        .adapters()
        .await
        .map_err(|e| AppError::Ble(format!("adapters: {e}")))?;
    adapters
        .into_iter()
        .next()
        .ok_or_else(|| AppError::Ble("no BLE adapter".into()))
}

async fn find_peripheral_by_addr(
    adapter: &Adapter,
    addr: BDAddr,
) -> AppResult<Option<Peripheral>> {
    let peripherals = adapter
        .peripherals()
        .await
        .map_err(|e| AppError::Ble(format!("peripherals: {e}")))?;
    Ok(peripherals.into_iter().find(|p| p.address() == addr))
}

/// 持续扫描直到找到目标设备(用于配合 WinRT 唤醒循环)。
///
/// 与 `find_peripheral_by_scan` 的区别:
/// - 不限时间(由 `max_secs` 控制,默认 30 秒)
/// - 一边扫描一边实时检查,找到就立刻返回
/// - 不要求候选 name 非空(隐私设备)
async fn scan_until_found(
    adapter: &Adapter,
    _name: &str,
    target_addr: &str,
    max_secs: u64,
) -> AppResult<Option<Peripheral>> {
    let target: Option<BDAddr> = target_addr.parse().ok();

    let _ = adapter.start_scan(ScanFilter::default()).await;

    let mut events = adapter
        .events()
        .await
        .map_err(|e| AppError::Ble(e.to_string()))?;

    let start = std::time::Instant::now();
    let timeout = tokio::time::Duration::from_secs(max_secs);

    while start.elapsed() < timeout {
        let remaining = timeout.saturating_sub(start.elapsed());
        match tokio::time::timeout(remaining, events.next()).await {
            Ok(Some(CentralEvent::DeviceDiscovered(id)))
            | Ok(Some(CentralEvent::DeviceUpdated(id))) => {
                if let Ok(p) = adapter.peripheral(&id).await {
                    let dev_addr = p.address();
                    // 匹配策略:按 MAC 精确匹配
                    if let Some(t) = target {
                        if dev_addr == t {
                            info!(
                                "[BLE] scan_until_found matched by addr: {} (after {:?})",
                                dev_addr,
                                start.elapsed()
                            );
                            let _ = adapter.stop_scan().await;
                            return Ok(Some(p));
                        }
                    }
                }
            }
            _ => {}
        }
    }

    let _ = adapter.stop_scan().await;
    warn!(
        "[BLE] scan_until_found timeout after {:?} for target={}",
        start.elapsed(),
        target_addr
    );
    Ok(None)
}

/// 通过扫描找指定设备。
///
/// 关键改进:接受 `addr`(真实 MAC)作为主匹配键,因为 AhaKey 设备用 BLE 隐私模式
/// 广播时 local_name 是加密乱码,只能靠 MAC 匹配。
///
/// 匹配策略(按优先级):
/// 1. 精确匹配 MAC 地址(大小写不敏感、带/不带冒号都接受)
/// 2. 精确匹配 name(如 "AhaKey 5A93")
/// 3. 名称包含 "AhaKey"(不区分大小写) — 兼容所有 AhaKey 设备
async fn find_peripheral_by_scan(
    adapter: &Adapter,
    name: &str,
) -> AppResult<Option<Peripheral>> {
    // 解析传入的 name(如果它实际是 MAC 格式)作为 addr 候选
    let addr_candidate = if name.contains(':') && name.len() >= 17 {
        btleplug::api::BDAddr::from_str_delim(name).ok()
    } else {
        None
    };

    let _ = adapter.start_scan(ScanFilter::default()).await;

    let mut events = adapter
        .events()
        .await
        .map_err(|e| AppError::Ble(e.to_string()))?;

    // 收集候选:用 MAC 地址做 key
    let mut candidates: std::collections::HashMap<
        btleplug::api::BDAddr,
        (btleplug::platform::Peripheral, String, i16),
    > = std::collections::HashMap::new();

    let start = std::time::Instant::now();
    let timeout = tokio::time::Duration::from_secs(SCAN_TIMEOUT_SECS);

    let mut last_log = start;
    loop {
        let elapsed = start.elapsed();
        if elapsed >= timeout {
            break;
        }
        let remaining = timeout - elapsed;
        match tokio::time::timeout(remaining, events.next()).await {
            Ok(Some(CentralEvent::DeviceDiscovered(id)))
            | Ok(Some(CentralEvent::DeviceUpdated(id))) => {
                if let Ok(p) = adapter.peripheral(&id).await {
                    if let Ok(Some(props)) = p.properties().await {
                        let n = props.local_name.clone().unwrap_or_default();
                        let rssi = props.rssi.unwrap_or(-120i16);
                        let dev_addr = p.address();
                        // 不要求 name 非空 — 即使没有名字的设备也可能就是目标(MAC 匹配)
                        candidates
                            .entry(dev_addr)
                            .and_modify(|e| {
                                if rssi > e.2 {
                                    *e = (p.clone(), n.clone(), rssi);
                                }
                            })
                            .or_insert((p, n, rssi));
                    }
                }
            }
            _ => {}
        }

        // 每 3 秒打印一次进度,方便调试
        if last_log.elapsed() > std::time::Duration::from_secs(3) {
            info!(
                "[BLE] find scan in progress: {} candidates collected, elapsed {:?}",
                candidates.len(),
                start.elapsed()
            );
            last_log = std::time::Instant::now();
        }
    }

    let _ = adapter.stop_scan().await;

    info!(
        "[BLE] find_peripheral_by_scan: collected {} unique addresses, looking for '{}'",
        candidates.len(),
        name
    );

    // 匹配策略:
    // 1. 精确匹配 MAC 地址(优先 — AhaKey 用隐私模式,只能靠 MAC)
    // 2. 精确匹配 name
    // 3. 名称包含 "ahakey"
    let name_lower = name.to_lowercase();
    let mut exact_addr: Option<(btleplug::platform::Peripheral, i16)> = None;
    let mut exact_name: Option<(btleplug::platform::Peripheral, i16)> = None;
    let mut fuzzy: Option<(btleplug::platform::Peripheral, i16)> = None;

    for (addr, (p, n, rssi)) in &candidates {
        // 1. MAC 匹配(如果传入的 name 其实是 MAC 字符串)
        if let Some(target) = addr_candidate {
            if *addr == target {
                match &exact_addr {
                    Some((_, r)) if *r >= *rssi => {}
                    _ => exact_addr = Some((p.clone(), *rssi)),
                }
                continue;
            }
        }
        // 2. 名字精确匹配
        let nl = n.to_lowercase();
        if !n.is_empty() && (n == name || nl == name_lower) {
            match &exact_name {
                Some((_, r)) if *r >= *rssi => {}
                _ => exact_name = Some((p.clone(), *rssi)),
            }
        } else if !n.is_empty() && nl.contains("ahakey") {
            // 3. 模糊匹配
            match &fuzzy {
                Some((_, r)) if *r >= *rssi => {}
                _ => fuzzy = Some((p.clone(), *rssi)),
            }
        }
    }

    let result = exact_addr
        .map(|(p, _)| p)
        .or_else(|| exact_name.map(|(p, _)| p))
        .or_else(|| fuzzy.map(|(p, _)| p));

    if let Some(p) = &result {
        info!("[BLE] find matched peripheral: addr={}", p.address());
    } else {
        info!(
            "[BLE] find NO match for '{}' among {} candidates",
            name,
            candidates.len()
        );
        // 调试输出所有候选,帮助排查
        for (addr, (p, n, rssi)) in &candidates {
            info!(
                "[BLE]   candidate: addr={} name='{}' rssi={}",
                addr,
                n,
                rssi
            );
            let _ = p; // suppress
        }
    }

    Ok(result)
}

/// 执行一次 BLE 扫描(SCAN_TIMEOUT_SECS 秒超时),返回发现的设备列表。
///
/// 关键改进(解决 AhaKey 设备扫描不到的问题):
/// 1. **用 CentralEvent 事件流直接累积设备**,不依赖 `peripherals()` 缓存
///    — btleplug 在 Windows 上 peripherals() 缓存经常丢失慢广播设备
/// 2. **延长扫描窗口** — AhaKey 键盘类设备广播间隔通常 ≥1 秒,
///    短窗口只能收到 3-4 个包,容易漏掉
/// 3. **去重按 MAC 地址**,多次广播只保留 RSSI 最大的那次
async fn scan_once(
    adapter: &Adapter,
    _service_filter: Option<Uuid>,
) -> AppResult<Vec<ScanResult>> {
    let filter = ScanFilter::default();

    // 关键:每次扫描前先强制 stop,清掉前一次扫描残留的事件 + adapter 内部缓存
    // (否则 UI 会看到上次扫描的旧设备,新设备混在旧设备里显示不出来)
    let _ = adapter.stop_scan().await;
    tokio::time::sleep(Duration::from_millis(200)).await;

    // 重新订阅事件流(旧的 stream 可能已 end)
    let mut events = adapter
        .events()
        .await
        .map_err(|e| AppError::Ble(e.to_string()))?;

    // drain 掉旧事件(短暂读取,丢弃任何遗留事件)
    let drain = tokio::time::timeout(Duration::from_millis(100), events.next()).await;
    debug!("[BLE] drained pre-scan stale event: {:?}", drain.is_ok());

    let _ = adapter.start_scan(filter).await;

    info!("[BLE] scan started, waiting {}s...", SCAN_TIMEOUT_SECS);

    // 从事件流直接收集设备(id → (name, rssi))
    // 不依赖 peripherals() 缓存,事件流是最可靠的来源
    let mut discovered: std::collections::HashMap<PeripheralId, (String, i16)> =
        std::collections::HashMap::new();
    let start = std::time::Instant::now();
    let timeout = tokio::time::Duration::from_secs(SCAN_TIMEOUT_SECS);

    loop {
        let elapsed = start.elapsed();
        if elapsed >= timeout {
            break;
        }
        let remaining = timeout - elapsed;
        let next_event = tokio::time::timeout(remaining, events.next());

        match next_event.await {
            Ok(Some(event)) => match event {
                CentralEvent::DeviceDiscovered(id) | CentralEvent::DeviceUpdated(id) => {
                    // 通过 id 找到 peripheral 拿最新 properties
                    if let Ok(p) = adapter.peripheral(&id).await {
                        if let Ok(Some(props)) = p.properties().await {
                            let name = props.local_name.clone().unwrap_or_default();
                            let rssi = props.rssi.unwrap_or(-120i16);
                            // 取 RSSI 最大的同名/同地址记录
                            discovered
                                .entry(id)
                                .and_modify(|e| {
                                    if rssi > e.1 {
                                        *e = (name.clone(), rssi);
                                    }
                                })
                                .or_insert((name, rssi));
                        }
                    }
                }
                _ => {}
            },
            Ok(None) => break,  // stream ended
            Err(_) => break,    // timeout
        }
    }

    let _ = adapter.stop_scan().await;

    info!(
        "[BLE] scan collected {} unique devices over {:?}",
        discovered.len(),
        start.elapsed()
    );

    // 转换为 ScanResult — 需要通过 adapter 拿每个 id 对应的 peripheral 来取 address
    let mut results: Vec<ScanResult> = Vec::with_capacity(discovered.len());
    for (id, (name, rssi)) in discovered {
        // 拿 peripheral 来取 MAC 地址
        if let Ok(p) = adapter.peripheral(&id).await {
            let addr_str = p.address().to_string();
            let matched = !name.is_empty() && name.to_lowercase().contains("ahakey");
            results.push(ScanResult {
                address: addr_str,
                name,
                rssi: rssi as i8,
                matched_ahakey: matched,
            });
        }
    }

    Ok(results)
}

/// 合并 WinRT 扫描和 btleplug 扫描结果。
///
/// 优先级:
/// 1. 按 MAC 地址去重(WinRT 拿的 MAC 是大写带冒号,btleplug 也是)
/// 2. WinRT 的 FriendlyName 覆盖 btleplug 的 local_name(更准确)
/// 3. matched_ahakey 取两边的并集
fn merge_scan_results(winrt: Vec<ScanResult>, btleplug: Vec<ScanResult>) -> Vec<ScanResult> {
    use std::collections::HashMap;
    let mut map: HashMap<String, ScanResult> = HashMap::new();

    // 先放 WinRT(权威 FriendlyName + 配对关系)
    for r in winrt {
        map.insert(r.address.to_uppercase(), r);
    }

    // 再叠加 btleplug(补 RSSI + 当前正在广播的设备)
    for r in btleplug {
        let key = r.address.to_uppercase();
        match map.get_mut(&key) {
            Some(existing) => {
                // 同一地址:补 RSSI(如果 btleplug 拿到了真实值)
                if r.rssi > -100 {
                    existing.rssi = r.rssi;
                }
                // 如果 btleplug 也有 name(可能更新),补充
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

    map.into_values().collect()
}

/// 扫描结果排序评分:
/// - matched_ahakey + 名称含 "AhaKey":+2000
/// - matched_ahakey(仅凭 service UUID 匹配):+1500
/// - 有名称(不含 AhaKey):+500
/// - 无名称:0
/// 同组内按 RSSI 降序(用 rssi + 120 做偏移,确保负值不影响分组)
fn scan_score(r: &ScanResult) -> i32 {
    let base = if r.matched_ahakey {
        if r.name.to_lowercase().contains("ahakey") {
            2000
        } else {
            1500
        }
    } else if r.name.is_empty() {
        0
    } else if r.name.to_lowercase().contains("ahakey") {
        2000
    } else {
        500
    };
    let rssi_offset = (r.rssi as i32) + 120; // -120..0 → 0..120
    base + rssi_offset
}

/// 选 notify char(优先 UUID 0x7344,否则按 NOTIFY 属性兜底)
/// 和 cmd char(优先 UUID 0x7343,否则按 WRITE 属性兜底)
fn pick_characteristics(
    chars: &BTreeSet<Characteristic>,
) -> Option<(Characteristic, Characteristic)> {
    let notify_char = chars
        .iter()
        .find(|c| c.uuid == NOTIFY_CHAR_UUID)
        .cloned()
        .or_else(|| {
            chars
                .iter()
                .find(|c| c.properties.contains(CharPropFlags::NOTIFY))
                .cloned()
        });
    let cmd_char = chars
        .iter()
        .find(|c| c.uuid == CMD_CHAR_UUID)
        .cloned()
        .or_else(|| {
            chars
                .iter()
                .find(|c| c.properties.contains(CharPropFlags::WRITE))
                .cloned()
        });
    Some((notify_char?, cmd_char?))
}

// GATT 标准 Device Name 特征 UUID:00002A00-0000-1000-8000-00805f9b34fb
// 连接后可从此特征读取设备真实名称(如 "AhaKey Pro")
const DEVICE_NAME_CHAR_UUID: Uuid = Uuid::from_bytes([
    0x00, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x10, 0x00, 0x80, 0x00, 0x00, 0x80, 0x5f, 0x9b, 0x34, 0xfb,
]);

/// 从已连接的 peripheral 读取 GATT Device Name 特征(0x2A00)。
/// 若设备没有此特征或读取失败,返回空字符串。
async fn read_device_name(peripheral: &Peripheral) -> Result<String, String> {
    let chars = peripheral.characteristics();
    let name_char = chars
        .iter()
        .find(|c| c.uuid == DEVICE_NAME_CHAR_UUID)
        .cloned()
        .ok_or_else(|| "Device Name char (0x2A00) not found".to_string())?;

    let data = peripheral
        .read(&name_char)
        .await
        .map_err(|e| format!("read Device Name: {e}"))?;

    let name = String::from_utf8(data).unwrap_or_default();
    Ok(name)
}
