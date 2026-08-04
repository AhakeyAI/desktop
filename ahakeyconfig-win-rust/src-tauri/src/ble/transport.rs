//! BLE 数据传输封装
//!
//! 对应原 `UsbHidTransport.java`(Java 端)。
//! 协议帧通过 `crate::protocol::builder` 的 high-level 函数构造,
//! 不再维护 seq(原厂协议无 seq 概念)。

use crate::error::AppResult;
use crate::protocol::codec::ProtocolCodec;
use crate::protocol::packet::AhaKeyResponse;

/// BLE 传输层
pub struct BleTransport;

impl BleTransport {
    pub fn new() -> Self {
        Self
    }

    /// 发送心跳(原 Java 端无显式心跳函数;这里保留作为连接保活)
    pub fn send_heartbeat(&self) -> Vec<u8> {
        crate::protocol::query_device_status()
    }

    /// 发送按键配置(快捷键 HID 映射)
    pub fn send_key_config(&self, mode: u8, key_index: u8, hid_codes: &[u8]) -> Vec<u8> {
        crate::protocol::set_key_mapping(mode, key_index, hid_codes)
    }

    /// 发送 OLED 帧元数据(只发 update_picture 头,不包含图片数据本身)
    pub fn send_oled_frame_metadata(
        &self,
        mode: u8,
        start_index: u16,
        frame_count: u16,
        time_delay_ms: u16,
    ) -> Vec<u8> {
        crate::protocol::update_picture(mode, start_index, frame_count, time_delay_ms)
    }

    /// 解析响应帧
    pub fn parse_response(&self, buf: &[u8]) -> AppResult<AhaKeyResponse> {
        ProtocolCodec::decode(buf)
    }
}

impl Default for BleTransport {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_heartbeat_matches_protocol() {
        let t = BleTransport::new();
        let f = t.send_heartbeat();
        // queryDeviceStatus 字节: AA BB 00 CC DD
        assert_eq!(f, vec![0xAA, 0xBB, 0x00, 0xCC, 0xDD]);
    }

    #[test]
    fn test_send_key_config_matches_protocol() {
        let t = BleTransport::new();
        let f = t.send_key_config(0, 0, &[0x04, 0x05]);
        // setKeyMapping(0, 0, [0x04, 0x05]) 字节: AA BB 73 73 00 00 04 05 CC DD
        assert_eq!(f, vec![0xAA, 0xBB, 0x73, 0x73, 0x00, 0x00, 0x04, 0x05, 0xCC, 0xDD]);
    }

    #[test]
    fn test_parse_response() {
        let t = BleTransport::new();
        let frame = t.send_heartbeat();
        let resp = t.parse_response(&frame).unwrap();
        use crate::protocol::packet::AhaKeyCommand;
        assert_eq!(resp.cmd, AhaKeyCommand::QueryDeviceStatus);
        assert!(resp.payload.is_empty());
    }
}
