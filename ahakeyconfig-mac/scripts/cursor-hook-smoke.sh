#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test -d /tmp
TEMP_HOME="$(mktemp -d "/tmp/ahakey-cursor-hook.XXXXXX")"
trap 'rm -rf "$TEMP_HOME"' EXIT

cd "$ROOT"
swift build --product ahakeyconfig-agent

HOME="$TEMP_HOME" \
CFFIXED_USER_HOME="$TEMP_HOME" \
AHAKEY_CURSOR_PROCESS_SMOKE=1 \
AHAKEY_AGENT_BINARY="$ROOT/.build/debug/ahakeyconfig-agent" \
swift test --filter CursorHookRuntimeClientTests.testAgentProcessAgainstFakeRuntime

echo "cursor-hook-process-smoke: PASS"
