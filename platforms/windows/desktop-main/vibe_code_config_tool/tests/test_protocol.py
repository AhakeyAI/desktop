import unittest

from src.comm.protocol import parse_pic_state_response


class ParsePicStateResponseTests(unittest.TestCase):
    def test_parse_pic_state_response_ignores_trailing_bytes(self):
        payload = bytes([1, 2, 0, 3, 0, 4, 0, 5, 0, 99])

        self.assertEqual(
            parse_pic_state_response(payload),
            {
                "mode": 1,
                "start_index": 2,
                "pic_length": 3,
                "frame_interval": 4,
                "all_mode_max_pic": 5,
            },
        )


if __name__ == "__main__":
    unittest.main()
