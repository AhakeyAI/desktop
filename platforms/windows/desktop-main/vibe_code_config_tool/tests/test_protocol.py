import unittest

from src.comm.protocol import parse_status_response


class ParseStatusResponseTests(unittest.TestCase):
    def test_parse_status_response_valid_payload(self):
        payload = bytes([1, 4]) + b"Vibe" + bytes([5]) + b"AA:BB" + bytes([1])

        self.assertEqual(
            parse_status_response(payload),
            {
                "connected": True,
                "name": "Vibe",
                "mac": "AA:BB",
                "is_target": True,
            },
        )

    def test_parse_status_response_empty_payload(self):
        self.assertEqual(parse_status_response(b""), {})

    def test_parse_status_response_single_byte_payload(self):
        self.assertEqual(parse_status_response(b"\x01"), {})

    def test_parse_status_response_truncated_name(self):
        self.assertEqual(parse_status_response(bytes([1, 4]) + b"AB"), {})

    def test_parse_status_response_missing_mac_length(self):
        self.assertEqual(parse_status_response(bytes([1, 1]) + b"A"), {})

    def test_parse_status_response_truncated_mac(self):
        self.assertEqual(parse_status_response(bytes([1, 1]) + b"A" + bytes([4]) + b"BC"), {})

    def test_parse_status_response_missing_is_target_defaults_false(self):
        payload = bytes([1, 1]) + b"A" + bytes([2]) + b"BC"

        self.assertEqual(
            parse_status_response(payload),
            {
                "connected": True,
                "name": "A",
                "mac": "BC",
                "is_target": False,
            },
        )


if __name__ == "__main__":
    unittest.main()
