#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_BUNDLE_NAME="${APP_BUNDLE_NAME:-AhaKey Studio}"
APP_DISPLAY_NAME="${APP_DISPLAY_NAME:-AhaKey Studio}"
OUTPUT_DIR="${OUTPUT_DIR:-$APP_ROOT/dist}"
DMG_VOLUME_NAME="${DMG_VOLUME_NAME:-AhaKey Studio Installer}"
DMG_BASENAME="${DMG_BASENAME:-AhaKey-Studio-macOS}"
DMG_PATH="$OUTPUT_DIR/$DMG_BASENAME.dmg"
DMG_STAGING_DIR="$OUTPUT_DIR/.dmg-staging"
RW_DMG_PATH="$OUTPUT_DIR/$DMG_BASENAME-rw.dmg"
DMG_MOUNTPOINT="/Volumes/$DMG_VOLUME_NAME"
APP_BUNDLE_PATH="$OUTPUT_DIR/$APP_BUNDLE_NAME.app"
BACKGROUND_DIR="$DMG_STAGING_DIR/.background"
BACKGROUND_IMAGE="$BACKGROUND_DIR/InstallerBackground.png"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
RELEASE_DISTRIBUTION="${RELEASE_DISTRIBUTION:-0}"

echo "📦 Packaging $APP_DISPLAY_NAME DMG..."

if [[ "$RELEASE_DISTRIBUTION" == "1" ]]; then
  REQUIRE_DEVELOPER_ID=1 "$SCRIPT_DIR/build.sh"
else
  "$SCRIPT_DIR/build.sh"
fi

if [[ ! -d "$APP_BUNDLE_PATH" ]]; then
  echo "App bundle not found at $APP_BUNDLE_PATH"
  exit 1
fi

rm -rf "$DMG_STAGING_DIR"
mkdir -p "$DMG_STAGING_DIR"

echo "🧱 Preparing DMG staging folder..."
ditto "$APP_BUNDLE_PATH" "$DMG_STAGING_DIR/$APP_BUNDLE_NAME.app"
ln -s /Applications "$DMG_STAGING_DIR/Applications"
mkdir -p "$BACKGROUND_DIR"
swift "$APP_ROOT/scripts/generate_dmg_background.swift" "$BACKGROUND_IMAGE"

rm -f "$DMG_PATH" "$RW_DMG_PATH"
if [[ -d "$DMG_MOUNTPOINT" ]]; then
  hdiutil detach "$DMG_MOUNTPOINT" -force >/dev/null 2>&1 || true
fi

echo "💽 Creating writable DMG..."
hdiutil create \
  -volname "$DMG_VOLUME_NAME" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDRW \
  "$RW_DMG_PATH"

echo "🪟 Applying simple drag-to-install layout..."
hdiutil attach "$RW_DMG_PATH" -mountpoint "$DMG_MOUNTPOINT" -readwrite -noverify -noautoopen

osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$DMG_VOLUME_NAME"
    open
    delay 1
    tell container window
      set current view to icon view
      set toolbar visible to false
      set statusbar visible to false
      set bounds to {120, 120, 1180, 760}
    end tell
    set theIconViewOptions to the icon view options of container window
    set arrangement of theIconViewOptions to not arranged
    set icon size of theIconViewOptions to 128
    set text size of theIconViewOptions to 14
    set background picture of theIconViewOptions to (POSIX file "$DMG_MOUNTPOINT/.background/InstallerBackground.png" as alias)
    set position of item "$APP_BUNDLE_NAME.app" of container window to {180, 280}
    set position of item "Applications" of container window to {900, 280}
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT

hdiutil detach "$DMG_MOUNTPOINT"

echo "🗜️ Converting DMG..."
hdiutil convert "$RW_DMG_PATH" -ov -format UDZO -o "$DMG_PATH"
rm -f "$RW_DMG_PATH"

if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep 'Developer ID Application' | head -n 1 | sed -E 's/.*"(.+)"/\1/' || true)"
fi

if [[ -n "$SIGNING_IDENTITY" ]]; then
  echo "🔏 Signing DMG with: $SIGNING_IDENTITY"
  codesign --force --sign "$SIGNING_IDENTITY" "$DMG_PATH"
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
  echo "🧾 Notarizing DMG with profile: $NOTARY_PROFILE"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
elif [[ "$RELEASE_DISTRIBUTION" == "1" ]]; then
  echo "❌ RELEASE_DISTRIBUTION=1 requires NOTARY_PROFILE."
  echo "   Create one with: xcrun notarytool store-credentials <profile-name> ..."
  exit 1
fi

echo "🔎 Verifying DMG..."
hdiutil verify "$DMG_PATH"

if [[ -n "$SIGNING_IDENTITY" ]]; then
  echo "🔎 Assessing signed artifacts..."
  spctl --assess -vv "$APP_BUNDLE_PATH" || true
  spctl --assess -vv "$DMG_PATH" || true
fi

echo "✅ DMG ready: $DMG_PATH"
