//! Session-only, peer-owned host metadata. Never infer a host from the input target.
use crate::{protocol::frame, BleError, Result};
use serde::Serialize;

pub const NAME_BYTES: usize = 24;
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HostInfo {
    pub name: Option<String>,
    pub system: Option<String>,
}
fn unsafe_char(c: char) -> bool {
    c.is_control()
        || matches!(c, '\u{200e}' | '\u{200f}' | '\u{202a}'..='\u{202e}' | '\u{2066}'..='\u{2069}')
}
pub fn bounded_name(name: &str) -> String {
    let mut result = String::new();
    for c in name.trim().chars().filter(|c| !unsafe_char(*c)) {
        if result.len() + c.len_utf8() > NAME_BYTES {
            break;
        }
        result.push(c);
    }
    result
}
pub fn query(slot: u8, part: u8) -> Result<Vec<u8>> {
    if slot > 1 || part > 2 {
        return Err(BleError::Invalid(
            "Invalid host information slot/part".into(),
        ));
    }
    Ok(frame(0xa8, &[slot, part]))
}
pub fn registration(name: &str, system: u8, id: u16) -> Result<[Vec<u8>; 3]> {
    if !(1..=3).contains(&system) || id > 0x3fff {
        return Err(BleError::Invalid(
            "Invalid host information system/request".into(),
        ));
    }
    let name = bounded_name(name);
    let mut padded = [0; NAME_BYTES];
    padded[..name.len()].copy_from_slice(name.as_bytes());
    Ok(std::array::from_fn(|part| {
        let mut data = vec![
            (id & 127) as u8,
            (id >> 7) as u8,
            part as u8,
            system,
            name.len() as u8,
        ];
        data.extend_from_slice(&padded[part * 8..part * 8 + 8]);
        frame(0xa9, &data)
    }))
}
pub fn confirm(bytes: &[u8], id: u16, part: u8) -> Result<u8> {
    if bytes.len() != 10
        || bytes[..3] != [0xaa, 0xbb, 0xa9]
        || bytes[3] != 0
        || bytes[4] != (id & 127) as u8
        || bytes[5] != (id >> 7) as u8
        || bytes[6] != part
        || bytes[7] > 1
        || bytes[8..] != [0xcc, 0xdd]
    {
        return Err(BleError::Invalid(
            "设备未确认本机名称上报；输入连接不受影响".into(),
        ));
    }
    Ok(bytes[7])
}
pub fn decode(slot: u8, parts: &[Vec<u8>; 3]) -> Result<HostInfo> {
    let invalid = || {
        BleError::Invalid("设备名称未提供或读取期间发生变化，请重新读取（需固件 0.1.8+）".into())
    };
    let mut name = Vec::with_capacity(NAME_BYTES);
    for (part, b) in parts.iter().enumerate() {
        if slot > 1
            || b.len() != 20
            || b[..4] != [0xaa, 0xbb, 0xa8, 0]
            || b[4] != slot
            || b[5] != part as u8
            || b[6] > 127
            || b[7] > 127
            || b[8] > 3
            || b[9] > 24
            || b[18..] != [0xcc, 0xdd]
            || (part > 0 && b[6..10] != parts[0][6..10])
        {
            return Err(invalid());
        }
        name.extend_from_slice(&b[10..18]);
    }
    let len = parts[0][9] as usize;
    if name[len..].iter().any(|b| *b != 0) || (parts[0][8] == 0 && len != 0) {
        return Err(invalid());
    }
    let name = std::str::from_utf8(&name[..len]).map_err(|_| invalid())?;
    if name.chars().any(unsafe_char) {
        return Err(invalid());
    }
    Ok(HostInfo {
        name: (!name.is_empty()).then(|| name.to_owned()),
        system: match parts[0][8] {
            1 => Some("Windows"),
            2 => Some("macOS"),
            3 => Some("Linux"),
            _ => None,
        }
        .map(str::to_owned),
    })
}
#[cfg(test)]
mod tests {
    use super::*;
    fn replies(name: &str) -> [Vec<u8>; 3] {
        let mut padded = [0; 24];
        padded[..name.len()].copy_from_slice(name.as_bytes());
        std::array::from_fn(|part| {
            let mut b = vec![
                0xaa,
                0xbb,
                0xa8,
                0,
                1,
                part as u8,
                12,
                1,
                2,
                name.len() as u8,
            ];
            b.extend_from_slice(&padded[part * 8..part * 8 + 8]);
            b.extend_from_slice(&[0xcc, 0xdd]);
            b
        })
    }
    #[test]
    fn unicode_names_and_default_mtu_roundtrip() {
        let name = bounded_name("  我的 MacBook 名称比较长\n\u{202e}  ");
        assert!(name.len() <= 24);
        assert!(!name.contains('\n'));
        let frames = registration(&name, 2, 0x1234).unwrap();
        assert!(frames.iter().all(|f| f.len() == 18));
        let parsed = decode(1, &replies(&name)).unwrap();
        assert_eq!(parsed.name.as_deref(), Some(name.as_str()));
        assert_eq!(parsed.system.as_deref(), Some("macOS"));
        assert_eq!(
            confirm(
                &[0xaa, 0xbb, 0xa9, 0, 0x34, 0x24, 2, 1, 0xcc, 0xdd],
                0x1234,
                2
            )
            .unwrap(),
            1
        );
    }
    #[test]
    fn rejects_wrong_slot_mixed_revisions_controls_and_invalid_utf8() {
        let good = replies("Mac");
        assert!(decode(0, &good).is_err());
        for part in 0..3 {
            for len in 0..20 {
                let mut b = good.clone();
                b[part].truncate(len);
                assert!(decode(1, &b).is_err());
            }
        }
        let mut b = good.clone();
        b[1][6] += 1;
        assert!(decode(1, &b).is_err());
        let mut b = good.clone();
        b[0][10] = 0xff;
        assert!(decode(1, &b).is_err());
        let mut b = good.clone();
        b[0][10] = 10;
        assert!(decode(1, &b).is_err());
        let mut b = good;
        for p in &mut b {
            p[8] = 0;
        }
        assert!(decode(1, &b).is_err());
        assert!(confirm(&[0xaa, 0xbb, 0xa9, 0, 1, 0, 0, 0, 0xcc, 0xdd], 2, 0).is_err());
        assert!(registration("ok", 4, 1).is_err());
        assert!(query(2, 0).is_err());
        assert_eq!(decode(1, &replies("")).unwrap().name, None);
    }
}
