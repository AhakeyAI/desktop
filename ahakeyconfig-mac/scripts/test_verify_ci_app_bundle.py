from pathlib import Path
import plistlib
import tempfile
import unittest

from verify_ci_app_bundle import verify


class BundleCompositionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="ahakey-ci-bundle-")
        self.addCleanup(self.directory.cleanup)
        self.app = Path(self.directory.name) / "AhaKey Studio.app"
        self.contents = self.app / "Contents"
        (self.contents / "MacOS").mkdir(parents=True)
        for name in ("AhaKeyConfig", "ahakeyconfig-agent"):
            executable = self.contents / "MacOS" / name
            executable.write_bytes(b"fixture executable")
            executable.chmod(0o755)
        self.metadata = {"AhaKeyGitCommit": "a" * 40, "CFBundleExecutable": "AhaKeyConfig",
            "CFBundleIdentifier": "lab.jawa.ahakeyconfig", "CFBundleShortVersionString": "0.2.3", "CFBundleVersion": "42",
            "LSMinimumSystemVersion": "13.0", "CFBundleLocalizations": ["en", "zh-Hans"]}
        for key in ("NSBluetoothAlwaysUsageDescription", "NSMicrophoneUsageDescription", "NSSpeechRecognitionUsageDescription", "NSAppleEventsUsageDescription"):
            self.metadata[key] = "Fixture usage description"
        self.save()
        for language in ("en", "zh-Hans"):
            root = self.contents / "Resources" / (language + ".lproj")
            root.mkdir(parents=True)
            for name in ("InfoPlist.strings", "Localizable.strings"):
                (root / name).write_text('"fixture" = "fixture";\n')

    def save(self):
        (self.contents / "Info.plist").write_bytes(plistlib.dumps(self.metadata))

    def testCompleteCompositionPasses(self):
        self.assertTrue(verify(self.app, "a" * 40)["mainAndAgent"])

    def testMainOnlyArtifactIsRejected(self):
        (self.contents / "MacOS/ahakeyconfig-agent").unlink()
        with self.assertRaisesRegex(ValueError, "ahakeyconfig-agent"):
            verify(self.app, "a" * 40)

    def testAgentMustBeExecutableAndInsideBundle(self):
        agent = self.contents / "MacOS/ahakeyconfig-agent"
        agent.chmod(0o644)
        with self.assertRaises(ValueError):
            verify(self.app, "a" * 40)
        agent.unlink()
        agent.symlink_to(self.contents / "MacOS/AhaKeyConfig")
        with self.assertRaises(ValueError):
            verify(self.app, "a" * 40)

    def testMissingSourcePermissionAndWrongMinimumAreRejected(self):
        for key, value in [("AhaKeyGitCommit", None), ("NSAppleEventsUsageDescription", ""), ("LSMinimumSystemVersion", "12.0")]:
            with self.subTest(key=key):
                old = self.metadata[key]
                if value is None:
                    del self.metadata[key]
                else:
                    self.metadata[key] = value
                self.save()
                with self.assertRaises(ValueError):
                    verify(self.app, "a" * 40)
                self.metadata[key] = old
        self.save()

    def testIncompleteLanguageResourcesAreRejected(self):
        (self.contents / "Resources/en.lproj/Localizable.strings").unlink()
        with self.assertRaises(ValueError):
            verify(self.app, "a" * 40)


if __name__ == "__main__":
    unittest.main()
