#!/usr/bin/env python3
"""Single-source helpers for v0.2 release identity. Does not sign or install."""

from __future__ import annotations

import json
import os
import pathlib
import re
import shlex
import sys


REQUIRED = {
    "channel": "v0.2",
    "productVersion": "0.2.0",
    "bundleIdentifier": "lab.jawa.ahakeyconfig",
    "signingIdentifier": "lab.jawa.ahakeyconfig",
    "teamIdentifier": "P2VFVRZK7P",
    "agentLaunchdLabel": "lab.jawa.ahakeyconfig.agent",
    "machServiceName": "lab.jawa.ahakeyconfig.runtime",
    "minimumDarwinMajor": 22,
    "minimumMacOSVersion": "13.0",
}


def load_identity(app_root: pathlib.Path) -> dict:
    path = app_root / "Packaging" / "ReleaseIdentity.json"
    identity = json.loads(path.read_text(encoding="utf-8"))
    for key, value in REQUIRED.items():
        actual = identity.get(key)
        if actual != value:
            raise SystemExit(f"ReleaseIdentity.json {key}={actual!r}, expected {value!r}")
    return identity


def refuse_applications_output(path: str) -> None:
    raw = os.path.abspath(path)
    real = os.path.realpath(raw)
    for candidate in (raw, real):
        if candidate == "/Applications" or candidate.startswith("/Applications/"):
            raise SystemExit(
                f"unsigned packer refuses output under /Applications: {path} → {candidate}"
            )


def extract_embedded_json(swift_path: pathlib.Path) -> dict:
    text = swift_path.read_text(encoding="utf-8")
    match = re.search(
        r"// RELEASE-IDENTITY-JSON-BEGIN\n\s*static let json = #\"\"\"\n(.*)\n\"\"\"#\n\s*// RELEASE-IDENTITY-JSON-END",
        text,
        re.S,
    )
    if not match:
        raise SystemExit(f"missing RELEASE-IDENTITY-JSON markers in {swift_path}")
    return json.loads(match.group(1))


def parse_codesign(path: pathlib.Path) -> dict:
    import subprocess

    proc = subprocess.run(
        ["/usr/bin/codesign", "-dv", "--verbose=4", str(path)],
        capture_output=True,
        text=True,
        check=False,
    )
    output = (proc.stdout or "") + (proc.stderr or "")
    info = {}
    for line in output.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            info[key.strip()] = value.strip()
    return info


