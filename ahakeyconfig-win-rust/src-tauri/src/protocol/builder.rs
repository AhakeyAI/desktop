//! AhaKey protocol high-level command builders.
//!
//! Mirrors the macOS `AhaKeyCommand` (Swift) static methods and the Java
//! `AhaKeyProtocol` static methods, byte-for-byte.
//!
//! Each function returns the exact bytes the macOS / Java side would send.
//! Verified by `cargo test` cases tagged `*_byte_identical_to_macos`.
//!
//! Frame format:
//!   [AA BB] [cmd:1] [payload:N] [CC DD]
//!
//! Constraints:
//! - `mode`: 0-3
//! - `keyIndex`: 0-3 (Key1-Key4)
//! - `brightness`: 1-100
//! - `effect`: 0-N (light effect index)
//! - OLED startIndex must be 4096-byte aligned (flash sector size)

use crate::protocol::codec::ProtocolCodec;
use crate::protocol::packet::{
    AhaKeyCommand, KeySubType, OLED_CHUNK_SIZE, OLED_FACTORY_RESERVED_SLOTS,
    OLED_MAX_FRAMES_PER_MODE,
};

/// Clamp `mode` to 0-3
fn clamp_mode(mode: u8) -> u8 {
    mode.min(3)
}

/// Clamp `keyIndex` to 0-3
fn clamp_key_index(key_index: u8) -> u8 {
    key_index.min(3)
}

/// Clamp `brightness` to 1-100
fn clamp_brightness(brightness: u8) -> u8 {
    brightness.clamp(1, 100)
}

/// Convert `mode` to its starting sector index.
///
/// Matches macOS `oledStartIndex(forMode:)`:
/// `OLED_FACTORY_RESERVED_SLOTS + min(3, mode) * OLED_MAX_FRAMES_PER_MODE`
fn oled_start_index(mode: u8) -> u16 {
    (OLED_FACTORY_RESERVED_SLOTS + (clamp_mode(mode) as usize) * OLED_MAX_FRAMES_PER_MODE) as u16
}

// =============================================================================
// Device query / control
// =============================================================================

/// Device status query: `AA BB 00 CC DD`
pub fn query_device_status() -> Vec<u8> {
    ProtocolCodec::encode_no_payload(AhaKeyCommand::QueryDeviceStatus)
}

/// Query device capabilities: `AA BB 99 CC DD`
pub fn query_capabilities() -> Vec<u8> {
    ProtocolCodec::encode_no_payload(AhaKeyCommand::Capabilities)
}

/// Save config to device Flash: `AA BB 04 CC DD`
pub fn save_config() -> Vec<u8> {
    ProtocolCodec::encode_no_payload(AhaKeyCommand::SaveConfig)
}

/// Change device name: `AA BB 01 [utf8...] CC DD`
pub fn change_name(name: &str) -> Vec<u8> {
    // macOS limits name to ~20 ASCII bytes; truncate conservatively
    let name_bytes: Vec<u8> = name.as_bytes().iter().take(20).copied().collect();
    ProtocolCodec::encode(AhaKeyCommand::ChangeName, &name_bytes)
}

/// Change BLE Appearance: `AA BB 02 [appearance] CC DD`
pub fn change_appearance(appearance: u8) -> Vec<u8> {
    ProtocolCodec::encode(AhaKeyCommand::ChangeAppearance, &[appearance])
}

// =============================================================================
// Work mode / lighting
// =============================================================================

/// Switch work mode 0-3: `AA BB 92 [mode] CC DD`
pub fn set_work_mode(mode: u8) -> Vec<u8> {
    ProtocolCodec::encode(AhaKeyCommand::SetWorkMode, &[clamp_mode(mode)])
}

/// Set global WS2812 brightness 1-100: `AA BB 85 [brightness] CC DD`
pub fn set_brightness(brightness: u8) -> Vec<u8> {
    ProtocolCodec::encode(AhaKeyCommand::SetBrightness, &[clamp_brightness(brightness)])
}

/// Preview a light effect (not persisted): `AA BB 91 [effect] CC DD`
///
/// Swift names this `previewLightEffect`, Java `setLightEffect`; both share
/// command code 0x91.
pub fn preview_light_effect(effect: u8) -> Vec<u8> {
    ProtocolCodec::encode(AhaKeyCommand::PreviewLightEffect, &[effect])
}

/// IDE state to LED color: `AA BB 90 [state] CC DD`
pub fn update_state(state: u8) -> Vec<u8> {
    ProtocolCodec::encode(AhaKeyCommand::UpdateState, &[state])
}

/// Set per-mode per-state LED effect mapping: `AA BB 84 [mode] [effect_codes...] CC DD`
pub fn set_light_mapping(mode: u8, effect_codes: &[u8]) -> Vec<u8> {
    let mut payload = vec![clamp_mode(mode)];
    payload.extend_from_slice(effect_codes);
    ProtocolCodec::encode(AhaKeyCommand::SetLightMapping, &payload)
}

