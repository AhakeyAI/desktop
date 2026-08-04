//! AhaKey 协议包定义
//!
//! 对齐 macOS `AhaKeyProtocol.swift` 字节级实现。
//! 帧格式: `AA BB [cmd:1] [payload:N] CC DD`
//! - 小端字节序
//! - payload 长度由 trailer 位置隐含,无显式长度字段
//! - 无序列号(原厂协议无 req/resp 配对概念)
//! - 无 CRC(原厂用固定 trailer 切帧,不做校验和)

use serde::{Deserialize, Serialize};

/// 帧头
pub const PROTOCOL_HEADER: [u8; 2] = [0xAA, 0xBB];

/// 帧尾
pub const PROTOCOL_TRAILER: [u8; 2] = [0xCC, 0xDD];

/// 最小帧长度(AA BB cmd CC DD)
pub const MIN_FRAME_LEN: usize = 5;

/// OLED 几何常量(与 macOS / Java 端一致)
pub const OLED_WIDTH: usize = 160;
pub const OLED_HEIGHT: usize = 80;
pub const OLED_FRAME_BYTES: usize = OLED_WIDTH * OLED_HEIGHT * 2;
pub const OLED_FRAME_SLOT_SIZE: usize = 28_672;
pub const OLED_FACTORY_RESERVED_SLOTS: usize = 10;
pub const OLED_MODE_COUNT: u8 = 4;
pub const OLED_MAX_FRAMES_PER_MODE: usize = 70;
pub const OLED_CHUNK_SIZE: usize = 4096;
pub const OLED_PACKET_SIZE: usize = 180;

/// AhaKey 命令码 — 完整对齐 macOS `AhaKeyCommand` 的 25 个命令
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[repr(u8)]
pub enum AhaKeyCommand {
    /// 设备状态查询 → AA BB 00 CC DD
    QueryDeviceStatus = 0x00,
    /// 修改设备名称 → AA BB 01 [utf8...] CC DD
    ChangeName = 0x01,
    /// 修改 BLE Appearance → AA BB 02 [appearance] CC DD
    ChangeAppearance = 0x02,
    /// 保存配置到设备 Flash → AA BB 04 CC DD
    SaveConfig = 0x04,
    /// 更新自定义按键(子类型决定 shortcut/macro/description)
    /// → AA BB 73 [sub] [mode] [key] [data...] CC DD
    UpdateCustomKey = 0x73,
    /// 准备大块数据写入 → AA BB 80 [flag:1] [chunk_len:2 LE] [address:4 LE] CC DD
    PrepareWrite = 0x80,
    /// 大块数据写入结果(设备→主机)
    WriteResult = 0x81,
    /// 更新 OLED 静态图片 → AA BB 82 [mode] [start_idx:2 LE] [frame_count:2 LE] [delay:2 LE] CC DD
    UpdatePic = 0x82,
    /// 读取图片状态 → AA BB 83 [mode] CC DD
    ReadPicState = 0x83,
    /// 设置 per-mode per-state LED 灯效映射 → AA BB 84 [mode] [effect_codes...] CC DD
    SetLightMapping = 0x84,
    /// 全局 WS2812 亮度 1-100 → AA BB 85 [brightness] CC DD
    SetBrightness = 0x85,
    /// IDE 状态 → LED 变色 → AA BB 90 [state] CC DD
    UpdateState = 0x90,
    /// 预览灯效(不保存配置)→ AA BB 91 [effect] CC DD
    PreviewLightEffect = 0x91,
    /// 远程切换工作模式 0-3 → AA BB 92 [mode] CC DD
    SetWorkMode = 0x92,
    /// 更新任务 GIF 单帧
    UpdateTaskPic = 0x93,
    /// 读取任务 GIF 状态
    ReadTaskPicState = 0x94,
    /// 更新任务 GIF 集合
    UpdateTaskPicSet = 0x95,
    /// 读取任务 GIF 集合
    ReadTaskPicSet = 0x96,
    /// 设置当前激活的任务 GIF 集合
    SetActiveTaskPicSet = 0x97,
    /// 完成任务 GIF 数据传输(不改变普通 OLED 动画绑定)
    FinishTaskPicWrite = 0x98,
    /// 查询设备能力
    Capabilities = 0x99,
    /// 终止图片写入
    AbortPictureWrite = 0x9A,
    /// 准备 session 写入
    PrepareSessionWrite = 0x9B,
}

impl AhaKeyCommand {
    pub fn from_u8(v: u8) -> Option<Self> {
        Some(match v {
            0x00 => Self::QueryDeviceStatus,
            0x01 => Self::ChangeName,
            0x02 => Self::ChangeAppearance,
            0x04 => Self::SaveConfig,
            0x73 => Self::UpdateCustomKey,
            0x80 => Self::PrepareWrite,
            0x81 => Self::WriteResult,
            0x82 => Self::UpdatePic,
            0x83 => Self::ReadPicState,
            0x84 => Self::SetLightMapping,
            0x85 => Self::SetBrightness,
            0x90 => Self::UpdateState,
            0x91 => Self::PreviewLightEffect,
            0x92 => Self::SetWorkMode,
            0x93 => Self::UpdateTaskPic,
            0x94 => Self::ReadTaskPicState,
            0x95 => Self::UpdateTaskPicSet,
            0x96 => Self::ReadTaskPicSet,
            0x97 => Self::SetActiveTaskPicSet,
            0x98 => Self::FinishTaskPicWrite,
            0x99 => Self::Capabilities,
            0x9A => Self::AbortPictureWrite,
            0x9B => Self::PrepareSessionWrite,
            _ => return None,
        })
    }
}

/// 按键子类型(UpdateCustomKey 0x73 命令的 payload 第一个字节)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u8)]
pub enum KeySubType {
    /// 快捷键映射 HID Usage
    Shortcut = 0x73,
    /// 宏(动作序列)
    Macro = 0x74,
    /// LCD 文字描述
    Description = 0x75,
}

/// AhaKey 响应帧解析结果
///
/// 注意:与上一版不同,**本协议无 status 字段**。
/// 响应帧 `AA BB cmd [data...] CC DD` 里的 cmd 字段就是请求的命令(0x80 表示通用 ACK)。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AhaKeyResponse {
    pub cmd: AhaKeyCommand,
    pub payload: Vec<u8>,
}
