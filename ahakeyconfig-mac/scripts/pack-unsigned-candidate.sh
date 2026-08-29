#!/bin/zsh
# WBS 5.9A：可复现的未签名 v0.2 候选。不公证、不覆盖 /Applications、不写登录项。
#
# 产出（默认 dist/unsigned-v0.2/）：
#   AhaKey Studio.app
#   LaunchAgent.plist
#   ReleaseIdentity.json
#   SIGNING-INPUTS.md
#   INSTALL-AND-ROLLBACK.md
#   manifest.json
#
# 用法：
#   zsh scripts/pack-unsigned-candidate.sh
#   OUTPUT_DIR=/tmp/ahakey-unsigned zsh scripts/pack-unsigned-candidate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$APP_ROOT"

IDENTITY_JSON="$APP_ROOT/Packaging/ReleaseIdentity.json"
OUTPUT_DIR="${OUTPUT_DIR:-$APP_ROOT/dist/unsigned-v0.2}"
APP_VERSION="${APP_VERSION:-0.2.0}"
MACOS_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET:-13.0}"

if [[ "${INSTALL_TO_APPLICATIONS:-0}" == "1" ]]; then
  echo "❌ pack-unsigned-candidate.sh refuses INSTALL_TO_APPLICATIONS=1 (WBS 5.9A)."
  exit 1
fi
if [[ "${REQUIRE_DEVELOPER_ID:-0}" == "1" ]]; then
  echo "❌ pack-unsigned-candidate.sh refuses REQUIRE_DEVELOPER_ID=1 (unsigned candidate only)."
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

INSTALL_TO_APPLICATIONS=0 \
REQUIRE_DEVELOPER_ID=0 \
FORCE_ADHOC_SIGN=1 \
APP_VERSION="$APP_VERSION" \
MACOS_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET" \
OUTPUT_DIR="$OUTPUT_DIR" \
zsh "$SCRIPT_DIR/build.sh"

cp "$IDENTITY_JSON" "$OUTPUT_DIR/ReleaseIdentity.json"
cp "$APP_ROOT/Packaging/LaunchAgent.plist" "$OUTPUT_DIR/LaunchAgent.plist"
cp "$APP_ROOT/Packaging/SIGNING-INPUTS.md" "$OUTPUT_DIR/SIGNING-INPUTS.md"
cp "$APP_ROOT/Packaging/INSTALL-AND-ROLLBACK.md" "$OUTPUT_DIR/INSTALL-AND-ROLLBACK.md"

REPO_ROOT="$(git -C "$APP_ROOT" rev-parse --show-toplevel 2>/dev/null || echo "$APP_ROOT")"
GIT_COMMIT="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
python3 - "$OUTPUT_DIR/manifest.json" "$APP_VERSION" "$GIT_COMMIT" "$MACOS_DEPLOYMENT_TARGET" <<'PY'
import json, pathlib, sys
path, version, commit, min_os = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
pathlib.Path(path).write_text(json.dumps({
    "productVersion": version,
    "gitCommit": commit,
    "minimumMacOSVersion": min_os,
    "signedWithDeveloperID": False,
    "installsToApplications": False,
}, indent=2) + "\n", encoding="utf-8")
PY

zsh "$SCRIPT_DIR/check-release-identity.sh" "$OUTPUT_DIR"

echo "✅ Unsigned v0.2 candidate: $OUTPUT_DIR"
echo "   Signing and /Applications install remain HIL-RELEASE-0.2 USER-GATE."
