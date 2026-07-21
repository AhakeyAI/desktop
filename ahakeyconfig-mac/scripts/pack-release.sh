#!/bin/zsh
# 可分发安装包（Developer ID + 公证）：对内测试与对外发版用同一流程即可。
# 需要「快速本地调试、不跑公证」时可直接：zsh scripts/build.sh
#
# 内部调用 package_dmg.sh、build.sh。
#
# 产出：dist/AhaKey Studio.app
#       dist/AhaKey-Studio-macOS-prod-YYYYMMDDHHmmss.dmg（可用 DMG_BASENAME 覆盖）
#
# 用法：
#   zsh scripts/pack-release.sh
#   zsh /path/to/ahakeyconfig/scripts/pack-release.sh
#
# 可选环境变量：APP_VERSION、BUILD_NUMBER、NOTARY_PROFILE、SIGNING_IDENTITY、SIGNING_IDENTITY_HINT、OUTPUT_DIR、DMG_BASENAME

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$APP_ROOT"

if [[ -f "$SCRIPT_DIR/build.local.env" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/build.local.env"
fi

NOTARY_PROFILE="${NOTARY_PROFILE:-AhaKeyNotary}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
SIGNING_IDENTITY_HINT="${SIGNING_IDENTITY_HINT:-}"
OUTPUT_DIR="${OUTPUT_DIR:-$APP_ROOT/dist}"
if [[ -z "${DMG_BASENAME:-}" ]]; then
  DMG_BASENAME="AhaKey-Studio-macOS-prod-$(date +%Y%m%d%H%M%S)"
fi

echo "🚀 Building formal distribution DMG → $DMG_BASENAME.dmg"

if [[ -z "$SIGNING_IDENTITY" && -n "$SIGNING_IDENTITY_HINT" ]]; then
  SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep 'Developer ID Application' | grep -F "$SIGNING_IDENTITY_HINT" | head -n 1 | sed -E 's/.*"(.+)"/\1/' || true)"
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep 'Developer ID Application' | head -n 1 | sed -E 's/.*"(.+)"/\1/' || true)"
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "❌ Missing Developer ID Application certificate."
  echo "   Install the certificate in your login keychain, then retry."
  exit 1
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "❌ Notary profile '$NOTARY_PROFILE' is not available."
  echo "   Create it first with:"
  echo "   xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id <apple-id> --team-id <team-id> --password <app-specific-password>"
  exit 1
fi

RELEASE_DISTRIBUTION=1 \
SIGNING_IDENTITY="$SIGNING_IDENTITY" \
SIGNING_IDENTITY_HINT="$SIGNING_IDENTITY_HINT" \
NOTARY_PROFILE="$NOTARY_PROFILE" \
OUTPUT_DIR="$OUTPUT_DIR" \
DMG_BASENAME="$DMG_BASENAME" \
zsh "$SCRIPT_DIR/package_dmg.sh"

echo "✅ Formal distribution package complete."
