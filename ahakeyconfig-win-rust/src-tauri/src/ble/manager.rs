// AhaKey BLE 通信 — 通过 BLE_tcp_bridge_v2 (.NET 8 WinForms, 127.0.0.1:9000)
//
// 为什么不用 btleplug 直连 Windows BLE API?
//   AhaKey 5A93 设备对 host 端 BLE 通信有特定要求 — 必须走 BLE_tcp_bridge 这层
//   (C# 调 Windows.Devices.Bluetooth WinRT API,在该层有 handshake / 缓存策略)。
//   btleplug / winrt 直连会出现 0x8000000E 等 WinRT 内部错误。
//
// 协议: [Type:1][Length:2 LE][Data:N]
//   C→S 0x01 WriteData  | C→S 0x02 WriteCommand | C→S 0x03 QueryBleStatus | C→S 0x04 QueryDeviceInfo
//   S→C 0x81 BleNotify  | S→C 0x82 BleStatusResp | S→C 0x83 DeviceInfoResp
//
// 状态查询:周期性发 [0x02 0x05 0x00 AA BB 00 CC DD] → 设备 0x7344 notify → v2 bridge 0x81 透传
//   → Rust 端 on_ble_notify 解析 14 字节 status frame (跟 macOS Swift 端 byte-level 一致)

use std::sync::Arc;
use std::time::Duration;

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, Manager};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::sync::{mpsc, Mutex};
use tokio::time::interval;
use tracing::{debug, info, warn};

use crate::error::{AppError, AppResult};

const BRIDGE_HOST: &str = "127.0.0.1";
const BRIDGE_PORT: u16 = 9000;
const STATUS_QUERY_FRAME: [u8; 5] = [0xAA, 0xBB, 0x00, 0xCC, 0xDD];
const STATUS_QUERY_INTERVAL_SECS: u64 = 1;

// ============================================================
// TCP 协议 (字节级兼容 BLE_tcp_bridge_v2 C# 端)
// ============================================================

const PKT_TYPE_WRITE_DATA: u8 = 0x01;
const PKT_TYPE_WRITE_COMMAND: u8 = 0x02;
const PKT_TYPE_QUERY_BLE_STATUS: u8 = 0x03;
const PKT_TYPE_QUERY_DEVICE_INFO: u8 = 0x04;

const PKT_TYPE_BLE_NOTIFY: u8 = 0x81;
const PKT_TYPE_BLE_STATUS_RESP: u8 = 0x82;
const PKT_TYPE_DEVICE_INFO_RESP: u8 = 0x83;

fn build_packet(packet_type: u8, data: &[u8]) -> Vec<u8> {
    let mut packet = Vec::with_capacity(3 + data.len());
    packet.push(packet_type);
    packet.push((data.len() & 0xFF) as u8);
    packet.push(((data.len() >> 8) & 0xFF) as u8);
    packet.extend_from_slice(data);
    packet
}

// ============================================================
// BridgeStatusInfo — 解析 0x82 BleStatusResp 包
// ============================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BleStatusInfo {
    pub connected: bool,
    pub device_name: String,
    pub mac_address: String,
    pub is_target_device: bool,
}

fn parse_ble_status(data: &[u8]) -> Option<BleStatusInfo> {
    if data.is_empty() {
        return None;
    }
    let connected = data[0] != 0;
    let mut offset = 1;
    if offset >= data.len() {
        return None;
    }
    let name_len = data[offset] as usize;
    offset += 1;
    if offset + name_len > data.len() {
        return None;
    }
    let device_name = String::from_utf8_lossy(&data[offset..offset + name_len]).into_owned();
    offset += name_len;
    if offset >= data.len() {
        return Some(BleStatusInfo {
            connected,
            device_name,
            mac_address: String::new(),
            is_target_device: false,
        });
    }
    let mac_len = data[offset] as usize;
    offset += 1;
    if offset + mac_len > data.len() {
        return Some(BleStatusInfo {
            connected,
            device_name,
            mac_address: String::new(),
            is_target_device: false,
        });
    }
    let mac_address = String::from_utf8_lossy(&data[offset..offset + mac_len]).into_owned();
    offset += mac_len;
    let is_target_device = offset < data.len() && data[offset] != 0;
    Some(BleStatusInfo {
        connected,
        device_name,
        mac_address,
        is_target_device,
    })
}

// ============================================================
// ConnState — TCP 写端 + 后台 task handle
// ============================================================

