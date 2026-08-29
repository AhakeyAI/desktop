#!/bin/zsh
# 校验冻结身份与候选/模板，不调用 codesign 签名、不安装。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CANDIDATE="${1:-}"

python3 "$SCRIPT_DIR/release_identity.py" check "$APP_ROOT" "$CANDIDATE"
