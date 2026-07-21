#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

EXECUTABLE_NAME="AhaKeyConfig"
APP_BUNDLE_NAME="${APP_BUNDLE_NAME:-AhaKey Studio}"
APP_DISPLAY_NAME="${APP_DISPLAY_NAME:-AhaKey Studio}"
APP_IDENTIFIER="lab.jawa.ahakeyconfig"
APP_VERSION="${APP_VERSION:-0.1.0}"
MACOS_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET:-12.0}"
BUILD_ARCHS="${BUILD_ARCHS:-arm64 x86_64}"
OUTPUT_DIR="${OUTPUT_DIR:-$APP_ROOT/dist}"
APP_BUNDLE="$OUTPUT_DIR/$APP_BUNDLE_NAME.app"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
AGENT_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/ahakeyconfig-agent"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
ENTITLEMENTS="$APP_ROOT/.build/AhaKeyConfig.entitlements"
ICON_SOURCE="${ICON_SOURCE:-$APP_ROOT/ahakeyicon.png}"
INSTALL_TO_APPLICATIONS="${INSTALL_TO_APPLICATIONS:-0}"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
LAUNCH_AFTER_INSTALL="${LAUNCH_AFTER_INSTALL:-0}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
SIGNING_IDENTITY_HINT="${SIGNING_IDENTITY_HINT:-}"
REQUIRE_DEVELOPER_ID="${REQUIRE_DEVELOPER_ID:-0}"
DEST_APP="$INSTALL_DIR/$APP_BUNDLE_NAME.app"

echo "📦 Building $APP_DISPLAY_NAME..."
cd "$APP_ROOT"

export MACOSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET"

BUILD_OUTPUTS=()
AGENT_OUTPUTS=()
for ARCH in ${(z)BUILD_ARCHS}; do
  echo "🔨 Building $ARCH for macOS $MACOS_DEPLOYMENT_TARGET..."
  swift build -c release --arch "$ARCH" --product AhaKeyConfig
  swift build -c release --arch "$ARCH" --product ahakeyconfig-agent

  ARCH_BUILD_OUTPUT=".build/$ARCH-apple-macosx/release/$EXECUTABLE_NAME"
  ARCH_AGENT_OUTPUT=".build/$ARCH-apple-macosx/release/ahakeyconfig-agent"
  if [[ ! -f "$ARCH_BUILD_OUTPUT" ]]; then
    echo "Build output not found at $ARCH_BUILD_OUTPUT"
    exit 1
  fi
  if [[ ! -f "$ARCH_AGENT_OUTPUT" ]]; then
    echo "Agent build output not found at $ARCH_AGENT_OUTPUT"
    exit 1
  fi
  BUILD_OUTPUTS+=("$ARCH_BUILD_OUTPUT")
  AGENT_OUTPUTS+=("$ARCH_AGENT_OUTPUT")
done

echo "🧱 Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$OUTPUT_DIR"

ICONSET_DIR="$APP_ROOT/.build/AhaKeyConfig.iconset"
ICNS_PATH="$APP_ROOT/.build/AhaKeyConfig.icns"

echo "🎨 Generating app icon..."
if [[ -f "$ICON_SOURCE" ]]; then
  swift "$APP_ROOT/scripts/generate_icons.swift" "$ICONSET_DIR" "$ICON_SOURCE"
else
  swift "$APP_ROOT/scripts/generate_icons.swift" "$ICONSET_DIR"
fi
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"

echo "🌐 Generating localization strings..."
python3 "$APP_ROOT/scripts/generate_localizations.py"

