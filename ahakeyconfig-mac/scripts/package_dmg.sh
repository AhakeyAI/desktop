#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$SCRIPT_DIR/build.local.env" ]]; then
  source "$SCRIPT_DIR/build.local.env"
fi

APP_BUNDLE_NAME="${APP_BUNDLE_NAME:-AhaKey Studio}"
APP_DISPLAY_NAME="${APP_DISPLAY_NAME:-AhaKey Studio}"
OUTPUT_DIR="${OUTPUT_DIR:-$APP_ROOT/dist}"
DMG_VOLUME_NAME="${DMG_VOLUME_NAME:-Install AhaKey Studio}"
DMG_BASENAME="${DMG_BASENAME:-AhaKey-Studio-macOS-prod-$(date +%Y%m%d%H%M%S)}"
DMG_PATH="$OUTPUT_DIR/$DMG_BASENAME.dmg"
APP_BUNDLE_PATH="$OUTPUT_DIR/$APP_BUNDLE_NAME.app"
DMG_PYTHON="${DMG_PYTHON:-python3}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
NOTARY_KEYCHAIN="${NOTARY_KEYCHAIN:-}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
SIGNING_IDENTITY_HINT="${SIGNING_IDENTITY_HINT:-}"
RELEASE_DISTRIBUTION="${RELEASE_DISTRIBUTION:-0}"

if [[ -z "$SIGNING_IDENTITY" ]]; then
  IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  if [[ -n "$SIGNING_IDENTITY_HINT" ]]; then
    SIGNING_IDENTITY="$(echo "$IDENTITIES" | grep 'Developer ID Application' | grep "$SIGNING_IDENTITY_HINT" | head -n 1 | sed -E 's/.*"(.+)"/\1/' || true)"
  else
    SIGNING_IDENTITY="$(echo "$IDENTITIES" | grep 'Developer ID Application' | head -n 1 | sed -E 's/.*"(.+)"/\1/' || true)"
  fi
fi

if (( $# > 1 )) || [[ -n "${1:-}" && "$1" != "--reuse-built-app" ]]; then
  echo "Usage: $0 [--reuse-built-app]" >&2
  exit 2
fi

if ! "$DMG_PYTHON" -c 'import sys; sys.exit(sys.version_info < (3, 10))'; then
  echo "DMG packaging needs Python 3.10 or later. Set DMG_PYTHON to its executable." >&2
  exit 1
fi

if [[ "$RELEASE_DISTRIBUTION" == "1" && ( -z "$SIGNING_IDENTITY" || -z "$NOTARY_PROFILE" ) ]]; then
  echo "Release packaging requires a Developer ID signing identity and NOTARY_PROFILE." >&2
  exit 1
fi

echo "📦 Packaging $APP_DISPLAY_NAME DMG..."

if [[ "${1:-}" != "--reuse-built-app" ]]; then
  if [[ "$RELEASE_DISTRIBUTION" == "1" ]]; then
    REQUIRE_DEVELOPER_ID=1 "$SCRIPT_DIR/build.sh"
  else
    "$SCRIPT_DIR/build.sh"
  fi
fi

if [[ ! -d "$APP_BUNDLE_PATH" ]]; then
  echo "App bundle not found at $APP_BUNDLE_PATH" >&2
  exit 1
fi
if [[ -n "$SIGNING_IDENTITY" ]]; then
  codesign --verify --deep --strict "$APP_BUNDLE_PATH"
fi

mkdir -p "$OUTPUT_DIR"
DMG_WORK_DIR="$(mktemp -d "$OUTPUT_DIR/.dmg-package.XXXXXX")"
trap 'rm -rf "$DMG_WORK_DIR"' EXIT
STAGED_DMG="$DMG_WORK_DIR/$DMG_BASENAME.dmg"
BACKGROUND_IMAGE="$DMG_WORK_DIR/InstallerBackground.png"

swift "$SCRIPT_DIR/generate_dmg_background.swift" "$BACKGROUND_IMAGE"
"$DMG_PYTHON" -m venv "$DMG_WORK_DIR/venv"
# dmgbuild 1.6.7 omits the legacy background bookmark that Finder rejects on Tahoe.
"$DMG_WORK_DIR/venv/bin/python" -m pip install --disable-pip-version-check \
  'dmgbuild==1.6.7' 'ds_store==1.3.4' 'mac_alias==2.2.4'

echo "💽 Writing the drag-to-install layout..."
"$DMG_WORK_DIR/venv/bin/python" - \
  "$STAGED_DMG" "$DMG_VOLUME_NAME" "$APP_BUNDLE_PATH" "$BACKGROUND_IMAGE" <<'PYTHON'
import os
import sys

import dmgbuild

output, volume, app, background = sys.argv[1:]
dmgbuild.build_dmg(output, volume, settings={
    "format": "ULMO",
    "files": [app],
    "symlinks": {"Applications": "/Applications"},
    "background": background,
    "window_rect": ((200, 160), (920, 492)),
    "icon_locations": {os.path.basename(app): (230, 235), "Applications": (690, 235)},
    "icon_size": 120,
    "text_size": 13,
    "show_icon_preview": True,
})
PYTHON

if [[ -n "$SIGNING_IDENTITY" ]]; then
  echo "🔏 Signing DMG with: $SIGNING_IDENTITY"
  codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$STAGED_DMG"
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
  echo "🧾 Notarizing DMG with profile: $NOTARY_PROFILE"
  NOTARY_AUTH_ARGS=(--keychain-profile "$NOTARY_PROFILE")
  if [[ -n "$NOTARY_KEYCHAIN" ]]; then
    NOTARY_AUTH_ARGS+=(--keychain "$NOTARY_KEYCHAIN")
  fi
  xcrun notarytool submit "$STAGED_DMG" "${NOTARY_AUTH_ARGS[@]}" --no-s3-acceleration --wait
  xcrun stapler staple "$STAGED_DMG"
  xcrun stapler validate "$STAGED_DMG"
fi

echo "🔎 Verifying DMG..."
hdiutil verify "$STAGED_DMG"

if [[ -n "$NOTARY_PROFILE" ]]; then
  spctl --assess --type open --context context:primary-signature -vv "$STAGED_DMG"
fi

mv -f "$STAGED_DMG" "$DMG_PATH"
echo "✅ DMG ready: $DMG_PATH"