// =============================================================================
// Key configuration
// =============================================================================

/// Map a key to a HID shortcut: `AA BB 73 73 [mode] [key_index] [hid_codes...] CC DD`
pub fn set_key_mapping(mode: u8, key_index: u8, hid_codes: &[u8]) -> Vec<u8> {
    let mut payload = vec![
        KeySubType::Shortcut as u8,
        clamp_mode(mode),
        clamp_key_index(key_index),
    ];
    payload.extend_from_slice(hid_codes);
    ProtocolCodec::encode(AhaKeyCommand::UpdateCustomKey, &payload)
}

/// Set a key's LCD text description: `AA BB 73 75 [mode] [key_index] [utf8...] CC DD`
///
/// `text` truncated to 20 ASCII bytes.
pub fn set_key_description(mode: u8, key_index: u8, text: &str) -> Vec<u8> {
    let text_bytes: Vec<u8> = text.as_bytes().iter().take(20).copied().collect();
    let mut payload = vec![
        KeySubType::Description as u8,
        clamp_mode(mode),
        clamp_key_index(key_index),
    ];
    payload.extend_from_slice(&text_bytes);
    ProtocolCodec::encode(AhaKeyCommand::UpdateCustomKey, &payload)
}

/// Set a key's macro: `AA BB 73 74 [mode] [key_index] [action, param, ...] CC DD`
pub fn set_key_macro(mode: u8, key_index: u8, macro_data: &[u8]) -> Vec<u8> {
    let mut payload = vec![
        KeySubType::Macro as u8,
        clamp_mode(mode),
        clamp_key_index(key_index),
    ];
    payload.extend_from_slice(macro_data);
    ProtocolCodec::encode(AhaKeyCommand::UpdateCustomKey, &payload)
}

// =============================================================================
// OLED large data write
// =============================================================================

/// Read picture state: `AA BB 83 [mode] CC DD`
pub fn read_pic_state(mode: u8) -> Vec<u8> {
    ProtocolCodec::encode(AhaKeyCommand::ReadPicState, &[clamp_mode(mode)])
}

/// Prepare large data write: `AA BB 80 [flag:1] [chunk_len:2 LE] [address:4 LE] CC DD`
///
/// `address` must be 4096-byte aligned (flash sector size).
/// `chunk_length` must equal `OLED_CHUNK_SIZE` (4096) -- one sector per call.
pub fn prepare_write(chunk_length: u16, address: u32) -> Vec<u8> {
    debug_assert!(
        chunk_length as usize == OLED_CHUNK_SIZE,
        "chunk_length must equal OLED_CHUNK_SIZE"
    );
    debug_assert!(
        address % OLED_CHUNK_SIZE as u32 == 0,
        "address must be OLED_CHUNK_SIZE-aligned"
    );
    let payload = [
        0x00u8, // flag
        (chunk_length & 0xFF) as u8,
        ((chunk_length >> 8) & 0xFF) as u8,
        (address & 0xFF) as u8,
        ((address >> 8) & 0xFF) as u8,
        ((address >> 16) & 0xFF) as u8,
        ((address >> 24) & 0xFF) as u8,
    ];
    ProtocolCodec::encode(AhaKeyCommand::PrepareWrite, &payload)
}

/// Update OLED static picture (metadata only, not picture data):
/// `AA BB 82 [mode] [start_idx:2 LE] [frame_count:2 LE] [delay:2 LE] CC DD`
pub fn update_picture(mode: u8, start_index: u16, frame_count: u16, time_delay_ms: u16) -> Vec<u8> {
    let payload = [
        clamp_mode(mode),
        (start_index & 0xFF) as u8,
        ((start_index >> 8) & 0xFF) as u8,
        (frame_count & 0xFF) as u8,
        ((frame_count >> 8) & 0xFF) as u8,
        (time_delay_ms & 0xFF) as u8,
        ((time_delay_ms >> 8) & 0xFF) as u8,
    ];
    ProtocolCodec::encode(AhaKeyCommand::UpdatePic, &payload)
}

/// Convenience: build `update_picture` for a given mode, auto-computing startIndex.
pub fn update_picture_for_mode(mode: u8, frame_count: u16, time_delay_ms: u16) -> Vec<u8> {
    update_picture(mode, oled_start_index(mode), frame_count, time_delay_ms)
}

