#!/bin/sh
# AhaKey LED 状态同步 hook 脚本
# 用法: ahakey-state.sh <state_number>
# 通过 Unix socket 通知 ahakeyconfig-agent 发送 LED 状态到键盘
#
# Claude Hook 事件 → state 映射:
#   Notification=0  PermissionRequest=1  PostToolUse=2
#   PreToolUse=3    SessionStart=4       Stop=5
#   TaskCompleted=6 UserPromptSubmit=7   SessionEnd=8

SOCKET="/tmp/ahakey.sock"
STATE="${1:-0}"

[ -S "$SOCKET" ] && echo "$STATE" | nc -U "$SOCKET" -w 1 2>/dev/null || true
