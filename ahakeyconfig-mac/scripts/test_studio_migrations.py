#!/usr/bin/env python3
"""Run the production draft migrations with real English and Chinese bundle resources.

SwiftPM's test runner does not bundle the app's localizations. This small XCTest
host uses the same migration tests and sources, ensuring English regressions are
visible even on a Chinese development machine (and vice versa).
"""

import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile


def main():
    app_root = Path(__file__).resolve().parents[1]
    platform = subprocess.check_output(
        ["xcrun", "--show-sdk-platform-path"], text=True
    ).strip()
    frameworks = str(Path(platform) / "Developer/Library/Frameworks")
    libraries = str(Path(platform) / "Developer/usr/lib")
    with tempfile.TemporaryDirectory(prefix="ahakey-migration-tests-") as temporary:
        directory = Path(temporary)
        contents = directory / "MigrationTests.app/Contents"
        executable = contents / "MacOS/MigrationTests"
        executable.parent.mkdir(parents=True)
        resources = contents / "Resources"
        resources.mkdir()
        for language in ["en", "zh-Hans"]:
            shutil.copytree(app_root / f"Resources/{language}.lproj", resources / f"{language}.lproj")
        with (contents / "Info.plist").open("wb") as output:
            plistlib.dump({
                "CFBundleExecutable": "MigrationTests",
                "CFBundleIdentifier": "lab.jawa.ahakeyconfig.migration-tests",
                "CFBundleDevelopmentRegion": "zh-Hans",
                "CFBundleLocalizations": ["en", "zh-Hans"],
                "CFBundlePackageType": "APPL",
            }, output)
        driver = directory / "main.swift"
        driver.write_text('''import Foundation
import XCTest
let language = ProcessInfo.processInfo.environment["AHAKEY_TEST_LANGUAGE"]!
UserDefaults.standard.setVolatileDomain(["AppleLanguages": [language]], forName: UserDefaults.argumentDomain)
let expected = language == "en" ? "Return" : "回车"
precondition(NSLocalizedString("回车", comment: "") == expected, "Test host did not load the requested localization")
let suite = StudioDraftMigrationTests.defaultTestSuite
suite.run()
guard let result = suite.testRun, result.executionCount > 0, result.hasSucceeded else { exit(1) }
''')
        subprocess.run([
            "xcrun", "swiftc", "-D", "STANDALONE_MIGRATION_TESTS",
            "-I", libraries, "-L", libraries,
            "-F", frameworks, "-Xlinker", "-rpath", "-Xlinker", frameworks,
            "-Xlinker", "-rpath", "-Xlinker", libraries,
            str(app_root / "Sources/Models/AhaKeyStudioModels.swift"),
            str(app_root / "Sources/BLE/AhaKeyProtocol.swift"),
            str(app_root / "Sources/Utilities/DefaultOLEDAssets.swift"),
            str(app_root / "Tests/AhaKeyConfigTests/StudioDraftMigrationTests.swift"),
            str(driver), "-o", str(executable),
        ], check=True)
        for language in ["en", "zh-Hans"]:
            print(f"Testing Studio migrations in {language}", flush=True)
            subprocess.run([str(executable)], check=True, env={**os.environ, "AHAKEY_TEST_LANGUAGE": language})


if __name__ == "__main__":
    main()