def check(app_root: pathlib.Path, candidate: pathlib.Path | None) -> None:
    identity = load_identity(app_root)
    plist_path = app_root / "Packaging" / "LaunchAgent.plist"
    import plistlib

    plist = plistlib.loads(plist_path.read_bytes())
    if plist.get("Label") != identity["agentLaunchdLabel"]:
        raise SystemExit("LaunchAgent Label mismatch")
    services = plist.get("MachServices") or {}
    if services.get(identity["machServiceName"]) is not True:
        raise SystemExit("LaunchAgent MachServices missing runtime endpoint")

    embedded = extract_embedded_json(
        app_root / "Sources" / "Shared" / "AhaKeyReleaseIdentity.swift"
    )
    if embedded != identity:
        raise SystemExit("embedded Swift ReleaseIdentity.json does not match Packaging/ReleaseIdentity.json")

    seam = (app_root / "Sources" / "Shared" / "AhaKeyRuntimeProductionSeam.swift").read_text(
        encoding="utf-8"
    )
    if "AhaKeyReleaseIdentity.current.teamIdentifier" not in seam:
        raise SystemExit("XPC peer Team ID must read AhaKeyReleaseIdentity.current")
    if "AhaKeyReleaseIdentity.current.signingIdentifier" not in seam:
        raise SystemExit("XPC peer signing ID must read AhaKeyReleaseIdentity.current")

    build_sh = (app_root / "scripts" / "build.sh").read_text(encoding="utf-8")
    if '--identifier "$SIGNING_IDENTIFIER"' not in build_sh and "--identifier \"$SIGNING_IDENTIFIER\"" not in build_sh:
        if "--identifier" not in build_sh or "SIGNING_IDENTIFIER" not in build_sh:
            raise SystemExit("build.sh must codesign agent with frozen --identifier")

    package_dmg = (app_root / "scripts" / "package_dmg.sh").read_text(encoding="utf-8")
    ident_token = '--identifier "$SIGNING_IDENTIFIER"'
    if package_dmg.count(ident_token) < 2:
        raise SystemExit("package_dmg.sh must re-sign App and Agent with frozen --identifier")
    if 'Packaging/LaunchAgent.plist' not in package_dmg:
        raise SystemExit("package_dmg.sh must copy Packaging/LaunchAgent.plist beside the App")
    if "verify-release-dmg.sh" not in package_dmg:
        raise SystemExit("package_dmg.sh must run verify-release-dmg.sh as the product gate")
    pack_release = (app_root / "scripts" / "pack-release.sh").read_text(encoding="utf-8")
    if "verify-release-dmg.sh" not in pack_release and "package_dmg.sh" not in pack_release:
        raise SystemExit("pack-release.sh must invoke package_dmg.sh (product DMG gate)")
    verifier = app_root / "scripts" / "verify-release-dmg.sh"
    if not verifier.is_file():
        raise SystemExit("missing scripts/verify-release-dmg.sh")

    if candidate:
        refuse_applications_output(str(candidate))
        app = candidate / "AhaKey Studio.app"
        info = plistlib.loads((app / "Contents" / "Info.plist").read_bytes())
        if info.get("CFBundleIdentifier") != identity["bundleIdentifier"]:
            raise SystemExit("candidate CFBundleIdentifier mismatch")
        if info.get("LSMinimumSystemVersion") != identity["minimumMacOSVersion"]:
            raise SystemExit("candidate LSMinimumSystemVersion mismatch")
        agent = app / "Contents" / "MacOS" / identity["agentBinaryName"]
        if not agent.is_file():
            raise SystemExit(f"missing agent binary {agent}")
        cand_plist = plistlib.loads((candidate / "LaunchAgent.plist").read_bytes())
        if (cand_plist.get("MachServices") or {}).get(identity["machServiceName"]) is not True:
            raise SystemExit("candidate LaunchAgent MachServices missing")
        manifest = json.loads((candidate / "manifest.json").read_text(encoding="utf-8"))
        if manifest.get("signedWithDeveloperID") is not False:
            raise SystemExit("unsigned candidate must set signedWithDeveloperID=false")
        if manifest.get("installsToApplications") is not False:
            raise SystemExit("unsigned candidate must not install to /Applications")
        sig = parse_codesign(app)
        authority = sig.get("Authority", "")
        if "Developer ID Application" in authority:
            raise SystemExit("unsigned candidate must not be Developer ID signed")
        if sig.get("Identifier") != identity["signingIdentifier"]:
            raise SystemExit(
                f"candidate signing identifier {sig.get('Identifier')!r} != {identity['signingIdentifier']!r}"
            )
        team = sig.get("TeamIdentifier", "not set")
        if team not in ("not set", "-", "", None):
            raise SystemExit(f"unsigned candidate must be ad-hoc without Team ID, found {team!r}")
        agent_sig = parse_codesign(agent)
        if agent_sig.get("Identifier") != identity["signingIdentifier"]:
            raise SystemExit("agent signing identifier mismatch")
        if "Developer ID Application" in agent_sig.get("Authority", ""):
            raise SystemExit("agent must not be Developer ID signed in unsigned candidate")

    print("release identity ok")


def _run_codesign(args: list[str]) -> subprocess.CompletedProcess[str]:
    import subprocess

    return subprocess.run(args, capture_output=True, text=True, check=False)


def verify_codesign_strict(path: pathlib.Path) -> None:
    proc = _run_codesign(["/usr/bin/codesign", "--verify", "--strict", str(path)])
    if proc.returncode != 0:
        detail = ((proc.stdout or "") + (proc.stderr or "")).strip()
        raise SystemExit(f"codesign --verify --strict failed for {path}: {detail}")


def verify_developer_id_requirement(path: pathlib.Path, requirement: str) -> None:
    proc = _run_codesign(["/usr/bin/codesign", "-R", f"={requirement}", str(path)])
    if proc.returncode != 0:
        detail = ((proc.stdout or "") + (proc.stderr or "")).strip()
        raise SystemExit(f"frozen Developer ID requirement failed for {path}: {detail}")


