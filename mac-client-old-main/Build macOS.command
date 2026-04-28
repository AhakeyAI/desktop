å#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="$ROOT_DIR/.venv"
SELECTED_PYTHON=""

cd "$ROOT_DIR"

for candidate in python3.13 python3.12 python3.11 python3.10 python3; do
  if command -v "$candidate" >/dev/null 2>&1; then
    version="$("$candidate" - <<'PY'
import sys
print(f"{sys.version_info.major}.{sys.version_info.minor}")
PY
)"
    case "$version" in
      3.10|3.11|3.12|3.13)
        SELECTED_PYTHON="$candidate"
        break
        ;;
    esac
  fi
done

if [ -z "$SELECTED_PYTHON" ]; then
  osascript -e 'display dialog "未找到可用的 Python 3.10-3.13。请先安装 Python 3.13，再重新双击本文件。" buttons {"确定"} default button "确定"'
  exit 1
fi

if [ ! -d "$VENV_DIR" ]; then
  "$SELECTED_PYTHON" -m venv "$VENV_DIR"
fi

source "$VENV_DIR/bin/activate"
chmod +x "$ROOT_DIR/build_macos.sh"
PYTHON_BIN="$VENV_DIR/bin/python3" "$ROOT_DIR/build_macos.sh"

osascript -e 'display dialog "macOS 安装包构建完成，发布文件在 dist-macos/release/ 目录。" buttons {"确定"} default button "确定"'
