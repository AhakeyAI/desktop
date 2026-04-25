#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

NOTARY_PROFILE="${NOTARY_PROFILE:-AhaKeyNotary}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
OUTPUT_DIR="${OUTPUT_DIR:-$APP_ROOT/dist}"

echo "🚀 Building formal distribution DMG..."

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
NOTARY_PROFILE="$NOTARY_PROFILE" \
OUTPUT_DIR="$OUTPUT_DIR" \
zsh "$SCRIPT_DIR/package_dmg.sh"

echo "✅ Formal distribution package complete."
