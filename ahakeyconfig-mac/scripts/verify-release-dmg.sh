#!/bin/zsh
# Fail-closed product gate for a v0.2 DMG. Mounts read-only (or inspects --root).
# Does not sign, staple, install, or replace hdiutil/notary/spctl.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

EXPECT_DEVELOPER_ID=0
ROOT=""
DMG=""

usage() {
  echo "usage: verify-release-dmg.sh [--expect-developer-id] [--root DIR | DMG]" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --expect-developer-id)
      EXPECT_DEVELOPER_ID=1
      shift
      ;;
    --root)
      [[ $# -ge 2 ]] || usage
      ROOT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    -*)
      echo "unknown flag: $1" >&2
      usage
      ;;
    *)
      if [[ -n "$DMG" ]]; then
        echo "unexpected argument: $1" >&2
        usage
      fi
      DMG="$1"
      shift
      ;;
  esac
done

PYTHON_ARGS=()
if [[ "$EXPECT_DEVELOPER_ID" == "1" ]]; then
  PYTHON_ARGS+=(--expect-developer-id)
fi

verify_root() {
  python3 "$SCRIPT_DIR/release_identity.py" verify-volume "$APP_ROOT" "$1" "${PYTHON_ARGS[@]}"
}

if [[ -n "$ROOT" ]]; then
  if [[ -n "$DMG" ]]; then
    echo "pass either --root DIR or a DMG path, not both" >&2
    exit 1
  fi
  if [[ ! -d "$ROOT" ]]; then
    echo "root is not a directory: $ROOT" >&2
    exit 1
  fi
  verify_root "$ROOT"
  echo "release dmg volume ok: $ROOT"
  exit 0
fi

if [[ -z "$DMG" || ! -f "$DMG" ]]; then
  usage
fi

MNT="$(mktemp -d /tmp/ahakey-dmg-verify.XXXXXX)"
DETACHED=0
cleanup() {
  if [[ "$DETACHED" -eq 0 ]]; then
    /usr/bin/hdiutil detach "$MNT" -force >/dev/null 2>&1 || true
    DETACHED=1
  fi
  rmdir "$MNT" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM HUP

/usr/bin/hdiutil attach "$DMG" -readonly -nobrowse -noverify -mountpoint "$MNT" >/dev/null
verify_root "$MNT"
/usr/bin/hdiutil detach "$MNT" -force >/dev/null
DETACHED=1
echo "release dmg ok: $DMG"
