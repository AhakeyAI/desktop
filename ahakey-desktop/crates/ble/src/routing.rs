//! Device-owned three-link routing. Never infer support from the legacy "1.0" status.
use crate::{protocol::frame, BleError, Result};
use serde::{Deserialize, Serialize};

pub const QUERY: [u8; 5] = [0xaa, 0xbb, 0xa2, 0xcc, 0xdd];
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