for LPROJ in "$APP_ROOT"/Resources/*.lproj; do
  if [[ -d "$LPROJ" ]]; then
    ditto "$LPROJ" "$APP_BUNDLE/Contents/Resources/$(basename "$LPROJ")"
  fi
done

if [[ ${#BUILD_OUTPUTS[@]} -gt 1 ]]; then
  lipo -create "${BUILD_OUTPUTS[@]}" -output "$APP_EXECUTABLE"
  lipo -create "${AGENT_OUTPUTS[@]}" -output "$AGENT_EXECUTABLE"
else
  cp "$BUILD_OUTPUTS[1]" "$APP_EXECUTABLE"
  cp "$AGENT_OUTPUTS[1]" "$AGENT_EXECUTABLE"
fi
cp "$ICNS_PATH" "$APP_BUNDLE/Contents/Resources/AhaKeyConfig.icns"
if [[ -d "$APP_ROOT/Resources/Help" ]]; then
  mkdir -p "$APP_BUNDLE/Contents/Resources/Help"
  ditto "$APP_ROOT/Resources/Help" "$APP_BUNDLE/Contents/Resources/Help"
fi
if [[ -d "$APP_ROOT/Resources/DefaultOLED" ]]; then
  mkdir -p "$APP_BUNDLE/Contents/Resources/DefaultOLED"
  ditto "$APP_ROOT/Resources/DefaultOLED" "$APP_BUNDLE/Contents/Resources/DefaultOLED"
fi

REPO_ROOT="$(git -C "$APP_ROOT" rev-parse --show-toplevel 2>/dev/null || echo "$APP_ROOT")"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$REPO_ROOT" rev-list --count HEAD 2>/dev/null || echo 1)}"
GIT_COMMIT="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"

cat > "$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh-Hans</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>zh-Hans</string>
    <string>en</string>
  </array>
  <key>CFBundleDisplayName</key>
  <string>${APP_DISPLAY_NAME}</string>
  <key>CFBundleExecutable</key>
  <string>${EXECUTABLE_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${APP_IDENTIFIER}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleIconFile</key>
  <string>AhaKeyConfig</string>
  <key>CFBundleName</key>
  <string>${APP_DISPLAY_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${APP_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD_NUMBER}</string>
  <key>AhaKeyGitCommit</key>
  <string>${GIT_COMMIT}</string>
  <key>LSMinimumSystemVersion</key>
  <string>${MACOS_DEPLOYMENT_TARGET}</string>
  <key>NSBluetoothAlwaysUsageDescription</key>
  <string>AhaKey 配置需要蓝牙连接你的 AhaKey 键盘。</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>AhaKey Studio 需要访问麦克风，才能使用苹果原生语音转写。</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>AhaKey Studio 需要语音识别权限，才能把语音键转换成苹果原生转写。</string>
</dict>
</plist>
PLIST

mkdir -p "$(dirname "$ENTITLEMENTS")"
cat > "$ENTITLEMENTS" <<'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.device.bluetooth</key>
  <true/>
  <key>com.apple.security.device.audio-input</key>
  <true/>
</dict>
</plist>
ENTITLEMENTS

find_developer_id() {
  local identities
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  if [[ -n "$SIGNING_IDENTITY_HINT" ]]; then
    echo "$identities" | grep 'Developer ID Application' | grep "$SIGNING_IDENTITY_HINT" | head -n 1 | sed -E 's/.*"(.+)"/\1/' || true
  else
    echo "$identities" | grep 'Developer ID Application' | head -n 1 | sed -E 's/.*"(.+)"/\1/' || true
  fi
}

find_apple_development() {
  local identities
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  if [[ -n "$SIGNING_IDENTITY_HINT" ]]; then
    echo "$identities" | grep 'Apple Development' | grep "$SIGNING_IDENTITY_HINT" | head -n 1 | sed -E 's/.*"(.+)"/\1/' || true
  else
    echo "$identities" | grep 'Apple Development' | head -n 1 | sed -E 's/.*"(.+)"/\1/' || true
  fi
}

if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(find_developer_id)"
fi

if [[ -z "$SIGNING_IDENTITY" && "$REQUIRE_DEVELOPER_ID" != "1" ]]; then
  SIGNING_IDENTITY="$(find_apple_development)"
fi

if [[ "$REQUIRE_DEVELOPER_ID" == "1" && -z "$SIGNING_IDENTITY" ]]; then
  echo "❌ No Developer ID Application identity found in keychain."
  echo "   Please install a Developer ID Application certificate first."
  exit 1
fi

if [[ -n "${SIGNING_IDENTITY}" ]]; then
  echo "🔏 Signing with: $SIGNING_IDENTITY"
  SIGN_ARGS=(--force --sign "$SIGNING_IDENTITY")
  APP_SIGN_ARGS=("${SIGN_ARGS[@]}")

  if [[ "$SIGNING_IDENTITY" == Developer\ ID\ Application:* ]]; then
    SIGN_ARGS+=(--timestamp --options runtime)
    APP_SIGN_ARGS=("${SIGN_ARGS[@]}" --entitlements "$ENTITLEMENTS")
  else
    APP_SIGN_ARGS+=(--entitlements "$ENTITLEMENTS")
  fi

  xattr -cr "$APP_BUNDLE" 2>/dev/null || true
  codesign "${SIGN_ARGS[@]}" "$AGENT_EXECUTABLE"
  codesign "${APP_SIGN_ARGS[@]}" "$APP_BUNDLE"
else
  if [[ "$REQUIRE_DEVELOPER_ID" == "1" ]]; then
    echo "❌ RELEASE_DISTRIBUTION requires a valid Developer ID Application identity."
    exit 1
  fi
  echo "🧪 No signing identity found, using ad-hoc signature for local testing"
  xattr -cr "$APP_BUNDLE" 2>/dev/null || true
  codesign --force --sign - "$AGENT_EXECUTABLE"
  codesign --force --sign - "$APP_BUNDLE"
fi

echo "🔎 Verifying app signature..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

if [[ "$INSTALL_TO_APPLICATIONS" == "1" ]]; then
  echo "📥 Installing to $DEST_APP..."

  # 单实例：关闭已运行的实例
  if pgrep -f "$DEST_APP/Contents/MacOS/$EXECUTABLE_NAME" >/dev/null 2>&1; then
    osascript -e "tell application id \"$APP_IDENTIFIER\" to quit" 2>/dev/null || true
    for _ in {1..20}; do
      pgrep -f "$DEST_APP/Contents/MacOS/$EXECUTABLE_NAME" >/dev/null 2>&1 || break
      sleep 0.25
    done
    pkill -9 -f "$DEST_APP/Contents/MacOS/$EXECUTABLE_NAME" 2>/dev/null || true
    sleep 0.3
  fi

  rm -rf "$DEST_APP"
  mkdir -p "$INSTALL_DIR"
  ditto "$APP_BUNDLE" "$DEST_APP"
  xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true

  LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -f "$DEST_APP" >/dev/null 2>&1 || true
  fi

  if [[ "$LAUNCH_AFTER_INSTALL" == "1" ]]; then
    open "$DEST_APP"
  fi
fi

echo "✅ Build complete: $APP_BUNDLE"
