import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest

from hook_lifecycle_fixture import terminate_process_group


class ProcessCleanupTests(unittest.TestCase):
    def testExitedParentDoesNotHideChildThatIgnoresTerm(self):
        with tempfile.TemporaryDirectory(prefix="ahakey-process-cleanup-") as directory:
            root = Path(directory)
            child = root / "child.py"
            ready = root / "ready"
            child.write_text("import signal,time,pathlib\nsignal.signal(signal.SIGTERM, signal.SIG_IGN)\npathlib.Path(" + repr(str(ready)) + ").touch()\nwhile True: time.sleep(.1)\n")
            parent = "import subprocess,sys,time,pathlib\nsubprocess.Popen([sys.executable," + repr(str(child)) + "],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)\np=pathlib.Path(" + repr(str(ready)) + ")\nfor _ in range(100):\n if p.exists(): break\n time.sleep(.01)\nassert p.exists()\n"
            process = subprocess.Popen([sys.executable, "-c", parent], start_new_session=True,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                self.assertEqual(process.wait(timeout=5), 0)
                self.assertTrue(ready.exists())
                terminate_process_group(process, grace_seconds=.5)
                with self.assertRaises(ProcessLookupError):
                    os.killpg(process.pid, 0)
            finally:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait(timeout=5)


if __name__ == "__main__":
    unittest.main()
