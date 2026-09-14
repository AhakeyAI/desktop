//! Read-only policy/status and explicitly USB-only reset wire contract.
use crate::{protocol::frame, BleError, Result};
use serde::Serialize;
pub const QUERY: [u8; 5] = [0xaa, 0xbb, 0xab, 0xcc, 0xdd];
#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct Policy {
    pub fixed_upper_usb: bool,
    pub state: u8,
    pub target: Option<u8>,
    pub error: u8,
    pub request: u16,
    pub paired: u8,
}
pub fn parse(b: &[u8]) -> Result<Policy> {
    if b.len() != 14
        || b[..6] != [0xaa, 0xbb, 0xab, 0, 1, 1]
        || b[6] > 3
        || ![0, 1, 2, 255].contains(&b[7])
        || b[9] > 127
        || b[10] > 127
        || b[11] > 3
        || b[12..] != [0xcc, 0xdd]
    {
        return Err(BleError::Invalid(
            "固件不支持固定上端 USB / 安全重置，请升级至 0.1.9+".into(),
        ));
    }
    Ok(Policy {
        fixed_upper_usb: true,
        state: b[6],
        target: (b[7] < 3).then_some(b[7]),
        error: b[8],
        request: u16::from(b[9]) | (u16::from(b[10]) << 7),
        paired: b[11],
    })
}
pub fn request(target: u8, id: u16) -> Result<Vec<u8>> {
    if target > 2 || id > 0x3fff {
        return Err(BleError::Invalid("无效重置目标".into()));
    }
    Ok(frame(0xac, &[target, (id & 127) as u8, (id >> 7) as u8]))
}
pub fn accepted(b: &[u8], target: u8, id: u16) -> Result<()> {
    if b.len() != 9
        || b[..3] != [0xaa, 0xbb, 0xac]
        || b[4] != target
        || b[5] != (id & 127) as u8
        || b[6] != (id >> 7) as u8
        || b[7..] != [0xcc, 0xdd]
    {
        return Err(BleError::Invalid(
            "未取得匹配的重置确认；请读取状态，勿重复提交".into(),
        ));
    }
    if b[3] != 0 {
        return Err(BleError::Invalid(format!(
            "设备拒绝重置（{}）；请松开按键并确认绑定记录可识别",
            b[3]
        )));
    }
    Ok(())
}
pub fn completed(p: &Policy, target: u8, id: u16) -> Result<bool> {
    if p.target != Some(target) || p.request != id {
        return Err(BleError::Invalid("重置状态不匹配；勿自动重复操作".into()));
    }
    if p.state == 3 {
        return Err(BleError::Invalid(format!(
            "重置未确认完成（错误 {}）；可能已断开目标，请先重新读取",
            p.error
        )));
    }
    Ok(p.state == 2)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn only_exact_capability_and_reset_confirmation_are_accepted() {
        let b = [0xaa, 0xbb, 0xab, 0, 1, 1, 2, 1, 0, 12, 0, 1, 0xcc, 0xdd];
        let p = parse(&b).unwrap();
        assert!(completed(&p, 1, 12).unwrap());
        assert!(completed(&p, 0, 12).is_err());
        for len in 0..14 {
            assert!(parse(&b[..len]).is_err());
        }
        for index in [3, 4, 5, 6, 7, 9, 10, 11, 13] {
            let mut bad = b;
            bad[index] = 254;
            assert!(parse(&bad).is_err());
        }
        assert!(accepted(&[0xaa, 0xbb, 0xac, 0, 1, 12, 0, 0xcc, 0xdd], 1, 12).is_ok());
        assert!(accepted(&[0xaa, 0xbb, 0xac, 1, 1, 12, 0, 0xcc, 0xdd], 1, 12).is_err());
        assert!(request(3, 1).is_err());
        let mut pending = p.clone();
        pending.state = 1;
        assert!(!completed(&pending, 1, 12).unwrap());
        pending.state = 3;
        assert!(completed(&pending, 1, 12).is_err());
    }
}
