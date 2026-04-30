#!/bin/zsh

# 备份原始配置
cp ~/.cursor/cli-config.json ~/.cursor/cli-config.json.bak

# 修改 approvalMode 为 prompt（会提示但使用 hook 结果）
sed -i '' 's/"approvalMode": "allowlist"/"approvalMode": "prompt"/g' ~/.cursor/cli-config.json

echo "已修改 approvalMode 为 prompt"
cat ~/.cursor/cli-config.json | grep -A 5 "approvalMode"
