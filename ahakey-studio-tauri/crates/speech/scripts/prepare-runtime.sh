#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="${1:-$SCRIPT_DIR/../runtime}"

mkdir -p "$RUNTIME_DIR"
RUNTIME_ROOT="$(cd "$RUNTIME_DIR" && pwd)"

ARCH="$(uname -m)"
if [[ "$ARCH" == "arm64" ]]; then
    STEM="sherpa-onnx-v1.13.7-osx-arm64-shared-lib"
    EXPECTED_HASH="c51e220217f2ce5d3de211887dc13ad49bf22346a2025a4159591d892008242d"
elif [[ "$ARCH" == "x86_64" ]]; then
    STEM="sherpa-onnx-v1.13.7-osx-x64-shared-lib"
    EXPECTED_HASH="24182aef70b889868dbfd943a7f2246383dd1cd196b9b86c20b9642e7b2c396f"
else
    echo "Unsupported architecture: $ARCH" >&2
    exit 1
fi

ARCHIVE="$RUNTIME_ROOT/$STEM.tar.bz2"
if [[ ! -f "$ARCHIVE" ]]; then
    TEMP_FILE="$RUNTIME_ROOT/$(uuidgen || date +%s).part"
    curl -fsSL "https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.7/$STEM.tar.bz2" -o "$TEMP_FILE"
    if [[ -n "$EXPECTED_HASH" ]]; then
        CALCULATED_HASH="$(shasum -a 256 "$TEMP_FILE" | awk '{print $1}')"
        if [[ "$CALCULATED_HASH" != "$EXPECTED_HASH" ]]; then
            rm -f "$TEMP_FILE"
            echo "Native runtime archive SHA256 mismatch" >&2
            exit 1
        fi
    fi
    mv "$TEMP_FILE" "$ARCHIVE"
fi

if [[ -n "$EXPECTED_HASH" ]]; then
    CALCULATED_HASH="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
    if [[ "$CALCULATED_HASH" != "$EXPECTED_HASH" ]]; then
        echo "Cached native runtime archive SHA256 mismatch" >&2
        exit 1
    fi
fi

tar -xf "$ARCHIVE" -C "$RUNTIME_ROOT"

LIB_DIR="$RUNTIME_ROOT/$STEM/lib"
if [[ ! -f "$LIB_DIR/libsherpa-onnx-c-api.dylib" ]]; then
    echo "Runtime import library missing: $LIB_DIR" >&2
    exit 1
fi

NOTICES="$RUNTIME_ROOT/licenses"
mkdir -p "$NOTICES"
if [[ -d "$SCRIPT_DIR/../licenses" ]]; then
    cp "$SCRIPT_DIR/../licenses/"* "$NOTICES/" 2>/dev/null || true
fi

ORT_NOTICES="$NOTICES/onnxruntime-ThirdPartyNotices.txt"
NOTICE_HASH="0e07b95f3a8d6230037707c5c4a2b554d12c4cb67369669ac255635528ffcee2"
if [[ ! -f "$ORT_NOTICES" ]]; then
    TEMP_NOTICE="$NOTICES/$(uuidgen || date +%s).part"
    curl -fsSL "https://raw.githubusercontent.com/microsoft/onnxruntime/v1.27.1/ThirdPartyNotices.txt" -o "$TEMP_NOTICE"
    CALC_NOTICE="$(shasum -a 256 "$TEMP_NOTICE" | awk '{print $1}')"
    if [[ "$CALC_NOTICE" != "$NOTICE_HASH" ]]; then
        rm -f "$TEMP_NOTICE"
        echo "ONNX Runtime notices SHA256 mismatch" >&2
        exit 1
    fi
    mv "$TEMP_NOTICE" "$ORT_NOTICES"
fi

echo "$LIB_DIR"
