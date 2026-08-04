//! 协议编解码器
//!
//! 与 macOS `AhaKeyCommand` (Swift) / `AhaKeyProtocol` (Java) **字节级一致**。
//! 帧格式: `[AA BB] [cmd:1] [payload:N] [CC DD]`

use crate::error::{AppError, AppResult};
use crate::protocol::packet::{
    AhaKeyCommand, AhaKeyResponse, PROTOCOL_HEADER, PROTOCOL_TRAILER,
};

/// 协议编解码器
pub struct ProtocolCodec;

impl ProtocolCodec {
    /// 编码请求帧: `[AA BB] [cmd] [payload] [CC DD]`
    pub fn encode(cmd: AhaKeyCommand, payload: &[u8]) -> Vec<u8> {
        let mut frame = Vec::with_capacity(MIN_FRAME_LEN + payload.len());
        frame.extend_from_slice(&PROTOCOL_HEADER);
        frame.push(cmd as u8);
        frame.extend_from_slice(payload);
        frame.extend_from_slice(&PROTOCOL_TRAILER);
        frame
    }

    /// 编码无 payload 的请求帧: `[AA BB] [cmd] [CC DD]`
    pub fn encode_no_payload(cmd: AhaKeyCommand) -> Vec<u8> {
        Self::encode(cmd, &[])
    }

    /// 解码响应帧
    pub fn decode(buf: &[u8]) -> AppResult<AhaKeyResponse> {
        if buf.len() < MIN_FRAME_LEN {
            return Err(AppError::Protocol(format!(
                "frame too short: {} bytes",
                buf.len()
            )));
        }
        if buf[0..2] != PROTOCOL_HEADER {
            return Err(AppError::Protocol("bad header (expected AA BB)".into()));
        }
        if buf[buf.len() - 2..] != PROTOCOL_TRAILER {
            return Err(AppError::Protocol("bad trailer (expected CC DD)".into()));
        }
        let cmd = AhaKeyCommand::from_u8(buf[2])
            .ok_or_else(|| AppError::Protocol(format!("unknown cmd: 0x{:02X}", buf[2])))?;
        let payload = buf[3..buf.len() - 2].to_vec();
        Ok(AhaKeyResponse { cmd, payload })
    }
}

use crate::protocol::packet::MIN_FRAME_LEN;

#[cfg(test)]
mod tests {
    use super::*;

    /// 关键断言:与 macOS `AhaKeyCommand.queryDeviceStatus()` 字节级一致
    /// macOS 源码: `Data(header + [0x00] + trailer)` = AA BB 00 CC DD
    #[test]
    fn test_query_device_status_matches_macos() {
        let frame = ProtocolCodec::encode_no_payload(AhaKeyCommand::QueryDeviceStatus);
        assert_eq!(frame, vec![0xAA, 0xBB, 0x00, 0xCC, 0xDD]);
    }

    /// 关键断言:与 macOS `saveConfig()` 字节级一致
    /// macOS 源码: `Data(header + [cmdSaveConfig] + trailer)` = AA BB 04 CC DD
    #[test]
    fn test_save_config_matches_macos() {
        let frame = ProtocolCodec::encode_no_payload(AhaKeyCommand::SaveConfig);
        assert_eq!(frame, vec![0xAA, 0xBB, 0x04, 0xCC, 0xDD]);
    }

    /// 关键断言:与 macOS `setKeyMapping(mode:0, keyIndex:0, hidCodes:[0x04, 0x05])` 一致
    /// macOS 源码: `Data(header + [cmdUpdateCustomKey] + [subShortcut, mode, keyIndex] + hidCodes + trailer)`
    /// = AA BB 73 73 00 00 04 05 CC DD
    #[test]
    fn test_set_key_mapping_matches_macos() {
        // 这个测试本来由 builder.rs 覆盖,但先在 codec 层验证 encode 不带 sub-prefix
        let frame = ProtocolCodec::encode(
            AhaKeyCommand::UpdateCustomKey,
            &[0x73, 0x00, 0x00, 0x04, 0x05],
        );
        assert_eq!(frame, vec![0xAA, 0xBB, 0x73, 0x73, 0x00, 0x00, 0x04, 0x05, 0xCC, 0xDD]);
    }

    /// 关键断言:与 macOS `changeName("Hi")` 一致
    /// macOS 源码: `Data(header + [cmdChangeName] + "Hi".utf8 + trailer)`
    /// = AA BB 01 48 69 CC DD
    #[test]
    fn test_change_name_matches_macos() {
        let frame = ProtocolCodec::encode(AhaKeyCommand::ChangeName, b"Hi");
        assert_eq!(frame, vec![0xAA, 0xBB, 0x01, 0x48, 0x69, 0xCC, 0xDD]);
    }

    /// 关键断言:与 macOS `setBrightness(75)` 一致
    /// macOS 源码: `Data(header + [cmdSetBrightness, 75] + trailer)`
    /// = AA BB 85 4B CC DD
    #[test]
    fn test_set_brightness_matches_macos() {
        let frame = ProtocolCodec::encode(AhaKeyCommand::SetBrightness, &[75]);
        assert_eq!(frame, vec![0xAA, 0xBB, 0x85, 0x4B, 0xCC, 0xDD]);
    }

    /// 解码 roundtrip
    #[test]
    fn test_decode_roundtrip() {
        let frame = ProtocolCodec::encode(AhaKeyCommand::QueryDeviceStatus, &[0x01, 0x02, 0x03]);
        let resp = ProtocolCodec::decode(&frame).unwrap();
        assert_eq!(resp.cmd, AhaKeyCommand::QueryDeviceStatus);
        assert_eq!(resp.payload, vec![0x01, 0x02, 0x03]);
    }

    /// 错误路径:帧头不对
    #[test]
    fn test_decode_bad_header() {
        let bad = vec![0x00, 0x01, 0x00, 0xCC, 0xDD];
        assert!(ProtocolCodec::decode(&bad).is_err());
    }

    /// 错误路径:帧尾不对
    #[test]
    fn test_decode_bad_trailer() {
        let bad = vec![0xAA, 0xBB, 0x00, 0x00, 0x00];
        assert!(ProtocolCodec::decode(&bad).is_err());
    }

    /// 错误路径:命令码未识别
    #[test]
    fn test_decode_unknown_cmd() {
        let bad = vec![0xAA, 0xBB, 0xFF, 0xCC, 0xDD];
        assert!(ProtocolCodec::decode(&bad).is_err());
    }

    /// 错误路径:帧太短
    #[test]
    fn test_decode_too_short() {
        assert!(ProtocolCodec::decode(&[0xAA, 0xBB]).is_err());
    }
}