// =============================================================================
// Tests: byte-identical to macOS Swift
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    /// Byte-identical to macOS `setKeyMapping(mode:0, keyIndex:0, hidCodes:[0x04, 0x05])`:
    /// `AA BB 73 73 00 00 04 05 CC DD`
    #[test]
    fn test_set_key_mapping_byte_identical_to_macos() {
        let frame = set_key_mapping(0, 0, &[0x04, 0x05]);
        assert_eq!(
            frame,
            vec![0xAA, 0xBB, 0x73, 0x73, 0x00, 0x00, 0x04, 0x05, 0xCC, 0xDD]
        );
    }

    /// Byte-identical to macOS `changeName("Hi")`: `AA BB 01 48 69 CC DD`
    #[test]
    fn test_change_name_byte_identical_to_macos() {
        let frame = change_name("Hi");
        assert_eq!(frame, vec![0xAA, 0xBB, 0x01, 0x48, 0x69, 0xCC, 0xDD]);
    }

    /// Byte-identical to macOS `setBrightness(75)`: `AA BB 85 4B CC DD`
    #[test]
    fn test_set_brightness_byte_identical_to_macos() {
        let frame = set_brightness(75);
        assert_eq!(frame, vec![0xAA, 0xBB, 0x85, 0x4B, 0xCC, 0xDD]);
    }

    /// Byte-identical to macOS `setWorkMode(2)`: `AA BB 92 02 CC DD`
    #[test]
    fn test_set_work_mode_byte_identical_to_macos() {
        let frame = set_work_mode(2);
        assert_eq!(frame, vec![0xAA, 0xBB, 0x92, 0x02, 0xCC, 0xDD]);
    }

    /// Byte-identical to macOS `readPicState(mode:0)`: `AA BB 83 00 CC DD`
    #[test]
    fn test_read_pic_state_byte_identical_to_macos() {
        let frame = read_pic_state(0);
        assert_eq!(frame, vec![0xAA, 0xBB, 0x83, 0x00, 0xCC, 0xDD]);
    }

    /// Byte-identical to macOS `setKeyDescription(mode:0, keyIndex:0, text:"OK")`:
    /// `AA BB 73 75 00 00 4F 4B CC DD`
    #[test]
    fn test_set_key_description_byte_identical_to_macos() {
        let frame = set_key_description(0, 0, "OK");
        assert_eq!(
            frame,
            vec![0xAA, 0xBB, 0x73, 0x75, 0x00, 0x00, 0x4F, 0x4B, 0xCC, 0xDD]
        );
    }

    /// Byte-identical to macOS `prepareWrite(flag:0, chunkLength:4096, address:0x1000)`:
    /// `AA BB 80 00 00 10 00 10 00 00 CC DD`
    #[test]
    fn test_prepare_write_byte_identical_to_macos() {
        let frame = prepare_write(OLED_CHUNK_SIZE as u16, 0x1000);
        assert_eq!(
            frame,
            vec![0xAA, 0xBB, 0x80, 0x00, 0x00, 0x10, 0x00, 0x10, 0x00, 0x00, 0xCC, 0xDD]
        );
    }

    /// Byte-identical to macOS `setLightMapping(mode:1, effectCodes:[0x02, 0x03])`:
    /// `AA BB 84 01 02 03 CC DD`
    #[test]
    fn test_set_light_mapping_byte_identical_to_macos() {
        let frame = set_light_mapping(1, &[0x02, 0x03]);
        assert_eq!(frame, vec![0xAA, 0xBB, 0x84, 0x01, 0x02, 0x03, 0xCC, 0xDD]);
    }

    /// Boundary: brightness > 100 clamps to 100
    #[test]
    fn test_brightness_clamp_high() {
        let frame = set_brightness(255);
        assert_eq!(frame, vec![0xAA, 0xBB, 0x85, 0x64, 0xCC, 0xDD]); // 0x64 = 100
    }

    /// Boundary: brightness < 1 clamps to 1
    #[test]
    fn test_brightness_clamp_low() {
        let frame = set_brightness(0);
        assert_eq!(frame, vec![0xAA, 0xBB, 0x85, 0x01, 0xCC, 0xDD]);
    }

    /// Boundary: mode > 3 clamps to 3
    #[test]
    fn test_mode_clamp() {
        let frame = set_work_mode(99);
        assert_eq!(frame, vec![0xAA, 0xBB, 0x92, 0x03, 0xCC, 0xDD]);
    }

    /// Boundary: keyIndex > 3 clamps to 3
    #[test]
    fn test_key_index_clamp() {
        let frame = set_key_mapping(0, 99, &[0x04]);
        assert_eq!(
            frame,
            vec![0xAA, 0xBB, 0x73, 0x73, 0x00, 0x03, 0x04, 0xCC, 0xDD]
        );
    }

    /// Boundary: name > 20 bytes truncates
    #[test]
    fn test_change_name_truncate() {
        let long = "A".repeat(50);
        let frame = change_name(&long);
        let mut expected = vec![0xAA, 0xBB, 0x01];
        expected.extend(std::iter::repeat(b'A').take(20));
        expected.extend_from_slice(&[0xCC, 0xDD]);
        assert_eq!(frame, expected);
    }
}
