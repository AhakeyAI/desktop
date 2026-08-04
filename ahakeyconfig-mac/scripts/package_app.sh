#!/usr/bin/env bash
# 把 AhaKeyConfig 组装成 ad-hoc 签名的 "AhaKey Studio.app"。
# 本地与 CI 共用;产物落在 ahakeyconfig-mac/dist/。
#
#   APP_VERSION=1.2.3 APP_BUILD=42 scripts/package_app.sh
#
# 版本号可用环境变量覆盖,缺省时 version=0.0.0、build=git 提交数。
set -euo pipefail

cd "$(dirname "$0")/.."          # -> ahakeyconfig-mac

CONFIG="release"
APP_NAME="AhaKey Studio"
EXEC="AhaKeyConfig"
DIST="dist"
APP="${DIST}/${APP_NAME}.app"

echo "==> swift build -c ${CONFIG} --product ${EXEC}"
swift build -c "${CONFIG}" --product "${EXEC}"
BIN_PATH="$(swift build -c "${CONFIG}" --show-bin-path)"

echo "==> assembling ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN_PATH}/${EXEC}" "${APP}/Contents/MacOS/${EXEC}"

VERSION="${APP_VERSION:-0.0.0}"
BUILD="${APP_BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"

# EmbeddedInfo.plist 只含 TCC 权限键(已嵌进二进制的 __info_plist 段);
# bundle 的 Contents/Info.plist 还需要 CFBundleExecutable 等键,这里补全。
cat > "${APP}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>${APP_NAME}</string>
	<key>CFBundleDisplayName</key><string>${APP_NAME}</string>
	<key>CFBundleIdentifier</key><string>lab.jawa.ahakeyconfig</string>
	<key>CFBundleExecutable</key><string>${EXEC}</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>${VERSION}</string>
	<key>CFBundleVersion</key><string>${BUILD}</string>
	<key>LSMinimumSystemVersion</key><string>12.0</string>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSBluetoothAlwaysUsageDescription</key><string>AhaKey 配置需要蓝牙连接你的 AhaKey 键盘。</string>
	<key>NSMicrophoneUsageDescription</key><string>AhaKey Studio 需要访问麦克风，才能使用苹果原生语音转写。</string>
	<key>NSSpeechRecognitionUsageDescription</key><string>AhaKey Studio 需要语音识别权限，才能把语音键转换成苹果原生转写。</string>
</dict>
</plist>
PLIST

# 默认资源(OLED 动图等),存在才拷。
if [ -d "Resources" ]; then
	cp -R "Resources/." "${APP}/Contents/Resources/" 2>/dev/null || true
fi

# ad-hoc 签名,让产物在本地/CI 检查时可被 Gatekeeper 识别为已签名(非公证)。
codesign --force --deep --sign - "${APP}" 2>/dev/null || echo "warn: codesign skipped (no codesign available)"

echo "==> done: ${APP}  (version ${VERSION}, build ${BUILD})"
