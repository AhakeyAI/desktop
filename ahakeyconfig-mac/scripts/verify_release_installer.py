#!/usr/bin/env python3
"""Inspect an already composition-verified DMG; never install or execute it."""
import hashlib
import json
import pathlib
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile


def read_json(path):
    if path.stat().st_size > 1_048_576:
        raise ValueError("Oversized release metadata")
    return json.loads(path.read_bytes())


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1_048_576), b""):
            result.update(block)
    return result.hexdigest()


def run(args):
    return subprocess.run(args, check=True, capture_output=True, timeout=120)


def verify_signature(path, team, execute, command):
    command(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(path)])
    info = command(["/usr/bin/codesign", "--display", "--verbose=4", str(path)]).stderr.decode("utf-8", errors="replace")
    lines = info.splitlines()
    if f"TeamIdentifier={team}" not in lines or not any(line.startswith("Authority=Developer ID Application:") for line in lines):
        raise ValueError("Installer or application has an unexpected signing identity")
    if execute and not re.search(r"^CodeDirectory .*flags=.*\(.*runtime.*\)", info, re.MULTILINE):
        raise ValueError("Application and Agent require hardened runtime")


def verify(root, report_path, commit, version, team, command=run):
    if not re.fullmatch(r"[0-9a-f]{40}", commit) or not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise ValueError("Invalid pinned release identity")
    root = root.resolve(strict=True)
    manifest = read_json(root / "composition.json")
    report = read_json(report_path)
    client = manifest["client"]
    if client["sourceCommit"] != commit or report["clientCommit"] != commit or client["version"] != version:
        raise ValueError("Tag, composition and verified report disagree")
    reference = client["installer"]
    installer = (root / reference["path"]).resolve(strict=True)
    if not installer.is_relative_to(root) or not installer.is_file() or installer.suffix.lower() != ".dmg":
        raise ValueError("Expected a contained DMG installer")
    if installer.stat().st_size != reference["byteCount"] or digest(installer) != reference["sha256"] or report["installerSHA256"] != reference["sha256"]:
        raise ValueError("Tested installer bytes changed")

    # Copy to a fixed output name outside the downloaded evidence tree. The
    # same bytes inspected here are uploaded; no re-signing or rebuilding.
    staging = pathlib.Path(tempfile.mkdtemp(prefix="ahakey-verified-release-"))
    verified = staging / "AhaKey-Studio-macOS.dmg"
    try:
        shutil.copyfile(installer, verified)
        if digest(verified) != reference["sha256"]:
            raise ValueError("Installer changed while staging")
        verify_signature(verified, team, False, command)
        command(["/usr/bin/xcrun", "stapler", "validate", str(verified)])
        command(["/usr/sbin/spctl", "--assess", "--type", "open", "--context", "context:primary-signature", str(verified)])
        with tempfile.TemporaryDirectory(prefix="ahakey-release-inspect-") as directory:
            mount = pathlib.Path(directory).resolve(strict=True)
            attached = False
            try:
                command(["/usr/bin/hdiutil", "attach", str(verified), "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", str(mount)])
                attached = True
                app = (mount / "AhaKey Studio.app").resolve(strict=True)
                if not app.is_relative_to(mount):
                    raise ValueError("Application escapes read-only mount")
                verify_signature(app, team, True, command)
                agent = app / "Contents/MacOS/ahakeyconfig-agent"
                verify_signature(agent, team, True, command)
                with (app / "Contents/Info.plist").open("rb") as stream:
                    info = plistlib.load(stream)
                if info.get("AhaKeyGitCommit") != commit or info.get("CFBundleShortVersionString") != version or info.get("CFBundleIdentifier") != "lab.jawa.ahakeyconfig":
                    raise ValueError("Signed application does not match the tested client")
            finally:
                if attached:
                    command(["/usr/bin/hdiutil", "detach", str(mount)])
                else:
                    # Attach may have partially succeeded before an error.
                    try:
                        command(["/usr/bin/hdiutil", "detach", str(mount)])
                    except (subprocess.SubprocessError, OSError):
                        pass
        if digest(verified) != reference["sha256"]:
            raise ValueError("Installer bytes changed during inspection")
        return verified
    except BaseException:
        shutil.rmtree(staging, ignore_errors=True)
        raise


if __name__ == "__main__":
    try:
        if len(sys.argv) != 6:
            raise ValueError("Usage: verify_release_installer.py ROOT REPORT COMMIT VERSION DEVELOPER_TEAM")
        result = verify(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), *sys.argv[3:])
        print(f"installer={result}")
    except (ValueError, KeyError, TypeError, OSError, subprocess.SubprocessError) as error:
        print(f"Release installer verification failed: {error}", file=sys.stderr)
        sys.exit(1)
