#!/usr/bin/env bash
set -euo pipefail

BRIDGE_HOME="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$HOME/Library/Application Support/VibeKeyboard/BLETcpBridge"
LOG_FILE="$LOG_DIR/bridge_console.log"

mkdir -p "$LOG_DIR"
export BLE_TCP_BRIDGE_HOME="$BRIDGE_HOME"

cd "$BRIDGE_HOME"
clear
echo "=== BLETcpBridge ==="
echo "Log file: $LOG_FILE"
echo
"$BRIDGE_HOME/BleTcpBridge" "$@" 2>&1 | tee -a "$LOG_FILE"
echo
echo "Bridge exited. Press Enter to close this window."
read -r _
