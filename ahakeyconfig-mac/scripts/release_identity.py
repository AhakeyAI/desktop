#!/usr/bin/env python3
"""Single-source helpers for v0.2 release identity. Does not sign or install."""

from __future__ import annotations

import json
import os
import pathlib
import re
import shlex
import subprocess
import sys


REQUIRED = {
    "channel": "v0.2",
    "productVersion": "0.2.1",
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


FROZEN_SOCKET_PLACEHOLDER = "SOCKET_PATH_PLACEHOLDER"


def frozen_program_arguments(identity: dict) -> list[str]:
    agent_path = (
        f"/Applications/{identity['appBundleFileName']}/Contents/MacOS/{identity['agentBinaryName']}"
    )
    return [agent_path, "--socket", FROZEN_SOCKET_PLACEHOLDER]


def frozen_mach_services(identity: dict) -> dict:
    return {identity["machServiceName"]: True}


def verify_companion_plist(plist: dict, identity: dict) -> None:
    if plist.get("Label") != identity["agentLaunchdLabel"]:
        raise SystemExit(
            f"LaunchAgent Label {plist.get('Label')!r} != {identity['agentLaunchdLabel']!r}"
        )
    services = plist.get("MachServices")
    expected_services = frozen_mach_services(identity)
    if services != expected_services:
        raise SystemExit(f"LaunchAgent MachServices {services!r} != {expected_services!r}")
    arguments = plist.get("ProgramArguments")
    expected_arguments = frozen_program_arguments(identity)
    if arguments != expected_arguments:
        raise SystemExit(
            f"LaunchAgent ProgramArguments {arguments!r} != {expected_arguments!r}"
        )


def evaluate_signature_policy(
    identity: dict,
    *,
    identifier: str | None,
    team: str | None,
    requirement_satisfied: bool,
    expect_developer_id: bool,
    label: str,
) -> None:
    if identifier != identity["signingIdentifier"]:
        raise SystemExit(
            f"{label} signing identifier {identifier!r} != {identity['signingIdentifier']!r}"
        )
    if not expect_developer_id:
        return
    if team != identity["teamIdentifier"]:
        raise SystemExit(f"{label} Team ID {team!r} != {identity['teamIdentifier']!r}")
    if requirement_satisfied is not True:
        raise SystemExit(f"{label} frozen Developer ID requirement failed")


def require_regular_inside(path: pathlib.Path, root: pathlib.Path, label: str) -> pathlib.Path:
    if path.is_symlink():
        raise SystemExit(f"{label} must not be a symlink: {path}")
    if not path.exists():
        raise SystemExit(f"missing {label} {path}")
    resolved = path.resolve()
    resolved_root = root.resolve()
    try:
        resolved.relative_to(resolved_root)
    except ValueError:
        raise SystemExit(f"{label} canonical path escapes {resolved_root}: {resolved}")
    return resolved


def check(app_root: pathlib.Path, candidate: pathlib.Path | None) -> None:
    identity = load_identity(app_root)
    plist_path = app_root / "Packaging" / "LaunchAgent.plist"
    import plistlib

    plist = plistlib.loads(plist_path.read_bytes())
    verify_companion_plist(plist, identity)

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
    if 'release_identity.py" env' not in package_dmg and "release_identity.py env" not in package_dmg:
        raise SystemExit("package_dmg.sh must load identity via release_identity.py env")
    if "json.loads" in package_dmg:
        raise SystemExit("package_dmg.sh must not duplicate JSON identity parsing")
    if 'Packaging/LaunchAgent.plist' not in package_dmg:
        raise SystemExit("package_dmg.sh must copy Packaging/LaunchAgent.plist beside the App")
    if "$DMG_STAGING_DIR/$APP_BUNDLE_FILE_NAME" in package_dmg:
        raise SystemExit("package_dmg.sh must not copy the App into unused .dmg-staging")
    if '"$DMG_STAGING_DIR/LaunchAgent.plist"' in package_dmg:
        raise SystemExit("package_dmg.sh must not copy LaunchAgent.plist into unused .dmg-staging")
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
    return subprocess.run(args, capture_output=True, text=True, check=False)


def verify_codesign_strict(path: pathlib.Path) -> None:
    proc = _run_codesign(["/usr/bin/codesign", "--verify", "--strict", str(path)])
    if proc.returncode != 0:
        detail = ((proc.stdout or "") + (proc.stderr or "")).strip()
        raise SystemExit(f"codesign --verify --strict failed for {path}: {detail}")


def inspect_developer_id_requirement_process(
    path: pathlib.Path, requirement: str
) -> subprocess.CompletedProcess[str]:
    # codesign verify requires a single "-R=<req>" token; "-R" "=" "<req>" is usage/exit 2.
    return _run_codesign(
        ["/usr/bin/codesign", "--verify", f"-R={requirement}", str(path)]
    )


def inspect_developer_id_requirement(path: pathlib.Path, requirement: str) -> bool:
    proc = inspect_developer_id_requirement_process(path, requirement)
    if proc.returncode == 2:
        detail = ((proc.stdout or "") + (proc.stderr or "")).strip()
        raise SystemExit(
            f"codesign requirement invocation failed with usage/exit 2 for {path}: {detail}"
        )
    return proc.returncode == 0


def verify_volume(app_root: pathlib.Path, volume: pathlib.Path, expect_developer_id: bool) -> None:
    import plistlib

    identity = load_identity(app_root)
    if volume.is_symlink():
        raise SystemExit(f"volume must not be a symlink: {volume}")
    if not volume.exists() or not volume.is_dir():
        raise SystemExit(f"volume is not a directory: {volume}")
    volume = volume.resolve()

    apps = [path for path in volume.iterdir() if path.name.endswith(".app")]
    expected_app = identity["appBundleFileName"]
    if len(apps) != 1:
        raise SystemExit(f"expected exactly one app, found {[path.name for path in apps]!r}")
    app = apps[0]
    if app.name != expected_app:
        raise SystemExit(f"app name {app.name!r} != {expected_app!r}")
    app = require_regular_inside(app, volume, "app")
    if not app.is_dir():
        raise SystemExit(f"app is not a directory: {app}")

    info_plist = require_regular_inside(app / "Contents" / "Info.plist", app, "Info.plist")
    if info_plist.is_symlink() or not info_plist.is_file():
        raise SystemExit(f"Info.plist must be a regular file: {info_plist}")
    info = plistlib.loads(info_plist.read_bytes())
    if info.get("CFBundleIdentifier") != identity["bundleIdentifier"]:
        raise SystemExit(
            f"CFBundleIdentifier {info.get('CFBundleIdentifier')!r} != {identity['bundleIdentifier']!r}"
        )
    if info.get("CFBundleShortVersionString") != identity["productVersion"]:
        raise SystemExit(
            f"CFBundleShortVersionString {info.get('CFBundleShortVersionString')!r} != {identity['productVersion']!r}"
        )

    agent = require_regular_inside(
        app / "Contents" / "MacOS" / identity["agentBinaryName"],
        app,
        "agent",
    )
    if agent.is_symlink() or not agent.is_file():
        raise SystemExit(f"missing agent binary {agent}")

    companion = require_regular_inside(volume / "LaunchAgent.plist", volume, "companion")
    if companion.is_symlink() or not companion.is_file():
        raise SystemExit("missing companion LaunchAgent.plist")
    verify_companion_plist(plistlib.loads(companion.read_bytes()), identity)

    for path, label in ((app, "app"), (agent, "agent")):
        verify_codesign_strict(path)
        sig = parse_codesign(path)
        requirement_ok = False
        if expect_developer_id:
            requirement_ok = inspect_developer_id_requirement(
                path, identity["developerIDRequirement"]
            )
        evaluate_signature_policy(
            identity,
            identifier=sig.get("Identifier"),
            team=sig.get("TeamIdentifier"),
            requirement_satisfied=requirement_ok,
            expect_developer_id=expect_developer_id,
            label=label,
        )


def parse_bool_flag(raw: str) -> bool:
    if raw in ("1", "true", "True", "yes"):
        return True
    if raw in ("0", "false", "False", "no"):
        return False
    raise SystemExit(f"expected 0 or 1, got {raw!r}")


def main() -> int:
    argv = sys.argv[1:]
    if not argv:
        raise SystemExit(
            "usage: release_identity.py env|check-output|check|verify-volume|evaluate-signature-policy|inspect-requirement ROOT ..."
        )
    command = argv[0]
    if command == "env":
        app_root = pathlib.Path(argv[1]).resolve()
        identity = load_identity(app_root)
        for key, value in identity.items():
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
            pathlib.Path(rest[1]),
            "--expect-developer-id" in argv[1:],
        )
        print("release volume ok")
        return 0
    if command == "evaluate-signature-policy":
        rest = [item for item in argv[1:] if item != "--expect-developer-id"]
        if len(rest) < 1:
            raise SystemExit(
                "usage: release_identity.py evaluate-signature-policy ROOT "
                "--identifier ID --team TEAM --requirement-ok 0|1 [--expect-developer-id] [--label app]"
            )
        app_root = pathlib.Path(rest[0]).resolve()
        identity = load_identity(app_root)
        identifier = None
        team = None
        requirement_ok = False
        label = "artifact"
        args = rest[1:]
        while args:
            flag = args.pop(0)
            if flag == "--identifier":
                identifier = args.pop(0) if args else None
            elif flag == "--team":
                team = args.pop(0) if args else None
            elif flag == "--requirement-ok":
                requirement_ok = parse_bool_flag(args.pop(0) if args else "")
            elif flag == "--label":
                label = args.pop(0) if args else label
            else:
                raise SystemExit(f"unknown evaluate-signature-policy flag {flag}")
        evaluate_signature_policy(
            identity,
            identifier=identifier,
            team=team,
            requirement_satisfied=requirement_ok,
            expect_developer_id="--expect-developer-id" in argv[1:],
            label=label,
        )
        print("signature policy ok")
        return 0
    if command == "inspect-requirement":
        rest = argv[1:]
        path_arg: str | None = None
        requirement: str | None = None
        while rest:
            flag = rest.pop(0)
            if flag == "--requirement":
                requirement = rest.pop(0) if rest else None
            elif not flag.startswith("-"):
                path_arg = flag
            else:
                raise SystemExit(f"unknown inspect-requirement flag {flag}")
        if not path_arg or requirement is None:
            raise SystemExit(
                "usage: release_identity.py inspect-requirement PATH --requirement REQ"
            )
        proc = inspect_developer_id_requirement_process(pathlib.Path(path_arg), requirement)
        output = ((proc.stdout or "") + (proc.stderr or "")).strip()
        print(f"returncode={proc.returncode}")
        if proc.returncode == 2 or "Usage:" in output:
            raise SystemExit(
                f"codesign requirement invocation failed with usage/exit 2: {output}"
            )
        print("requirement_ok=1" if proc.returncode == 0 else "requirement_ok=0")
        return 0
    raise SystemExit(f"unknown command {command}")


if __name__ == "__main__":
    raise SystemExit(main())
