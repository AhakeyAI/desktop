#!/usr/bin/env python3
"""Check the CI artifact's required components and source metadata.

This is a composition check. Public release signature/notarization validation
remains in verify_release_installer.py and the protected promotion workflow.
"""
import argparse
import json
import os
from pathlib import Path
import plistlib


def verify(app, source_commit):
    contents = app / "Contents"
    for name in ("AhaKeyConfig", "ahakeyconfig-agent"):
        executable = contents / "MacOS" / name
        if not executable.is_file() or executable.is_symlink() or not os.access(executable, os.X_OK):
            raise ValueError("Missing regular executable: " + name)
    info = contents / "Info.plist"
    if info.stat().st_size > 65_536:
        raise ValueError("Oversized application metadata")
    metadata = plistlib.loads(info.read_bytes())
    if metadata.get("AhaKeyGitCommit") != source_commit:
        raise ValueError("Application source commit mismatch")
    if metadata.get("CFBundleExecutable") != "AhaKeyConfig" or metadata.get("CFBundleIdentifier") != "lab.jawa.ahakeyconfig":
        raise ValueError("Unexpected application identity")
    for key in ("CFBundleShortVersionString", "CFBundleVersion", "NSBluetoothAlwaysUsageDescription",
                "NSMicrophoneUsageDescription", "NSSpeechRecognitionUsageDescription", "NSAppleEventsUsageDescription"):
        if not isinstance(metadata.get(key), str) or not metadata[key].strip():
            raise ValueError("Missing application field: " + key)
    minimum = tuple(int(part) for part in metadata.get("LSMinimumSystemVersion", "0").split("."))
    if minimum < (13,):
        raise ValueError("Application minimum macOS is below the Swift package target")
    locales = metadata.get("CFBundleLocalizations", [])
    for language in ("en", "zh-Hans"):
        if language not in locales:
            raise ValueError("Missing declared language: " + language)
        for name in ("InfoPlist.strings", "Localizable.strings"):
            resource = contents / "Resources" / (language + ".lproj") / name
            if not resource.is_file() or not resource.stat().st_size:
                raise ValueError("Missing language resource: " + language + "/" + name)
    return {"sourceCommit": source_commit, "version": metadata["CFBundleShortVersionString"],
            "build": metadata["CFBundleVersion"], "minimumMacOS": metadata["LSMinimumSystemVersion"],
            "mainAndAgent": True, "languages": ["en", "zh-Hans"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--source-commit", required=True)
    args = parser.parse_args()
    print(json.dumps(verify(args.app, args.source_commit), indent=2))


if __name__ == "__main__":
    main()
