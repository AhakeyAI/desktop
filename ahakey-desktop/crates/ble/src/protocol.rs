//! AhaKey GATT payloads, identical to the existing Java/Swift firmware protocol.
use crate::{BleError, Result};
use serde::{Deserialize, Serialize};

pub const F17: u8 = 0x6c;
pub const F18: u8 = 0x6d;
pub const QUERY_STATUS: [u8; 5] = [0xaa, 0xbb, 0x00, 0xcc, 0xdd];

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct DeviceStatus {
    pub battery_level: u8,
    pub signal: i8,
    pub firmware_main: u8,
    pub firmware_sub: u8,
    pub work_mode: u8,
    pub light_mode: u8,
    pub switch_state: u8,
    pub light_brightness: u8,
}

pub fn parse_status(bytes: &[u8]) -> Option<DeviceStatus> {
    if bytes.len() != 13 || bytes[..3] != [0xaa, 0xbb, 0] || bytes[11..] != [0xcc, 0xdd] {
        return None;
    }
    Some(DeviceStatus {
        battery_level: bytes[3],
        signal: bytes[4] as i8,
        firmware_main: bytes[5],
        firmware_sub: bytes[6],
        work_mode: bytes[7],
        light_mode: bytes[8],
        switch_state: bytes[9],
        light_brightness: bytes[10],
    })
}

pub fn frame(command: u8, payload: &[u8]) -> Vec<u8> {
    let mut out = vec![0xaa, 0xbb, command];
    out.extend_from_slice(payload);
    out.extend_from_slice(&[0xcc, 0xdd]);
    out
}

/// Raw HID usage list (modifiers are usages E0..E7, not a modifier bitmap).
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct KeyConfig {
    pub hid_codes: Vec<u8>,
    pub description: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProfileConfig {
    pub keys: [KeyConfig; 4],
    pub light_effects: Vec<u8>,
}

/// Only one mode's four keys; do not overwrite other modes or lighting.
pub fn key_frames(mode: u8, keys: &[KeyConfig; 4]) -> Result<Vec<Vec<u8>>> {
    if mode > 3 || keys.iter().any(|k| k.hid_codes.len() > 9) {
        return Err(BleError::Invalid("Invalid mode or HID sequence".into()));
    }
    let mut frames = vec![];
    for (index, key) in keys.iter().enumerate() {
        let mut payload = vec![0x73, mode, index as u8];
        payload.extend_from_slice(&key.hid_codes);
        frames.push(frame(0x73, &payload));
        let mut label = vec![0x75, mode, index as u8];
        label.extend(
            key.description
                .bytes()
                .filter(|b| (0x20..=0x7e).contains(b))
                .take(20),
        );
        frames.push(frame(0x73, &label));
    }
    frames.push(frame(0x04, &[]));
    Ok(frames)
}

/// Device key indices are 0..3. A batch is fully validated before any writes.
pub fn profile_frames(
    profiles: &[ProfileConfig; 4],
    active_mode: u8,
    brightness: u8,
) -> Result<Vec<Vec<u8>>> {
    if active_mode > 3 || !(1..=100).contains(&brightness) {
        return Err(BleError::Invalid(
            "mode must be 0..3; brightness must be 1..100".into(),
        ));
    }
    let mut out = Vec::new();
    for (mode, profile) in profiles.iter().enumerate() {
        if profile.light_effects.len() != 9 {
            return Err(BleError::Invalid(
                "exactly nine AI light effects are required (firmware states 0..8)".into(),
            ));
        }
        for (key, config) in profile.keys.iter().enumerate() {
            if config.hid_codes.len() > 9 {
                return Err(BleError::Invalid("at most nine HID usages per key".into()));
            }
            let mut payload = vec![0x73, mode as u8, key as u8];
            payload.extend_from_slice(&config.hid_codes);
            out.push(frame(0x73, &payload));
            let mut payload = vec![0x75, mode as u8, key as u8];
            payload.extend(
                config
                    .description
                    .bytes()
                    .filter(|b| (0x20..=0x7e).contains(b))
                    .take(20),
            );
            out.push(frame(0x73, &payload));
        }
        let mut payload = vec![mode as u8];
        payload.extend_from_slice(&profile.light_effects);
        out.push(frame(0x84, &payload));
    }
    out.push(frame(0x85, &[brightness]));
    out.push(frame(0x92, &[active_mode]));
    out.push(frame(0x04, &[]));
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn four_key_write_does_not_touch_other_modes_or_lights() {
        let keys = profiles()[0].keys.clone();
        let frames = key_frames(3, &keys).unwrap();
        assert_eq!(frames.len(), 9);
        for frame in &frames[..8] {
            assert_eq!(frame[2], 0x73);
            assert_eq!(frame[4], 3);
        }
        assert_eq!(frames[8], vec![0xaa, 0xbb, 0x04, 0xcc, 0xdd]);
        assert!(key_frames(4, &keys).is_err());
    }
    #[test]
    fn known_status_preserves_signed_rssi() {
        let s = parse_status(&[0xaa, 0xbb, 0, 65, 0xc4, 1, 3, 2, 4, 1, 80, 0xcc, 0xdd]).unwrap();
        assert_eq!(
            (s.battery_level, s.signal, s.work_mode, s.light_brightness),
            (65, -60, 2, 80)
        );
        assert!(parse_status(&[0xaa, 0xbb, 0x90, 1, 0xcc, 0xdd]).is_none());
        assert!(parse_status(&[0; 13]).is_none());
    }
    fn profiles() -> [ProfileConfig; 4] {
        std::array::from_fn(|_| ProfileConfig {
            keys: std::array::from_fn(|_| KeyConfig {
                hid_codes: vec![F18],
                description: "Voice".into(),
            }),
            light_effects: vec![0, 1, 2, 3, 4, 5, 6, 7, 8],
        })
    }
    #[test]
    fn known_profile_bytes_and_save_order() {
        let f = profile_frames(&profiles(), 2, 70).unwrap();
        assert_eq!(f.len(), 39);
        assert_eq!(f[0], vec![0xaa, 0xbb, 0x73, 0x73, 0, 0, 0x6d, 0xcc, 0xdd]);
        assert_eq!(f[36], vec![0xaa, 0xbb, 0x85, 70, 0xcc, 0xdd]);
        assert_eq!(f[37], vec![0xaa, 0xbb, 0x92, 2, 0xcc, 0xdd]);
        assert_eq!(f[38], vec![0xaa, 0xbb, 4, 0xcc, 0xdd]);
    }
    #[test]
    fn validate_entire_batch() {
        let mut p = profiles();
        p[3].keys[3].hid_codes = vec![1; 10];
        assert!(profile_frames(&p, 0, 50).is_err());
        assert!(profile_frames(&profiles(), 4, 50).is_err());
    }
}
