#!/usr/bin/env bash
# WBS 5.2 真实双进程签名 smoke 脚本
# 要求：macOS 12+、codesign、swift、Developer ID Application 证书
# 行为：
#   1. 编译 smoke server/client helper
#   2. 正向：Developer ID 签名 helper → 启动临时 Mach service → client 连接并完成 handshake + 业务请求
#   3. 负向：同一 client 改用 ad-hoc 签名 → libxpc 在 payload 处理前拒绝 → server 业务 endpoint 调用数保持 0
#   4. 退出路径无条件 bootout/清理

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."
# launchd/dyld 从 ~/Documents 下的 .build 加载会挂起；签名副本放到 /tmp。
BUILD_DIR="/tmp/ahakey-xpc-smoke-$(date +%s)"
TMP_DIR="$(mktemp -d -t ahakey-xpc-smoke)"
RESULT_PATH="${TMP_DIR}/result.json"

# 随机临时 Mach service label（用户域）
SERVICE_LABEL="lab.jawa.ahakeyconfig.xpc-smoke.$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-')"
PLIST_PATH="${TMP_DIR}/${SERVICE_LABEL}.plist"
SERVER_BIN="${BUILD_DIR}/RuntimeXPCSmokeServer"
CLIENT_BIN="${BUILD_DIR}/RuntimeXPCSmokeClient"

# 签名身份（正向）
DEV_ID="Developer ID Application: Xinyang Zhang (P2VFVRZK7P)"
TEAM_ID="P2VFVRZK7P"
ALLOWED_SIGNING_ID="lab.jawa.ahakeyconfig"

# 超时设置
SERVER_TIMEOUT_SEC=15
CLIENT_TIMEOUT_SEC=12

cleanup() {
    local ec=$?
    # 无论成功/失败/中断，都尝试 bootout 并清理临时资源
    if [[ -f "${PLIST_PATH}" ]]; then
        launchctl bootout "gui/$(id -u)/${SERVICE_LABEL}" 2>/dev/null || true
    fi
    rm -rf "${TMP_DIR}" "${BUILD_DIR}" 2>/dev/null || true
    exit $ec
}
trap cleanup EXIT INT TERM

# ── 1. 编译 ──
echo "[smoke] Building smoke helpers..."
mkdir -p "${BUILD_DIR}"
cd "${PROJECT_DIR}"
swift build --product RuntimeXPCSmokeServer --product RuntimeXPCSmokeClient 2>&1 | tail -5
cp "${PROJECT_DIR}/.build/debug/RuntimeXPCSmokeServer" "${SERVER_BIN}"
cp "${PROJECT_DIR}/.build/debug/RuntimeXPCSmokeClient" "${CLIENT_BIN}"

# ── 2. 正向签名 ──
echo "[smoke] Signing helpers with Developer ID..."
codesign --force --options runtime --sign "${DEV_ID}" --identifier "${ALLOWED_SIGNING_ID}" --timestamp "${SERVER_BIN}"
codesign --force --options runtime --sign "${DEV_ID}" --identifier "${ALLOWED_SIGNING_ID}" --timestamp "${CLIENT_BIN}"

# 验证签名身份
echo "[smoke] Verifying signing identities..."
codesign -dv --verbose=4 "${SERVER_BIN}" 2>&1 | grep -E 'Identifier|TeamIdentifier|Authority'
codesign -dv --verbose=4 "${CLIENT_BIN}" 2>&1 | grep -E 'Identifier|TeamIdentifier|Authority'

# ── 3. 注册临时 Mach service（用户域）──
echo "[smoke] Registering temporary Mach service: ${SERVICE_LABEL}"
cat > "${PLIST_PATH}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${SERVICE_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${SERVER_BIN}</string>
        <string>${SERVICE_LABEL}</string>
        <string>${TEAM_ID}</string>
        <string>${ALLOWED_SIGNING_ID}</string>
        <string>${RESULT_PATH}</string>
    </array>
    <key>MachServices</key>
    <dict>
        <key>${SERVICE_LABEL}</key>
        <true/>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>StandardOutPath</key>
    <string>${TMP_DIR}/server.out</string>
    <key>StandardErrorPath</key>
    <string>${TMP_DIR}/server.err</string>
</dict>
</plist>
EOF

