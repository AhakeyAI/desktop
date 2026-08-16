import unittest
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from src.comm.protocol import (
    CAP_STANDBY_TIMEOUT_V2,
    CAP_FACTORY_RESET_V1,
    CAP_VOICE_KEY_DUAL_V1,
    DeviceCmd,
    build_device_frame,
    parse_capabilities_response,
    parse_standby_timeout_response,
    build_voice_key_config,
    parse_voice_key_config_response,
)


class ProtocolV2Test(unittest.TestCase):
    def test_command_frames(self):
        self.assertEqual(
            build_device_frame(DeviceCmd.QUERY_CAPABILITIES),
            b"\xAA\xBB\x9F\xCC\xDD",
        )
        self.assertEqual(
            build_device_frame(DeviceCmd.STANDBY_TIMEOUT, b"\x1E\x00"),
            b"\xAA\xBB\x95\x1E\x00\xCC\xDD",
        )
        self.assertEqual(
            build_device_frame(DeviceCmd.FACTORY_RESET, b"\xA5\x5A"),
            b"\xAA\xBB\x96\xA5\x5A\xCC\xDD",
        )

    def test_capabilities(self):
        result = parse_capabilities_response(
            b"\x02\x01\x01\x01\x01\x03\x00\x00\x00\x07"
        )
        self.assertEqual(result["protocol_major"], 2)
        self.assertEqual(result["hardware_revision"], 1)
        self.assertEqual(
            result["capability_bits"],
            CAP_STANDBY_TIMEOUT_V2 | CAP_FACTORY_RESET_V1,
        )
        self.assertTrue(result["supports_standby_timeout_v2"])
        self.assertTrue(result["supports_factory_reset_v1"])
        self.assertEqual(result["firmware_patch"], 7)

    def test_standby_timeout(self):
        self.assertEqual(parse_standby_timeout_response(b"\x1E\x00"), 30)

    def test_dual_voice_key(self):
        payload = build_voice_key_config(b"\xE6", b"\xE0\xE3")
        self.assertEqual(payload, b"\x01\xE6\x02\xE0\xE3")
        self.assertEqual(
            build_device_frame(DeviceCmd.VOICE_KEY_CONFIG, payload),
            b"\xAA\xBB\x97\x01\xE6\x02\xE0\xE3\xCC\xDD",
        )
        parsed = parse_voice_key_config_response(payload + b"\x5E\x01")
        self.assertEqual(parsed["short_codes"], b"\xE6")
        self.assertEqual(parsed["long_codes"], b"\xE0\xE3")
        self.assertEqual(parsed["long_press_ms"], 350)
        self.assertEqual(build_voice_key_config(b"", b""), b"\x00\x00")

    def test_dual_voice_capability(self):
        result = parse_capabilities_response(
            b"\x02\x02\x01\x01\x01\x07\x00\x00\x00\x00"
        )
        self.assertTrue(result["supports_voice_key_dual_v1"])
        self.assertEqual(
            result["capability_bits"],
            CAP_STANDBY_TIMEOUT_V2 | CAP_FACTORY_RESET_V1 | CAP_VOICE_KEY_DUAL_V1,
        )


if __name__ == "__main__":
    unittest.main()
