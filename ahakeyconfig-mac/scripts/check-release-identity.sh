#!/bin/zsh
# 校验冻结身份与候选/模板，不调用 codesign、不安装。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CANDIDATE="${1:-}"

python3 - "$APP_ROOT" "$CANDIDATE" <<'PY'
import json, pathlib, plistlib, sys

root = pathlib.Path(sys.argv[1])
candidate = pathlib.Path(sys.argv[2]) if sys.argv[2] else None
identity = json.loads((root / "Packaging/ReleaseIdentity.json").read_text(encoding="utf-8"))
required = {
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
for key, value in required.items():
    actual = identity.get(key)
    if actual != value:
        raise SystemExit(f"ReleaseIdentity.json {key}={actual!r}, expected {value!r}")

plist_path = root / "Packaging/LaunchAgent.plist"
plist = plistlib.loads(plist_path.read_bytes())
if plist.get("Label") != identity["agentLaunchdLabel"]:
    raise SystemExit("LaunchAgent Label mismatch")
services = plist.get("MachServices") or {}
if services.get(identity["machServiceName"]) is not True:
    raise SystemExit("LaunchAgent MachServices missing runtime endpoint")

if candidate:
    info = plistlib.loads((candidate / "AhaKey Studio.app/Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != identity["bundleIdentifier"]:
        raise SystemExit("candidate CFBundleIdentifier mismatch")
    if info.get("LSMinimumSystemVersion") != identity["minimumMacOSVersion"]:
        raise SystemExit("candidate LSMinimumSystemVersion mismatch")
    agent = candidate / "AhaKey Studio.app/Contents/MacOS" / identity["agentBinaryName"]
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

print("release identity ok")
PY