struct ConnState {
    /// TCP stream 写端 — 所有 send_frame 走这里
    writer: Arc<Mutex<Option<tokio::net::tcp::OwnedWriteHalf>>>,
    /// read task — 解析 0x81 / 0x82 / 0x83 包
    read_task: tauri::async_runtime::JoinHandle<()>,
    /// 周期状态查询 task
    poll_task: tauri::async_runtime::JoinHandle<()>,
}

// ============================================================
// BleManager — 跟之前一样的对外 API
// ============================================================

pub struct BleManager {
    app: AppHandle,
    conn: Mutex<Option<ConnState>>,
}

impl BleManager {
    pub fn new(app: AppHandle) -> AppResult<Self> {
        Ok(Self {
            app,
            conn: Mutex::new(None),
        })
    }

    /// 连接到 v2 BLE bridge
    /// 流程:TCP 连接 127.0.0.1:9000 → 启动 read loop → 启动 status query poller
    /// 一旦 TCP 连上,就算"已连接",后续 0x82 通知 + 0x81 通知更新 state
    pub async fn connect(&self, _address: &str, _name: &str) -> AppResult<String> {
        // 1. 已有连接则先清理
        self.cleanup_internal().await;

        info!("[BLE] connect requested: bridge={}:{}", BRIDGE_HOST, BRIDGE_PORT);

        // 2. TCP 拨号 v2 bridge
        let stream = TcpStream::connect((BRIDGE_HOST, BRIDGE_PORT))
            .await
            .map_err(|e| AppError::Ble(format!("connect bridge: {e}")))?;
        info!("[BLE] TCP connected to {}:{}", BRIDGE_HOST, BRIDGE_PORT);

        // 3. 拆读写半部 — 写端用 Arc<Mutex<Option<>>> 让 send_frame 共享,读端独立 task
        let (read_half, write_half) = stream.into_split();
        let writer = Arc::new(Mutex::new(Some(write_half)));

        // 4. 启动 read loop — 解析 0x81 / 0x82 / 0x83 包
        let app_r = self.app.clone();
        let read_task = tauri::async_runtime::spawn(async move {
            Self::read_loop(app_r, read_half).await;
            warn!("[BLE] read loop ended");
        });

        // 5. 启动周期状态查询
        let writer_for_poll = writer.clone();
        let poll_task = tauri::async_runtime::spawn(async move {
            let mut ticker = interval(Duration::from_secs(STATUS_QUERY_INTERVAL_SECS));
            ticker.tick().await; // 第一次立即返回
            loop {
                let packet = build_packet(PKT_TYPE_WRITE_COMMAND, &STATUS_QUERY_FRAME);
                let mut guard = writer_for_poll.lock().await;
                if let Some(stream) = guard.as_mut() {
                    if let Err(e) = stream.write_all(&packet).await {
                        warn!("[BLE] status query write failed: {e}");
                        // 不退出 — 等下次重试(连接可能临时断)
                    }
                } else {
                    warn!("[BLE] writer closed, status query loop exiting");
                    return;
                }
                drop(guard);
                ticker.tick().await;
            }
        });

        // 6. 存状态
        *self.conn.lock().await = Some(ConnState {
            writer: writer.clone(),
            read_task,
            poll_task,
        });

        info!("[BLE] connect complete: bridge={}:{}", BRIDGE_HOST, BRIDGE_PORT);
        Ok(format!("bridge://{}:{}", BRIDGE_HOST, BRIDGE_PORT))
    }

