#!/bin/zsh
# 本地开发专用：一键修复 Debug build 的 TCC 权限失效。
#
# 作用：
#   1. 确保本地自签证书存在（ensure-dev-signing.sh）
#   2. 用该证书重签 dist/AhaKey Studio.app 里的所有二进制
#   3. 重置 AhaKey Studio 相关的 TCC 授权条目
#
# 这样用户下一次启动 App 时：
#   - cdhash 变了没关系，TCC 按证书 CN 重新认
#   - 系统会弹权限窗，一次勾选后永久生效
#
# 使用：
#   - 点击 App 里"开发版：修复签名 & 权限"按钮会自动调用
#   - 也可以手动执行：scripts/fix-debug-permissions.sh
#
# 注意：不影响 scripts/build.sh（release 流程）。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_BUNDLE_NAME="${APP_BUNDLE_NAME:-AhaKey Studio}"
APP_BUNDLE="$APP_ROOT/dist/$APP_BUNDLE_NAME.app"
APP_IDENTIFIER="${APP_IDENTIFIER:-lab.jawa.ahakeyconfig}"
ENTITLEMENTS="$APP_ROOT/.build/AhaKeyConfig.entitlements"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "❌ 找不到 $APP_BUNDLE"
  echo "   请先运行 scripts/build-debug.sh 或通过 Xcode 构建一次。"
  exit 1
fi

echo "🔐 步骤 1/3  获取/创建本地自签证书"
IDENTITY="$("$SCRIPT_DIR/ensure-dev-signing.sh")"
echo "   使用证书: $IDENTITY"

echo "🔏 步骤 2/3  用该证书重签 $APP_BUNDLE"

APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/AhaKeyConfig"
AGENT_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/ahakeyconfig-agent"

if [[ -f "$AGENT_EXECUTABLE" ]]; then
  codesign --force --sign "$IDENTITY" "$AGENT_EXECUTABLE"
fi

if [[ -f "$ENTITLEMENTS" ]]; then
  codesign --force --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" "$APP_EXECUTABLE"
  codesign --force --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"
else
  codesign --force --sign "$IDENTITY" "$APP_EXECUTABLE"
  codesign --force --sign "$IDENTITY" "$APP_BUNDLE"
fi

xattr -rd com.apple.quarantine "$APP_BUNDLE" 2>/dev/null || true

echo "🧹 步骤 3/3  重置 $APP_IDENTIFIER 的 TCC 授权"

# Bluetooth 不支持按 bundle id 重置，跳过
for svc in ListenEvent Accessibility PostEvent Microphone SpeechRecognition; do
  if tccutil reset "$svc" "$APP_IDENTIFIER" >/dev/null 2>&1; then
    echo "   ✓ reset $svc"
  else
    echo "   - skip $svc (无旧条目)"
  fi
done

echo ""
echo "✅ 修复完成。"
echo "   下一步：退出 AhaKey Studio，重新启动后按系统提示重新勾选权限即可。"
echo "   之后再改代码、再 build，TCC 都会按证书 CN 记住授权，不会再掉。"
