#!/bin/zsh
# Downloads the pinned sherpa-onnx static libraries (Apache-2.0) and packs them
# into Vendor/SherpaOnnxC.xcframework so SwiftPM can link the local speech
# engines (SenseVoice / Whisper). Same sherpa-onnx version as
# ahakey-studio-tauri/crates/speech (=1.13.7).
#
# Without this framework the app still builds; local engines are simply
# unavailable and Apple Speech is used.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VERSION="1.13.7"
TARBALL_NAME="sherpa-onnx-v${VERSION}-osx-universal2-static-no-tts-lib"
TARBALL_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/v${VERSION}/${TARBALL_NAME}.tar.bz2"
TARBALL_SHA256="69c9cdc1080700a9ecec51401eaf87150ef2c1771ccaa65b8295f3cc0d34203c"
HEADER_URL="https://raw.githubusercontent.com/k2-fsa/sherpa-onnx/v${VERSION}/sherpa-onnx/c-api/c-api.h"
HEADER_SHA256="426db2c6acfb51e02143aece67c45779fae699d961c7c26ccf6f1388fdeaa2df"

VENDOR_DIR="$APP_ROOT/Vendor"
OUTPUT="$VENDOR_DIR/SherpaOnnxC.xcframework"
STAMP="$VENDOR_DIR/.sherpa-onnx-version"

if [[ -d "$OUTPUT" && -f "$STAMP" && "$(cat "$STAMP")" == "$VERSION" && "${FORCE:-0}" != "1" ]]; then
  echo "✅ sherpa-onnx $VERSION already vendored at $OUTPUT"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

verify() {
  local file="$1" expected="$2"
  local actual
  actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  if [[ "$actual" != "$expected" ]]; then
    echo "❌ SHA256 mismatch for $(basename "$file"): expected $expected, got $actual" >&2
    exit 1
  fi
}

echo "⬇️  Downloading sherpa-onnx $VERSION static libraries..."
curl -fL --retry 3 -o "$WORK/lib.tar.bz2" "$TARBALL_URL"
verify "$WORK/lib.tar.bz2" "$TARBALL_SHA256"
curl -fL --retry 3 -o "$WORK/c-api.h" "$HEADER_URL"
verify "$WORK/c-api.h" "$HEADER_SHA256"

tar xjf "$WORK/lib.tar.bz2" -C "$WORK"
LIB_DIR="$WORK/$TARBALL_NAME/lib"

echo "🔗 Merging static libraries..."
# portaudio is only used by sherpa-onnx's own CLI tools; we capture audio with AVAudioEngine.
libs=("${(@f)$(find "$LIB_DIR" -name '*.a' ! -name '*portaudio*' | sort)}")
libtool -static -o "$WORK/libsherpa-onnx.a" "${libs[@]}" 2>/dev/null

mkdir -p "$WORK/include"
cp "$WORK/c-api.h" "$WORK/include/sherpa-onnx-c-api.h"
cat > "$WORK/include/module.modulemap" <<'EOF'
module SherpaOnnxC {
    header "sherpa-onnx-c-api.h"
    link "c++"
    export *
}
EOF

mkdir -p "$VENDOR_DIR"
rm -rf "$OUTPUT"
xcodebuild -create-xcframework \
  -library "$WORK/libsherpa-onnx.a" \
  -headers "$WORK/include" \
  -output "$OUTPUT" >/dev/null
echo "$VERSION" > "$STAMP"
echo "✅ Vendored sherpa-onnx $VERSION at $OUTPUT"
