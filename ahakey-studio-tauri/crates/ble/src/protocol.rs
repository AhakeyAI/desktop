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

/// Firmware ACK frame on 0x7344: AA BB <cmd echo> <status> CC DD.
/// Per docs/ble-protocol.md section 9, status 0 is success and any other value
/// is a rejection. Status-query data frames (13 bytes, cmd echo 0x00) are not
/// ACKs and stay handled by parse_status.
pub fn parse_ack(bytes: &[u8]) -> Option<(u8, u8)> {
    let len = bytes.len();
    if len < 6 || bytes[..2] != [0xaa, 0xbb] || bytes[len - 2..] != [0xcc, 0xdd] {
        return None;
    }
    if parse_status(bytes).is_some() {
        return None;
    }
    Some((bytes[2], bytes[3]))
}

pub fn frame(command: u8, payload: &[u8]) -> Vec<u8> {
    let mut out = vec![0xaa, 0xbb, command];
    out.extend_from_slice(payload);
    out.extend_from_slice(&[0xcc, 0xdd]);
    out
}

pub(crate) fn needs_lighting_support(frames: &[Vec<u8>]) -> bool {
    frames
        .iter()
        .any(|frame| matches!(frame.get(2), Some(0x84 | 0x85 | 0x91)))
}

pub(crate) fn require_lighting_support(status: &DeviceStatus) -> Result<()> {
    // Legacy firmware reserves this byte as zero and ACKs unknown lighting
    // commands with success. Firmware version 1.0 alone cannot distinguish it
    // from compatible community firmware, which reports brightness in 1..=100.
    if !(1..=100).contains(&status.light_brightness) {
        return Err(BleError::Invalid(
            "固件未报告可配置灯效能力；未写入配置，请升级兼容固件或仅写入四键".into(),
        ));
    }
    Ok(())
}

pub(crate) fn confirm_config_status(frames: &[Vec<u8>], status: &DeviceStatus) -> Result<()> {
    for (command, actual, name) in [
        (0x85, status.light_brightness, "亮度"),
        (0x92, status.work_mode, "工作模式"),
    ] {
        if let Some(expected) = frames
            .iter()
            .rev()
            .find(|frame| frame.get(2) == Some(&command))
            .and_then(|frame| frame.get(3))
        {
            if actual != *expected {
                return Err(BleError::Invalid(format!(
                    "{name}回读不一致（期望 {expected}，实际 {actual}）；未确认保存"
                )));
            }
        }
    }
    Ok(())
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
    fn ack_frames_parse_and_rejections_surface() {
        assert_eq!(
            parse_ack(&[0xaa, 0xbb, 0x73, 0, 0xcc, 0xdd]),
            Some((0x73, 0))
        );
        assert_eq!(
            parse_ack(&[0xaa, 0xbb, 0x92, 3, 0xcc, 0xdd]),
            Some((0x92, 3))
        );
        // A status-query response is data, not an ACK.
        let status = [0xaa, 0xbb, 0, 46, 50, 1, 0, 1, 0, 1, 35, 0xcc, 0xdd];
        assert!(parse_ack(&status).is_none());
        assert!(parse_ack(&[0xaa, 0xbb, 0x92, 0]).is_none());
        assert!(parse_ack(&[1, 2, 3, 4, 5, 6]).is_none());
    }
    #[test]
    fn validate_entire_batch() {
        let mut p = profiles();
        p[3].keys[3].hid_codes = vec![1; 10];
        assert!(profile_frames(&p, 0, 50).is_err());
        assert!(profile_frames(&profiles(), 4, 50).is_err());
    }

    #[test]
    fn legacy_success_ack_does_not_authorize_lighting_writes() {
        let legacy = parse_status(&[0xaa, 0xbb, 0, 65, 50, 1, 0, 0, 0, 0, 0, 0xcc, 0xdd]).unwrap();
        assert_eq!(parse_ack(&frame(0x91, &[0])), Some((0x91, 0)));
        assert!(require_lighting_support(&legacy).is_err());
        assert!(needs_lighting_support(
            &profile_frames(&profiles(), 0, 35).unwrap()
        ));
        assert!(needs_lighting_support(&[frame(0x91, &[2])]));
        assert!(needs_lighting_support(&[frame(0x85, &[35])]));
        assert!(!needs_lighting_support(
            &key_frames(0, &profiles()[0].keys).unwrap()
        ));
        let mut compatible = legacy;
        compatible.light_brightness = 35;
        assert!(require_lighting_support(&compatible).is_ok());
        compatible.light_brightness = 255;
        assert!(require_lighting_support(&compatible).is_err());
    }

    #[test]
    fn profile_readback_requires_both_mode_and_brightness() {
        let frames = profile_frames(&profiles(), 2, 70).unwrap();
        let mut status =
            parse_status(&[0xaa, 0xbb, 0, 65, 50, 1, 0, 2, 0, 0, 70, 0xcc, 0xdd]).unwrap();
        assert!(confirm_config_status(&frames, &status).is_ok());
        status.light_brightness = 35;
        assert!(confirm_config_status(&frames, &status).is_err());
        status.light_brightness = 70;
        status.work_mode = 0;
        assert!(confirm_config_status(&frames, &status).is_err());
        // Key-only writes do not claim to change mode or brightness.
        assert!(
            confirm_config_status(&key_frames(0, &profiles()[0].keys).unwrap(), &status).is_ok()
        );
    }
}