    /// read loop — 持续读 TCP 流,解析 0x81 / 0x82 / 0x83 包
    async fn read_loop(app: AppHandle, mut stream: tokio::net::tcp::OwnedReadHalf) {
        let mut header = [0u8; 3];
        let mut consecutive_errors: u32 = 0;
        loop {
            // 读 3 字节 header
            match stream.read_exact(&mut header).await {
                Ok(_) => {}
                Err(e) => {
                    consecutive_errors += 1;
                    warn!("[BLE] read header error ({consecutive_errors}/3): {e}");
                    if consecutive_errors >= 3 {
                        warn!("[BLE] read loop: 3 errors in a row, exiting");
                        let state = app.state::<crate::state::AppState>();
                        state.set_disconnected();
                        let _ = app.emit("device-status-changed", state.get_studio_state());
                        return;
                    }
                    tokio::time::sleep(Duration::from_millis(200)).await;
                    continue;
                }
            }
            consecutive_errors = 0;

            let packet_type = header[0];
            let length = (header[1] as usize) | ((header[2] as usize) << 8);

            // 读 N 字节 payload
            let mut payload = vec![0u8; length];
            if length > 0 {
                if let Err(e) = stream.read_exact(&mut payload).await {
                    warn!("[BLE] read payload error: {e}");
                    continue;
                }
            }

            match packet_type {
                PKT_TYPE_BLE_NOTIFY => {
                    // 0x81: raw BLE notify (来自设备 0x7344)
                    // 直接交给 state.on_ble_notify 解析(协议层已经在 state.rs 实现)
                    debug!("[BLE] notify uuid=0x7344 len={}", payload.len());
                    let state = app.state::<crate::state::AppState>();
                    state.on_ble_notify(&payload);
                    let _ = app.emit("device-status-changed", state.get_studio_state());
                }
                PKT_TYPE_BLE_STATUS_RESP => {
                    // 0x82: BleStatusInfo (connected / name / mac)
                    if let Some(info) = parse_ble_status(&payload) {
                        info!(
                            "[BLE] status: connected={} name='{}' mac='{}' target={}",
                            info.connected, info.device_name, info.mac_address, info.is_target_device
                        );
                        let state = app.state::<crate::state::AppState>();
                        if info.connected {
                            state.set_connected(info.mac_address.clone(), info.device_name.clone());
                        } else {
                            state.set_disconnected();
                        }
                        let _ = app.emit("device-status-changed", state.get_studio_state());
                    } else {
                        warn!("[BLE] failed to parse BleStatusInfo: {} bytes", payload.len());
                    }
                }
                PKT_TYPE_DEVICE_INFO_RESP => {
                    // 0x83: 8 字节 device status
                    debug!("[BLE] device info: {} bytes", payload.len());
                    // 8-byte format: battery / signal / fwMain / fwSub / workMode / lightMode / switchState / reserve
                    // state.rs 当前不直接消费 0x83 — 14 字节 status frame 走 0x81 已经够用
                    // 这里仅记 log,等需要时再接
                }
                other => {
                    debug!("[BLE] unknown packet type 0x{:02X} len={}", other, length);
                }
            }
        }
    }

    /// 发送一个完整协议帧到设备
    /// 帧字节由调用方用 `crate::protocol::builder::*` 构造
    /// 这里包一层 v2 bridge 的 WriteCommand 协议: [0x02][len_le][AA BB cmd payload CC DD]
    ///
    /// 失败时:如果未连接,返回 `Ble("not connected")`;
    /// 如果 TCP 写入失败,返回 `Ble("write: ...")`。
    pub async fn send_frame(&self, frame: &[u8]) -> AppResult<()> {
        let packet = build_packet(PKT_TYPE_WRITE_COMMAND, frame);
        let mut guard = self.conn.lock().await;
        let conn = guard
            .as_ref()
            .ok_or_else(|| AppError::Ble("not connected".into()))?;
        let mut writer_guard = conn.writer.lock().await;
        let stream = writer_guard
            .as_mut()
            .ok_or_else(|| AppError::Ble("writer closed".into()))?;
        stream
            .write_all(&packet)
            .await
            .map_err(|e| AppError::Ble(format!("write: {e}")))?;
        Ok(())
    }

    /// 断开 BLE 连接。
    /// 完成:所有 task abort → TCP 关闭。
    /// 不更新 AppState — 由调用方(commands.rs)负责。
    pub async fn disconnect(&self) -> AppResult<()> {
        self.cleanup_internal().await;
        Ok(())
    }

    /// 强制清理 — 用于 force_cleanup_ble command
    pub async fn force_cleanup(&self) {
        self.cleanup_internal().await;
    }

    /// 内部: 取消 task + 关闭 TCP writer
    async fn cleanup_internal(&self) {
        let mut guard = self.conn.lock().await;
        if let Some(conn) = guard.take() {
            // 关 writer — 这让 read loop / poll task 收到 broken pipe 后自然退出
            *conn.writer.lock().await = None;
            // task 会被 runtime 自动 drop(我们没有 abort 句柄,所以用 timeout 防卡)
            let _ = tokio::time::timeout(Duration::from_millis(500), async {
                let _ = conn.read_task.await;
                let _ = conn.poll_task.await;
            })
            .await;
        }
    }
}
