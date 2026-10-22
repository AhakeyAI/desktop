import importlib.util
import json
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("installer_check", pathlib.Path(__file__).with_name("verify_release_installer.py"))
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class InstallerVerificationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = pathlib.Path(self.directory.name)
        self.commit = "a" * 40
        self.team = "P2VFVRZK7P"
        self.installer = self.root / "candidate.dmg"
        self.installer.write_bytes(b"synthetic non-mountable test bytes")
        self.reference = {"path": "candidate.dmg", "byteCount": self.installer.stat().st_size,
                          "sha256": checker.digest(self.installer)}
        self.manifest = {"client": {"sourceCommit": self.commit, "version": "0.2.3", "installer": self.reference}}
        (self.root / "composition.json").write_text(json.dumps(self.manifest))
        self.report = self.root / "report.json"
        self.report.write_text(json.dumps({"clientCommit": self.commit, "installerSHA256": self.reference["sha256"]}))
        self.calls = []
        self.app_commit = self.commit
        self.signing_team = self.team
        self.reject_agent = False

    def command(self, args):
        self.calls.append(args)
        if args[:2] == ["/usr/bin/hdiutil", "attach"]:
            mount = pathlib.Path(args[-1])
            app = mount / "AhaKey Studio.app/Contents"
            app.mkdir(parents=True)
            (app / "MacOS").mkdir()
            (app / "MacOS/ahakeyconfig-agent").write_bytes(b"synthetic agent")
            with (app / "Info.plist").open("wb") as stream:
                plistlib.dump({"AhaKeyGitCommit": self.app_commit, "CFBundleShortVersionString": "0.2.3",
                              "CFBundleIdentifier": "lab.jawa.ahakeyconfig"}, stream)
        if self.reject_agent and args[:2] == ["/usr/bin/codesign", "--verify"] and args[-1].endswith("ahakeyconfig-agent"):
            raise subprocess.CalledProcessError(1, args)
        stderr = (f"TeamIdentifier={self.signing_team}\nAuthority=Developer ID Application: Synthetic Test\n"
                  "CodeDirectory v=20500 size=100 flags=0x10000(runtime) hashes=1\n").encode()
        return subprocess.CompletedProcess(args, 0, stdout=b"", stderr=stderr)

    def verify(self):
        return checker.verify(self.root, self.report, self.commit, "0.2.3", self.team, self.command)

    def testExactInspectedBytesAreStagedAndNeverExecutedOrRebuilt(self):
        result = self.verify()
        self.addCleanup(shutil.rmtree, result.parent)
        self.assertEqual(result.read_bytes(), self.installer.read_bytes())
        self.assertNotEqual(result.parent, self.root)
        self.assertTrue(any(call[:3] == ["/usr/bin/xcrun", "stapler", "validate"] for call in self.calls))
        attach = next(call for call in self.calls if call[:2] == ["/usr/bin/hdiutil", "attach"])
        self.assertIn("-readonly", attach)
        self.assertEqual(self.calls[-1][:2], ["/usr/bin/hdiutil", "detach"])
        self.assertTrue(all(call[0] in ["/usr/bin/codesign", "/usr/bin/xcrun", "/usr/sbin/spctl", "/usr/bin/hdiutil"] for call in self.calls))

    def testChangedInstallerIsRejectedBeforePlatformCommands(self):
        self.installer.write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "bytes changed"):
            self.verify()
        self.assertEqual(self.calls, [])

    def testTagAndCompositionMustAgreeBeforeMount(self):
        with self.assertRaisesRegex(ValueError, "disagree"):
            checker.verify(self.root, self.report, "b" * 40, "0.2.3", self.team, self.command)
        self.assertEqual(self.calls, [])

    def testWrongTeamCannotPassOnAValidSignature(self):
        self.signing_team = "XXXXXXXXXX"
        with self.assertRaisesRegex(ValueError, "signing identity"):
            self.verify()
        self.assertFalse(any(call[:2] == ["/usr/bin/hdiutil", "attach"] for call in self.calls))

    def testSignedAppWrongSourceIsRejectedAndMountDetached(self):
        self.app_commit = "b" * 40
        with self.assertRaisesRegex(ValueError, "tested client"):
            self.verify()
        self.assertEqual(self.calls[-1][:2], ["/usr/bin/hdiutil", "detach"])

    def testNestedAgentSignatureFailureAlsoDetaches(self):
        self.reject_agent = True
        with self.assertRaises(subprocess.CalledProcessError):
            self.verify()
        self.assertEqual(self.calls[-1][:2], ["/usr/bin/hdiutil", "detach"])


if __name__ == "__main__":
    unittest.main()
