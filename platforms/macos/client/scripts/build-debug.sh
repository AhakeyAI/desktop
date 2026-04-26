#!/bin/zsh
# 快速 debug 构建 → 直接把产物塞进 dist/AhaKey Studio.app
# 用于 Xcode Scheme Pre-action，每次 Cmd+R 前自动刷新 .app 里的二进制。
# 111
# 关键点：
# 1. 不重新生成 icon、Info.plist、entitlements（如果已存在就复用）——省时
# 2. 保持 .app 路径、Bundle ID、entitlements 三件不变，TCC 授权条目才能匹配
# 3. 优先使用 AHAKEY_DEBUG_SIGNING_IDENTITY 环境变量指定的签名身份（建议自签证书）
#    没有就 fall back 到 ad-hoc；ad-hoc 情况下改完代码 TCC 可能需要重新授权

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

EXECUTABLE_NAME="AhaKeyConfig"
APP_BUNDLE_NAME="${APP_BUNDLE_NAME:-AhaKey Studio}"
APP_DISPLAY_NAME="${APP_DISPLAY_NAME:-AhaKey Studio}"
APP_IDENTIFIER="lab.jawa.ahakeyconfig"
OUTPUT_DIR="${OUTPUT_DIR:-$APP_ROOT/dist}"
APP_BUNDLE="$OUTPUT_DIR/$APP_BUNDLE_NAME.app"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
AGENT_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/ahakeyconfig-agent"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
ENTITLEMENTS="$APP_ROOT/.build/AhaKeyConfig.entitlements"
ICON_SOURCE="${ICON_SOURCE:-$APP_ROOT/VibeCodeKeyboard.ico}"
ICONSET_DIR="$APP_ROOT/.build/AhaKeyConfig.iconset"
ICNS_PATH="$APP_ROOT/.build/AhaKeyConfig.icns"
SIGNING_IDENTITY="${AHAKEY_DEBUG_SIGNING_IDENTITY:-${SIGNING_IDENTITY:-}}"

# 本地 Debug 默认启用稳定自签证书：TCC 会按证书 CN 记授权，
# 避免 ad-hoc 签名每次 build 因 cdhash 变化而掉权限。
# 若显式设置 AHAKEY_DEBUG_ADHOC=1 则强制回退到 ad-hoc（调试签名问题时用）。
if [[ -z "$SIGNING_IDENTITY" ]] && [[ "${AHAKEY_DEBUG_ADHOC:-0}" != "1" ]]; then
  if [[ -x "$SCRIPT_DIR/ensure-dev-signing.sh" ]]; then
    if auto_identity="$("$SCRIPT_DIR/ensure-dev-signing.sh")"; then
      SIGNING_IDENTITY="$auto_identity"
    else
      echo "⚠️  ensure-dev-signing.sh 失败，fall back 到 ad-hoc 签名"
    fi
  fi
fi

echo "🐞 Debug building $APP_DISPLAY_NAME..."
cd "$APP_ROOT"
swift build -c debug --arch arm64 --product AhaKeyConfig
swift build -c debug --arch arm64 --product ahakeyconfig-agent

BUILD_OUTPUT=".build/arm64-apple-macosx/debug/$EXECUTABLE_NAME"
AGENT_OUTPUT=".build/arm64-apple-macosx/debug/ahakeyconfig-agent"
if [[ ! -f "$BUILD_OUTPUT" ]]; then
  echo "Build output not found at $BUILD_OUTPUT"
  exit 1
fi

mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$OUTPUT_DIR"

# 内置默认 OLED 动图：供 AhaKeyOLEDDraft 在用户未自定义时作为出厂预览/上传素材。
# 放在 Contents/Resources/DefaultOLED/，代码里通过 Bundle.main 访问。
if [[ -d "$APP_ROOT/Resources/DefaultOLED" ]]; then
  mkdir -p "$APP_BUNDLE/Contents/Resources/DefaultOLED"
  # --delete 保证删掉/换名资源也会同步；同时排除 macOS 隐藏文件以免混进 bundle。
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete \
      --exclude='.DS_Store' --exclude='._*' --exclude='.*.swp' \
      "$APP_ROOT/Resources/DefaultOLED/" \
      "$APP_BUNDLE/Contents/Resources/DefaultOLED/"
  else
    rm -rf "$APP_BUNDLE/Contents/Resources/DefaultOLED"
    mkdir -p "$APP_BUNDLE/Contents/Resources/DefaultOLED"
    find "$APP_ROOT/Resources/DefaultOLED" -type f \
      ! -name '.DS_Store' ! -name '._*' ! -name '.*.swp' \
      -exec cp {} "$APP_BUNDLE/Contents/Resources/DefaultOLED/" \;
  fi
