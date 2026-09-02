#!/bin/zsh
# Fail-closed product gate for a v0.2 DMG. Mounts read-only (or inspects --root).
# Does not sign, staple, install, or replace hdiutil/notary/spctl.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

EXPECT_DEVELOPER_ID=0
ROOT=""
DMG=""
MODE="verify"

usage() {
  echo "usage: verify-release-dmg.sh [--expect-developer-id] [--root DIR | DMG]" >&2
  echo "       verify-release-dmg.sh --print-fixture-mounts" >&2
  echo "       verify-release-dmg.sh --detach-stale-fixtures" >&2
  exit 1
}

is_fixture_mountpoint() {
  local p="${1:-}"
  [[ "$p" == /tmp/ahakey-dmg-verify.* || "$p" == /private/tmp/ahakey-dmg-verify.* ]]
}

is_mountpoint() {
  local target="${1:-}"
  [[ -n "$target" ]] || return 1
  /sbin/mount | /usr/bin/awk -v t="$target" '
    $2 == "on" && $3 == t { found = 1 }
    END { exit found ? 0 : 1 }
  '
}

mountpoint_attached() {
  local p="${1:-}"
  [[ -n "$p" ]] || return 1
  is_mountpoint "$p" && return 0
  if [[ "$p" == /tmp/* ]]; then
    is_mountpoint "/private$p" && return 0
  fi
  if [[ "$p" == /private/tmp/* ]]; then
    is_mountpoint "${p#/private}" && return 0
  fi
  return 1
}

list_fixture_mounts() {
  /usr/bin/python3 - <<'PY'
import plistlib
import subprocess

raw = subprocess.check_output(["/usr/bin/hdiutil", "info", "-plist"])
info = plistlib.loads(raw)
seen = []
for img in info.get("images") or []:
    for ent in img.get("system-entities") or []:
        mp = ent.get("mount-point") or ""
        if "/ahakey-dmg-verify." in mp.replace("\\", "/"):
            if mp not in seen:
                seen.append(mp)
                print(mp)
PY
}

print_fixture_inventory() {
  echo "=== fixture mountpoints ==="
  local mounts
  mounts="$(list_fixture_mounts)"
  if [[ -n "$mounts" ]]; then
    print -r -- "$mounts"
  else
    echo "(none)"
  fi
  echo "=== fixture image-path / mount-point ==="
  /usr/bin/python3 - <<'PY'
import plistlib
import subprocess

raw = subprocess.check_output(["/usr/bin/hdiutil", "info", "-plist"])
info = plistlib.loads(raw)
found = False
for img in info.get("images") or []:
    image = img.get("image-path") or ""
    for ent in img.get("system-entities") or []:
        mp = ent.get("mount-point") or ""
        if "/ahakey-dmg-verify." in mp.replace("\\", "/"):
            found = True
            print(f"{image}\t{mp}")
if not found:
    print("(none)")
PY
}

detach_stale_fixtures() {
  echo "before:"
  print_fixture_inventory
  local failed=0
  local mp
  local stale_mounts
  stale_mounts="$(list_fixture_mounts)"
  while IFS= read -r mp; do
    [[ -n "$mp" ]] || continue
    if ! is_fixture_mountpoint "$mp"; then
      echo "refusing to detach non-fixture path: $mp" >&2
      failed=1
      continue
    fi
    if ! /usr/bin/hdiutil detach "$mp" -force; then
      echo "hdiutil detach failed: $mp" >&2
      failed=1
      continue
    fi
    if mountpoint_attached "$mp"; then
      echo "mount still present after detach: $mp" >&2
      failed=1
      continue
    fi
    echo "detached stale fixture: $mp"
    if [[ -d "$mp" ]] && ! mountpoint_attached "$mp"; then
      /bin/rmdir "$mp" || {
        echo "rmdir leftover mount dir failed: $mp" >&2
        failed=1
      }
    fi
  done <<< "$stale_mounts"
  echo "after:"
  print_fixture_inventory
  if [[ "$failed" -ne 0 ]]; then
    echo "stale fixture detach reported errors" >&2
    return 1
  fi
  local remaining
  remaining="$(list_fixture_mounts)"
  if [[ -n "$remaining" ]]; then
    echo "fixture mounts remain after cleanup:" >&2
    print -r -- "$remaining" >&2
    return 1
  fi
  return 0
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
    --print-fixture-mounts)
      MODE="print-fixtures"
      shift
      ;;
    --detach-stale-fixtures)
      MODE="detach-stale"
      shift
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

if [[ "$MODE" == "print-fixtures" ]]; then
  list_fixture_mounts
  exit 0
fi

if [[ "$MODE" == "detach-stale" ]]; then
  if [[ -n "$ROOT" || -n "$DMG" || "$EXPECT_DEVELOPER_ID" == "1" ]]; then
    echo "pass --detach-stale-fixtures alone" >&2
    exit 1
  fi
  detach_stale_fixtures
  exit 0
fi

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
PRIMARY_RC=0
CLEANUP_RC=0
CLEANUP_ERR=""
FINISHED=0

detach_own_mount() {
  [[ -n "${MNT:-}" ]] || return 0
  if ! is_fixture_mountpoint "$MNT"; then
    echo "refusing to detach non-fixture path: $MNT" >&2
    CLEANUP_RC=1
    CLEANUP_ERR="refusing to detach non-fixture path: $MNT"
    return 1
  fi
  if ! mountpoint_attached "$MNT"; then
    return 0
  fi
  if ! /usr/bin/hdiutil detach "$MNT" -force; then
    echo "hdiutil detach failed: $MNT" >&2
    CLEANUP_RC=1
    CLEANUP_ERR="hdiutil detach failed: $MNT"
  fi
  if mountpoint_attached "$MNT"; then
    echo "mount still present after detach: $MNT" >&2
    CLEANUP_RC=1
    CLEANUP_ERR="${CLEANUP_ERR:+$CLEANUP_ERR; }mount still present: $MNT"
    return 1
  fi
  echo "detached mountpoint: $MNT"
  return 0
}

remove_mount_dir() {
  [[ -n "${MNT:-}" ]] || return 0
  if mountpoint_attached "$MNT"; then
    echo "refusing to rmdir attached mountpoint: $MNT" >&2
    CLEANUP_RC=1
    CLEANUP_ERR="${CLEANUP_ERR:+$CLEANUP_ERR; }refusing to rmdir attached mountpoint: $MNT"
    return 1
  fi
  if [[ -d "$MNT" ]]; then
    if ! /bin/rmdir "$MNT"; then
      echo "rmdir failed: $MNT" >&2
      CLEANUP_RC=1
      CLEANUP_ERR="${CLEANUP_ERR:+$CLEANUP_ERR; }rmdir failed: $MNT"
      return 1
    fi
  fi
  return 0
}

shared_cleanup() {
  set +e
  detach_own_mount
  remove_mount_dir
  set -e
  return "$CLEANUP_RC"
}

on_exit() {
  local incoming=$?
  if [[ "$FINISHED" -eq 1 ]]; then
    return 0
  fi
  set +e
  shared_cleanup
  set -e
  local primary=$PRIMARY_RC
  if [[ "$primary" -eq 0 && "$incoming" -ne 0 ]]; then
    primary=$incoming
  fi
  FINISHED=1
  if [[ "$primary" -ne 0 ]]; then
    if [[ "$CLEANUP_RC" -ne 0 ]]; then
      echo "cleanup error (original failure $primary): ${CLEANUP_ERR:-unknown}" >&2
    fi
    exit "$primary"
  fi
  if [[ "$CLEANUP_RC" -ne 0 ]]; then
    echo "cleanup error: ${CLEANUP_ERR:-unknown}" >&2
    exit "$CLEANUP_RC"
  fi
}
trap on_exit EXIT INT TERM HUP

/usr/bin/hdiutil attach "$DMG" -readonly -nobrowse -noverify -mountpoint "$MNT" >/dev/null
set +e
verify_root "$MNT"
PRIMARY_RC=$?
set -e
if [[ "$PRIMARY_RC" -ne 0 ]]; then
  exit "$PRIMARY_RC"
fi
set +e
shared_cleanup
set -e
FINISHED=1
trap - EXIT INT TERM HUP
if [[ "$CLEANUP_RC" -ne 0 ]]; then
  echo "cleanup error: ${CLEANUP_ERR:-unknown}" >&2
  exit "$CLEANUP_RC"
fi
echo "release dmg ok: $DMG"
