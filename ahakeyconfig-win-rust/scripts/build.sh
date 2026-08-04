#!/usr/bin/env bash
# 构建 Rust 版 AhaKey Studio
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Installing UI dependencies..."
cd ui
npm install
echo "==> Building UI..."
npm run build
cd ..

echo "==> Building Rust release..."
cd src-tauri
cargo build --release
cd ..

echo ""
echo "==> Build complete!"
echo "Executable: $ROOT/src-tauri/target/release/ahakey-studio.exe"
echo ""
echo "Run benchmark:"
echo "  python scripts/compare.py"
