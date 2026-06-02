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
DMG_VOLUME_NAME="${DMG_VOLUME_NAME:-AhaKey Studio Installer}"
DMG_BASENAME="${DMG_BASENAME:-AhaKey-Studio-macOS-prod-$(date +%Y%m%d%H%M%S)}"
DMG_PATH="$OUTPUT_DIR/$DMG_BASENAME.dmg"
DMG_STAGING_DIR="$OUTPUT_DIR/.dmg-staging"
RW_DMG_PATH="$OUTPUT_DIR/$DMG_BASENAME-rw.dmg"
# macOS 26 在 /Volumes/ 下对已注册 bundle 名额外执行写入限制（EPERM），
# 改挂到 /tmp 下绕过；卷标（-volname）不变，用户看到的 Finder 窗口标题不受影响。
DMG_MOUNTPOINT="/tmp/ahakey-dmg-mount"
APP_BUNDLE_PATH="$OUTPUT_DIR/$APP_BUNDLE_NAME.app"
BACKGROUND_DIR="$DMG_STAGING_DIR/.background"
BACKGROUND_IMAGE="$BACKGROUND_DIR/InstallerBackground.png"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
SIGNING_IDENTITY_HINT="${SIGNING_IDENTITY_HINT:-}"
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

echo "💽 Creating writable HFS+ DMG..."
# macOS 13+ 上 APFS DMG 的 Finder 元数据持久化不可靠，强制 HFS+。
# macOS 26 在 /Volumes/ 下挂载时对已注册 bundle 名执行额外写入限制（EPERM），
# 两阶段挂载：① 挂到 /tmp 完成文件拷贝 → ② 重挂到 /Volumes 做 Finder 布局。
APP_SIZE_MB=$(du -sm "$APP_BUNDLE_PATH" | awk '{print $1}')
DMG_SIZE_MB=$(( APP_SIZE_MB + 32 ))

rm -f "$RW_DMG_PATH"
hdiutil create \
  -volname "$DMG_VOLUME_NAME" \
  -size "${DMG_SIZE_MB}m" \
  -ov \
  -fs HFS+ \
  "$RW_DMG_PATH"

# ── 阶段一：挂载到 /tmp，拷贝文件（/tmp 下不触发 EPERM）──────────────────
TMP_MOUNTPOINT="/tmp/ahakey-dmg-mount"
if [[ -d "$TMP_MOUNTPOINT" ]]; then
  hdiutil detach "$TMP_MOUNTPOINT" -force >/dev/null 2>&1 || true
fi
hdiutil attach "$RW_DMG_PATH" -mountpoint "$TMP_MOUNTPOINT" -readwrite -noverify -noautoopen

ditto "$APP_BUNDLE_PATH" "$TMP_MOUNTPOINT/$APP_BUNDLE_NAME.app"
ln -sf /Applications "$TMP_MOUNTPOINT/Applications"
mkdir -p "$TMP_MOUNTPOINT/.background"
cp "$BACKGROUND_IMAGE" "$TMP_MOUNTPOINT/.background/InstallerBackground.png"
chflags hidden "$TMP_MOUNTPOINT/.background" 2>/dev/null || true

sync; sync; sync
hdiutil detach "$TMP_MOUNTPOINT" -force

# ── 阶段二：重新挂载到 /Volumes，让 Finder 看到，再做布局 ─────────────────
echo "🪟 Applying drag-to-install layout..."
# 不能带 -noautoopen，否则 Finder 不把此卷加进可见列表，AppleScript tell disk 会失败 -1728
hdiutil attach "$RW_DMG_PATH" -mountpoint "$DMG_MOUNTPOINT" -readwrite -noverify

# 给 Finder 一点时间把卷加进它的内部 list
sleep 3

set +e
osascript 2>&1 <<APPLESCRIPT
tell application "Finder"
  activate
  delay 1
  tell disk "$DMG_VOLUME_NAME"
    open
    delay 3
    try
      set current view of container window to icon view
    end try
    try
      set toolbar visible of container window to false
    end try
    try
      set statusbar visible of container window to false
    end try
    try
      set the bounds of container window to {200, 160, 1060, 640}
    end try
    try
      set theViewOptions to the icon view options of container window
      set arrangement of theViewOptions to not arranged
      set icon size of theViewOptions to 128
      set text size of theViewOptions to 13
    end try
    try
      set background picture of theViewOptions to file ".background:InstallerBackground.png"
    on error errMsg
      log "background-picture error: " & errMsg
    end try
    try
      set position of item "$APP_BUNDLE_NAME.app" of container window to {200, 240}
    end try
    try
      set position of item "Applications" of container window to {660, 240}
    end try
    update without registering applications
    delay 2
    close
    delay 1
    open
    delay 1
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT
ASCRIPT_RC=$?
set -e
echo "(osascript exit=$ASCRIPT_RC)"

# 把元数据强制刷盘，再校验 .DS_Store 是否真写进去
sync; sync; sync
sleep 3
if [[ -f "$DMG_MOUNTPOINT/.DS_Store" ]]; then
  echo "✅ .DS_Store written ($(stat -f%z "$DMG_MOUNTPOINT/.DS_Store") bytes) — installer layout will persist."
else
  echo "⚠️ .DS_Store missing — Finder customization didn't persist. 检查 System Settings > Privacy > Automation 给 Terminal 授予 Finder 权限。"
fi

hdiutil detach "$DMG_MOUNTPOINT" -force

echo "🗜️ Converting DMG..."
hdiutil convert "$RW_DMG_PATH" -ov -format UDZO -o "$DMG_PATH"
rm -f "$RW_DMG_PATH"

if [[ -z "$SIGNING_IDENTITY" ]]; then
  IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  if [[ -n "$SIGNING_IDENTITY_HINT" ]]; then
    SIGNING_IDENTITY="$(echo "$IDENTITIES" | grep 'Developer ID Application' | grep "$SIGNING_IDENTITY_HINT" | head -n 1 | sed -E 's/.*"(.+)"/\1/' || true)"
  else
    SIGNING_IDENTITY="$(echo "$IDENTITIES" | grep 'Developer ID Application' | head -n 1 | sed -E 's/.*"(.+)"/\1/' || true)"
  fi
fi

if [[ -n "$SIGNING_IDENTITY" ]]; then
  echo "🔏 Signing DMG with: $SIGNING_IDENTITY"
  codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"
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
  spctl --assess --type execute -vv "$APP_BUNDLE_PATH"
  spctl --assess --type open --context context:primary-signature -vv "$DMG_PATH"
fi

echo "✅ DMG ready: $DMG_PATH"
