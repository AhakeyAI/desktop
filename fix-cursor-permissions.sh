#!/bin/zsh

# 修复 cursor-agent 权限配置
echo '{"version": 1, "editor": {"vimMode": false}, "hasChangedDefaultModel": false, "permissions": {"allow": ["Shell(ls)", "Shell(python3)"], "deny": []}, "approvalMode": "auto", "sandbox": {"mode": "disabled", "networkAccess": "user_config_with_defaults"}, "runEverythingSettingsPromptStreak": 0, "network": {"useHttp1ForAgent": false}, "attribution": {"attributeCommitsToAgent": true, "attributePRsToAgent": true}}' > ~/.cursor/cli-config.json

echo "已将 python3 添加到允许列表"
cat ~/.cursor/cli-config.json | grep -A 5 "permissions"

# 测试 cursor-agent 是否会自动批准 python3 命令
echo "\n测试 python3 自动批准："
cursor-agent --force --print << 'EOF'
请执行 python3 /Users/cjn/Desktop/keyboard1/ahakeyconfig/helloworld.py
EOF