launchctl bootstrap "gui/$(id -u)" "${PLIST_PATH}"

# 等待 server 打印 READY
echo "[smoke] Waiting for server READY..."
for i in $(seq 1 30); do
    if grep -q "READY ${SERVICE_LABEL}" "${TMP_DIR}/server.out" 2>/dev/null; then
        echo "[smoke] Server ready."
        break
    fi
    sleep 0.5
    if [[ $i -eq 30 ]]; then
        echo "[smoke] ERROR: Server did not become ready in time"
        cat "${TMP_DIR}/server.err" 2>/dev/null || true
        exit 2
    fi
done

# ── 4. 正向 smoke ──
echo "[smoke] Running POSITIVE smoke (Developer ID signed client)..."
"${CLIENT_BIN}" "${SERVICE_LABEL}" positive &
CLIENT_PID=$!
(
    sleep "${CLIENT_TIMEOUT_SEC}"
    kill -0 $CLIENT_PID 2>/dev/null && kill -9 $CLIENT_PID
) &
WAITER_PID=$!
CLIENT_EC=0
wait $CLIENT_PID || CLIENT_EC=$?
kill $WAITER_PID 2>/dev/null || true
wait $WAITER_PID 2>/dev/null || true

if [[ $CLIENT_EC -ne 0 ]]; then
    echo "[smoke] ERROR: Positive client exited with code $CLIENT_EC"
    cat "${TMP_DIR}/server.err" 2>/dev/null || true
    exit 2
fi
echo "[smoke] Positive smoke PASSED."

# 读取正向业务调用数
if [[ -f "${RESULT_PATH}" ]]; then
    POSITIVE_CALLS=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('businessCalls',0))" "${RESULT_PATH}")
    echo "[smoke] Business calls after positive: $POSITIVE_CALLS"
else
    echo "[smoke] ERROR: Result file not found after positive smoke"
    exit 2
fi

# ── 5. 负向签名（ad-hoc）──
echo "[smoke] Re-signing client ad-hoc for NEGATIVE smoke..."
codesign --force --sign - "${CLIENT_BIN}"
codesign -dv --verbose=4 "${CLIENT_BIN}" 2>&1 | grep -E 'Identifier|Authority'

# ── 6. 负向 smoke ──
echo "[smoke] Running NEGATIVE smoke (ad-hoc signed client)..."
"${CLIENT_BIN}" "${SERVICE_LABEL}" negative &
CLIENT_PID=$!
(
    sleep "${CLIENT_TIMEOUT_SEC}"
    kill -0 $CLIENT_PID 2>/dev/null && kill -9 $CLIENT_PID
) &
WAITER_PID=$!
CLIENT_EC=0
wait $CLIENT_PID || CLIENT_EC=$?
kill $WAITER_PID 2>/dev/null || true
wait $WAITER_PID 2>/dev/null || true

# 负向 client 期望退出码 3（libxpc 拒绝）
if [[ $CLIENT_EC -ne 3 ]]; then
    echo "[smoke] ERROR: Negative client expected exit code 3 (rejected), got $CLIENT_EC"
    cat "${TMP_DIR}/server.err" 2>/dev/null || true
    exit 2
fi
echo "[smoke] Negative smoke PASSED (client rejected as expected)."

# 读取负向后的业务调用数（必须没有新增）
if [[ -f "${RESULT_PATH}" ]]; then
    NEGATIVE_CALLS=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('businessCalls',0))" "${RESULT_PATH}")
    echo "[smoke] Business calls after negative: $NEGATIVE_CALLS"
else
    echo "[smoke] ERROR: Result file not found after negative smoke"
    exit 2
fi

if [[ "$NEGATIVE_CALLS" -ne "$POSITIVE_CALLS" ]]; then
    echo "[smoke] ERROR: Business calls changed after negative smoke ($POSITIVE_CALLS -> $NEGATIVE_CALLS)"
    exit 2
fi

echo "[smoke] ============================================================"
echo "[smoke] ALL SMOKES PASSED"
echo "[smoke]   - Positive (Developer ID): handshake + business OK, calls=$POSITIVE_CALLS"
echo "[smoke]   - Negative (ad-hoc): rejected before payload, calls unchanged=$NEGATIVE_CALLS"
echo "[smoke] ============================================================"
