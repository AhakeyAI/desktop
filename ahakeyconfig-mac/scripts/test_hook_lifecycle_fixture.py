import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from hook_lifecycle_fixture import ensure_claude_fixture_isolated, terminate_process_group, policy_swift_sources


@unittest.skipUnless(sys.platform == "darwin", "Production policy sources use macOS APIs")
class ProductionFixtureCompilationTests(unittest.TestCase):
    def testKimiFixtureCompilesAndRevokesOnlyInsideItsTemporaryDirectory(self):
        sources = Path(__file__).resolve().parents[1] / "Sources/Shared"
        with tempfile.TemporaryDirectory(prefix="ahakey-policy-closure-") as directory:
            root = Path(directory)
            main = root / "main.swift"
            main.write_text('''import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let result = ApprovalAutomationControl.beginRevocation(.kimi, directory: root,
    codexURL: root.appendingPathComponent("codex/config.toml"),
    kimiURL: root.appendingPathComponent("kimi/config.toml"),
    cursorDirectory: root.appendingPathComponent("cursor"))
guard result == .complete else { exit(1) }
''')
            fixture_sources = policy_swift_sources(sources) + [
                sources / "KimiHooksConfiguration.swift", sources / "JSONHooksConfiguration.swift"]
            binary = root / "policy"
            result = subprocess.run(["swiftc", *map(str, fixture_sources), str(main), "-o", str(binary)],
                capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stderr)
            subprocess.run([str(binary), str(root / "state")], check=True, timeout=5)


class ManagedPolicyIsolationTests(unittest.TestCase):
    def testEmptyFixtureAndAbsentPreferencesAreAccepted(self):
        with tempfile.TemporaryDirectory() as directory:
            ensure_claude_fixture_isolated(Path(directory), preference_probe=lambda: False)

    def testManagedFilesDropinsAndBrokenLinksAreRefused(self):
        for name in ("managed-settings.json", "managed-settings.d", "managed-mcp.json", "CLAUDE.md"):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / name
                if name.endswith(".d"):
                    path.mkdir()
                else:
                    path.symlink_to(Path(directory) / "missing-policy")
                with self.assertRaises(RuntimeError):
                    ensure_claude_fixture_isolated(Path(directory), preference_probe=lambda: False)

    def testPreferencesPresentOrUnverifiableRefuseExecution(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(RuntimeError):
                ensure_claude_fixture_isolated(Path(directory), preference_probe=lambda: True)

            def unavailable():
                raise RuntimeError("Unavailable policy source")
            with self.assertRaises(RuntimeError):
                ensure_claude_fixture_isolated(Path(directory), preference_probe=unavailable)


class ProcessCleanupTests(unittest.TestCase):
    def testExitedParentDoesNotHideChildThatIgnoresTerm(self):
        self.check_exited_parent_cleanup()

    def testDarwinOrphanGroupPermissionProbeStillConfirmsNoLiveMembers(self):
        original = os.killpg

        def emulate_darwin(group, sig):
            try:
                return original(group, sig)
            except ProcessLookupError:
                if sig == 0:
                    raise PermissionError("Darwin orphan-group probe")
                raise

        with patch("os.killpg", side_effect=emulate_darwin):
            self.check_exited_parent_cleanup()

    def check_exited_parent_cleanup(self):
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
                result = subprocess.check_output(["/bin/ps", "-axo", "pgid=,stat="], text=True)
                members = [line.split() for line in result.splitlines()]
                self.assertFalse(any(len(fields) == 2 and fields[0] == str(process.pid)
                    and not fields[1].startswith("Z") for fields in members))
            finally:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except (ProcessLookupError, PermissionError):
                    pass
                process.wait(timeout=5)


if __name__ == "__main__":
    unittest.main()
