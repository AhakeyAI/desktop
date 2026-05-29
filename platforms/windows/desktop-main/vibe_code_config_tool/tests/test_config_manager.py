import os
import tempfile
import unittest

from src.core.config_manager import ConfigManager
from src.core.keymap import KeyboardConfig


class ConfigManagerTests(unittest.TestCase):
    def test_save_then_load_round_trip_current_schema(self):
        fd, path = tempfile.mkstemp(suffix=".json")
        os.close(fd)
        try:
            manager = ConfigManager()
            manager.save(KeyboardConfig(name="RoundTrip"), path)

            loaded = manager.load(path)

            self.assertEqual(loaded.name, "RoundTrip")
        finally:
            os.remove(path)


if __name__ == "__main__":
    unittest.main()
