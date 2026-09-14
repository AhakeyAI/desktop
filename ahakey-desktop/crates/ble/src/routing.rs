//! Device-owned three-link routing. Never infer support from the legacy "1.0" status.
use crate::{protocol::frame, BleError, Result};
use serde::{Deserialize, Serialize};

pub const QUERY: [u8; 5] = [0xaa, 0xbb, 0xa2, 0xcc, 0xdd];
pub const DETAILS_QUERY: [u8; 5] = [0xaa, 0xbb, 0xa5, 0xcc, 0xdd];
#[derive(Clone, Copy, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ManagementAction {
    SwapSlots,
    Retry,
}
impl ManagementAction {
    pub fn command(self) -> u8 {
        match self {
            Self::SwapSlots => 0xa6,
            Self::Retry => 0xa7,
        }
    }
    pub fn frame(self, request: u16) -> Vec<u8> {
        frame(
            self.command(),
            &[(request & 127) as u8, ((request >> 7) & 127) as u8],
        )
    }
}
pub fn next_management_request() -> u16 {
    use std::sync::{
        atomic::{AtomicU16, Ordering},
        Once,
    };
    static INIT: Once = Once::new();
    static NEXT: AtomicU16 = AtomicU16::new(0);
    INIT.call_once(|| {
        let seed = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .subsec_nanos()
            ^ std::process::id();
        NEXT.store(seed as u16, Ordering::Relaxed);
    });
    NEXT.fetch_add(1, Ordering::Relaxed) & 0x3fff
}
pub fn management_confirmed(bytes: &[u8], action: ManagementAction, request: u16) -> Result<()> {
    if bytes.len() != 8
        || bytes[..3] != [0xaa, 0xbb, action.command()]
        || bytes[6..] != [0xcc, 0xdd]
        || bytes[4] != ((request & 127) as u8)
        || bytes[5] != (((request >> 7) & 127) as u8)
    {
        return Err(BleError::Invalid(
            "未取得匹配的设备确认，请重新读取；不要自动重复操作".into(),
        ));
    }
    if bytes[3] != 0 {
        return Err(BleError::Invalid(format!(
            "设备拒绝操作（{}），请松开按键并等待配对结束后重试",
            bytes[3]
        )));
    }
    Ok(())
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Details {
    pub paired: u8,
    pub connected: u8,
    pub ready: u8,
    pub effective_up: u8,
    pub effective_down: u8,
    pub wired: bool,
    pub radio_state: u8,
    pub pairing_slot: Option<u8>,
    pub remaining_seconds: u8,
    pub bond_count: u8,
    pub last_reason: u8,
    pub last_hci: u8,
    pub pending: bool,
    pub selected: u8,
    pub raw_links: u8,
}
pub fn parse_details(b: &[u8]) -> Result<Details> {
    if b.len() != 20 || b[..5] != [0xaa, 0xbb, 0xa5, 0, 1] || b[18..] != [0xcc, 0xdd] {
        return Err(BleError::Invalid(
            "固件未提供有效的配对详情，需要支持此功能的固件".into(),
        ));
    }
    if b[5] > 3
        || b[6] > 7
        || b[7] > 7
        || b[7] & !b[6] != 0
        || b[8] > 2
        || b[9] > 2
        || b[8] == b[9]
        || b[10] > 1
        || b[11] > 3
        || ![0, 1, 255].contains(&b[12])
        || b[13] > 60
        || b[14] > 2
        || b[17] & 0xe0 != 0
        || (b[17] >> 1) & 3 > 2
        || (b[17] >> 3) & 3 > 2
    {
        return Err(BleError::Invalid("设备配对详情不一致，请重新读取".into()));
    }
    Ok(Details {
        paired: b[5],
        connected: b[6],
        ready: b[7],
        effective_up: b[8],
        effective_down: b[9],
        wired: b[10] != 0,
        radio_state: b[11],
        pairing_slot: (b[12] < 2).then_some(b[12]),
        remaining_seconds: b[13],
        bond_count: b[14],
        last_reason: b[15],
        last_hci: b[16],
        pending: b[17] & 1 != 0,
        selected: (b[17] >> 1) & 3,
        raw_links: (b[17] >> 3) & 3,
    })
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Config {
    pub mode: u8,
    pub up: u8,
    pub down: u8,
}
impl Config {
    pub fn validate(&self) -> Result<()> {
        if self.mode > 1 || self.up > 2 || self.down > 2 || self.up == self.down {
            return Err(BleError::Invalid(
                "Choose two different targets from BLE A, BLE B and USB".into(),
            ));
        }
        Ok(())
    }
    pub fn frame(&self, request: u16) -> Result<Vec<u8>> {
        self.validate()?;
        // Seven-bit bytes cannot contain the legacy CC DD frame terminator.
        Ok(frame(
            0xa3,
            &[
                1,
                self.mode,
                self.up,
                self.down,
                (request & 127) as u8,
                ((request >> 7) & 127) as u8,
            ],
        ))
    }
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Status {
    pub config: Config,
    pub selected: u8,
    pub connected: u8,
    pub ready: u8,
    pub lever: u8,
    pub routing_error: u8,
}
#[derive(Debug)]
pub struct Reply {
    pub result: u8,
    pub request: Option<u16>,
    pub status: Status,
}
pub fn parse(bytes: &[u8]) -> Option<Reply> {
    let offset = match (bytes.len(), bytes.get(2)) {
        (15, Some(0xa2)) => 4,
        (17, Some(0xa3)) => 6,
        _ => return None,
    };
    if bytes[..2] != [0xaa, 0xbb] || bytes[bytes.len() - 2..] != [0xcc, 0xdd] {
        return None;
    }
    let p = &bytes[offset..offset + 9];
    let config = Config {
        mode: p[1],
        up: p[2],
        down: p[3],
    };
    if p[0] != 1
        || config.validate().is_err()
        || p[4] > 2
        || p[5] > 7
        || p[6] > 7
        || p[6] & !p[5] != 0
        || p[7] > 2
    {
        return None;
    }
    let request = if offset == 6 {
        if bytes[4] > 127 || bytes[5] > 127 {
            return None;
        }
        Some(u16::from(bytes[4]) | (u16::from(bytes[5]) << 7))
    } else {
        None
    };
    Some(Reply {
        result: bytes[3],
        request,
        status: Status {
            config,
            selected: p[4],
            connected: p[5],
            ready: p[6],
            lever: p[7],
            routing_error: p[8],
        },
    })
}
pub fn confirmed(reply: Reply, request: Option<u16>, expected: Option<&Config>) -> Result<Status> {
    if reply.request != request || expected.is_some_and(|v| v != &reply.status.config) {
        return Err(BleError::Invalid(
            "Routing reply does not match this request; read device settings again".into(),
        ));
    }
    if reply.result != 0 {
        return Err(BleError::Invalid(format!(
            "Device rejected routing settings (code {}); not confirmed saved",
            reply.result
        )));
    }
    Ok(reply.status)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn details_distinguish_pairing_from_live_links_and_validate_bounds() {
        let b = [
            0xaa, 0xbb, 0xa5, 0, 1, 2, 6, 6, 2, 1, 1, 3, 0xff, 0, 2, 6, 8, 4, 0xcc, 0xdd,
        ];
        let d = parse_details(&b).unwrap();
        assert_eq!((d.paired, d.connected, d.ready, d.selected), (2, 6, 6, 2));
        assert_eq!(d.pairing_slot, None);
        assert!(!d.pending);
        for i in 0..b.len() {
            assert!(parse_details(&b[..i]).is_err());
        }
        for (i, v) in [
            (3, 1),
            (4, 2),
            (5, 4),
            (6, 8),
            (7, 8),
            (8, 3),
            (9, 2),
            (10, 2),
            (11, 4),
            (12, 2),
            (13, 61),
            (14, 3),
            (17, 6),
            (19, 0),
        ] {
            let mut bad = b;
            bad[i] = v;
            assert!(parse_details(&bad).is_err(), "accepted invalid {i}");
        }
    }
    #[test]
    fn management_requires_exact_action_nonce_and_success_without_retry() {
        for action in [ManagementAction::SwapSlots, ManagementAction::Retry] {
            for id in 0..16384 {
                let f = action.frame(id);
                assert_eq!(f.len(), 7);
                assert!(!f[2..5].windows(2).any(|w| w == [0xcc, 0xdd]));
            }
            let id = 0x1234;
            let mut b = [
                0xaa,
                0xbb,
                action.command(),
                0,
                (id & 127) as u8,
                ((id >> 7) & 127) as u8,
                0xcc,
                0xdd,
            ];
            assert!(management_confirmed(&b, action, id).is_ok());
            assert!(management_confirmed(&b, action, id + 1).is_err());
            b[3] = 1;
            assert!(management_confirmed(&b, action, id).is_err());
        }
    }
    #[test]
    fn all_pairs_and_delimiter_safe_requests() {
        for up in 0..3 {
            for down in 0..3 {
                let c = Config { mode: 1, up, down };
                assert_eq!(c.validate().is_ok(), up != down);
            }
        }
        for request in 0..16384 {
            let f = Config {
                mode: 1,
                up: 2,
                down: 0,
            }
            .frame(request)
            .unwrap();
            assert!(!f[2..f.len() - 2].windows(2).any(|p| p == [0xcc, 0xdd]));
        }
    }
    #[test]
    fn strict_readback_and_acknowledgment() {
        let query = [0xaa, 0xbb, 0xa2, 0, 1, 1, 2, 0, 2, 7, 7, 0, 0, 0xcc, 0xdd];
        let state = confirmed(parse(&query).unwrap(), None, None).unwrap();
        assert_eq!(state.config.up, 2);
        let ack = [
            0xaa, 0xbb, 0xa3, 0, 0x32, 0x54, 1, 1, 2, 0, 2, 7, 7, 0, 0, 0xcc, 0xdd,
        ];
        assert!(confirmed(
            parse(&ack).unwrap(),
            Some(0x32 | (0x54 << 7)),
            Some(&state.config)
        )
        .is_ok());
        assert!(confirmed(parse(&ack).unwrap(), Some(1), None).is_err());
        let mut bad = ack;
        bad[3] = 2;
        assert!(confirmed(parse(&bad).unwrap(), Some(0x32 | (0x54 << 7)), None).is_err());
        assert!(parse(&[0xaa, 0xbb, 0xa2, 0, 0xcc, 0xdd]).is_none()); // old firmware generic ACK
        for len in 0..query.len() {
            assert!(parse(&query[..len]).is_none());
        }
        for (index, value) in [
            (4, 2),
            (5, 2),
            (6, 3),
            (7, 2),
            (8, 3),
            (9, 8),
            (10, 8),
            (11, 3),
            (14, 0),
        ] {
            let mut bad = query;
            bad[index] = value;
            assert!(parse(&bad).is_none());
        }
    }
}