def verify_volume(app_root: pathlib.Path, volume: pathlib.Path, expect_developer_id: bool) -> None:
    import plistlib

    identity = load_identity(app_root)
    volume = volume.resolve()
    if not volume.is_dir():
        raise SystemExit(f"volume is not a directory: {volume}")

    apps = [
        path
        for path in volume.iterdir()
        if path.suffix == ".app" and not path.name.startswith(".")
    ]
    expected_app = identity["appBundleFileName"]
    if len(apps) != 1:
        raise SystemExit(f"expected exactly one app, found {[path.name for path in apps]!r}")
    app = apps[0]
    if app.name != expected_app:
        raise SystemExit(f"app name {app.name!r} != {expected_app!r}")

    info = plistlib.loads((app / "Contents" / "Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != identity["bundleIdentifier"]:
        raise SystemExit(
            f"CFBundleIdentifier {info.get('CFBundleIdentifier')!r} != {identity['bundleIdentifier']!r}"
        )
    if info.get("CFBundleShortVersionString") != identity["productVersion"]:
        raise SystemExit(
            f"CFBundleShortVersionString {info.get('CFBundleShortVersionString')!r} != {identity['productVersion']!r}"
        )

    agent = app / "Contents" / "MacOS" / identity["agentBinaryName"]
    if not agent.is_file():
        raise SystemExit(f"missing agent binary {agent}")

    companion = volume / "LaunchAgent.plist"
    if not companion.is_file():
        raise SystemExit("missing companion LaunchAgent.plist")
    plist = plistlib.loads(companion.read_bytes())
    if plist.get("Label") != identity["agentLaunchdLabel"]:
        raise SystemExit(
            f"LaunchAgent Label {plist.get('Label')!r} != {identity['agentLaunchdLabel']!r}"
        )
    services = plist.get("MachServices") or {}
    if services.get(identity["machServiceName"]) is not True:
        raise SystemExit("LaunchAgent MachServices missing frozen runtime endpoint")
    expected_agent_path = (
        f"/Applications/{identity['appBundleFileName']}/Contents/MacOS/{identity['agentBinaryName']}"
    )
    arguments = plist.get("ProgramArguments") or []
    if not arguments or arguments[0] != expected_agent_path:
        raise SystemExit(
            f"LaunchAgent ProgramArguments[0] {arguments[:1]!r} != {expected_agent_path!r}"
        )

    for path, label in ((app, "app"), (agent, "agent")):
        verify_codesign_strict(path)
        sig = parse_codesign(path)
        if sig.get("Identifier") != identity["signingIdentifier"]:
            raise SystemExit(
                f"{label} signing identifier {sig.get('Identifier')!r} != {identity['signingIdentifier']!r}"
            )
        if expect_developer_id:
            if sig.get("TeamIdentifier") != identity["teamIdentifier"]:
                raise SystemExit(
                    f"{label} Team ID {sig.get('TeamIdentifier')!r} != {identity['teamIdentifier']!r}"
                )
            verify_developer_id_requirement(path, identity["developerIDRequirement"])


def main() -> int:
    argv = sys.argv[1:]
    if not argv:
        raise SystemExit(
            "usage: release_identity.py env|check-output|check|verify-volume ROOT [CANDIDATE|VOLUME]"
        )
    command = argv[0]
    if command == "env":
        app_root = pathlib.Path(argv[1]).resolve()
        identity = load_identity(app_root)
        for key, value in identity.items():
            env_key = "AHAKEY_RELEASE_" + "".join(
                "_" + ch.lower() if ch.isupper() else ch for ch in key
            ).lstrip("_").upper()
            # Keep camelCase mapped predictably:
            env_key = "AHAKEY_RELEASE_" + re.sub(r"([A-Z])", r"_\1", key).upper().lstrip("_")
            print(f"export {env_key}={shlex.quote(str(value))}")
        return 0
    if command == "check-output":
        refuse_applications_output(argv[1])
        return 0
    if command == "check":
        app_root = pathlib.Path(argv[1]).resolve()
        candidate = pathlib.Path(argv[2]).resolve() if len(argv) > 2 and argv[2] else None
        check(app_root, candidate)
        return 0
    if command == "verify-volume":
        rest = [item for item in argv[1:] if item != "--expect-developer-id"]
        if len(rest) < 2:
            raise SystemExit("usage: release_identity.py verify-volume ROOT VOLUME [--expect-developer-id]")
        verify_volume(
            pathlib.Path(rest[0]).resolve(),
            pathlib.Path(rest[1]).resolve(),
            "--expect-developer-id" in argv[1:],
        )
        print("release volume ok")
        return 0
    raise SystemExit(f"unknown command {command}")


if __name__ == "__main__":
    raise SystemExit(main())