fi

# icon：只在缺失时生成，避免每次 Run 都跑一遍 iconutil
if [[ ! -f "$APP_BUNDLE/Contents/Resources/AhaKeyConfig.icns" ]]; then
  echo "🎨 Generating app icon (first run)..."
  if [[ -f "$ICON_SOURCE" ]]; then
    swift "$APP_ROOT/scripts/generate_icons.swift" "$ICONSET_DIR" "$ICON_SOURCE"
  else
    swift "$APP_ROOT/scripts/generate_icons.swift" "$ICONSET_DIR"
  fi
  iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"
  cp "$ICNS_PATH" "$APP_BUNDLE/Contents/Resources/AhaKeyConfig.icns"
fi

BUILD_NUMBER="$(git -C "$APP_ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"

# Info.plist：只在缺失或 identifier 不对时重写，保证 Bundle ID 恒定 → TCC 条目稳定
NEED_PLIST=1
if [[ -f "$INFO_PLIST" ]] && /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO_PLIST" 2>/dev/null | grep -qx "$APP_IDENTIFIER"; then
  NEED_PLIST=0
fi
if [[ "$NEED_PLIST" == "1" ]]; then
  cat > "$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
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
  <string>0.1.0-debug</string>
  <key>CFBundleVersion</key>
  <string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>NSBluetoothAlwaysUsageDescription</key>
  <string>AhaKey 配置需要蓝牙连接你的 AhaKey 键盘。</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>AhaKey Studio 需要访问麦克风，才能使用苹果原生语音转写。</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>AhaKey Studio 需要语音识别权限，才能把语音键转换成苹果原生转写。</string>
</dict>
</plist>
PLIST
fi

mkdir -p "$(dirname "$ENTITLEMENTS")"
if [[ ! -f "$ENTITLEMENTS" ]]; then
  cat > "$ENTITLEMENTS" <<'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.device.bluetooth</key>
  <true/>
</dict>
</plist>
ENTITLEMENTS
fi

cp "$BUILD_OUTPUT" "$APP_EXECUTABLE"
cp "$AGENT_OUTPUT" "$AGENT_EXECUTABLE"

if [[ -n "$SIGNING_IDENTITY" ]]; then
  # 对 40 位十六进制（SHA-1）用 security 反查一下 CN，方便日志定位
  if [[ "$SIGNING_IDENTITY" =~ ^[0-9A-Fa-f]{40}$ ]]; then
    IDENTITY_CN="$(security find-identity -p codesigning "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null \
      | awk -v sha="$SIGNING_IDENTITY" '$2 == sha { sub(/.*"/,""); sub(/".*/,""); print; exit }')"
    echo "🔏 Debug signing with: $SIGNING_IDENTITY${IDENTITY_CN:+ ($IDENTITY_CN)}"
  else
    echo "🔏 Debug signing with: $SIGNING_IDENTITY"
  fi
  codesign --force --sign "$SIGNING_IDENTITY" --entitlements "$ENTITLEMENTS" "$APP_EXECUTABLE"
  codesign --force --sign "$SIGNING_IDENTITY" "$AGENT_EXECUTABLE"
  codesign --force --sign "$SIGNING_IDENTITY" --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"
else
  echo "🧪 Ad-hoc signing (TCC may need re-grant after code changes)."
  codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP_EXECUTABLE"
  codesign --force --sign - "$AGENT_EXECUTABLE"
  codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"
fi

# 清掉所有 com.apple.quarantine 扩展属性
# 否则 ad-hoc 签名 + quarantine 会触发 Gatekeeper App Translocation：
# macOS 会把 .app 拷到 /private/var/folders/.../AppTranslocation/<随机UUID>/ 再启动，
# 每次启动路径都不同，TCC 授权永远失配，“输入监控/辅助功能”永远识别不到。
xattr -rd com.apple.quarantine "$APP_BUNDLE" 2>/dev/null || true

# 强制 LaunchServices 刷新，避免 macOS 缓存到旧的 bundle 元数据
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$APP_BUNDLE" >/dev/null 2>&1 || true
fi

echo "✅ Debug bundle ready: $APP_BUNDLE"
