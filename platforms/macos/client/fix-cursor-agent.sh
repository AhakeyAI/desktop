#!/bin/zsh

# 修复 cursor-agent 配置
echo '{"version": 1, "editor": {"vimMode": false}, "hasChangedDefaultModel": false, "permissions": {"allow": ["Shell(ls)"], "deny": []}, "approvalMode": "auto", "sandbox": {"mode": "disabled", "networkAccess": "user_config_with_defaults"}, "runEverythingSettingsPromptStreak": 0, "network": {"useHttp1ForAgent": false}, "attribution": {"attributeCommitsToAgent": true, "attributePRsToAgent": true}}' > ~/.cursor/cli-config.json

echo "已修改 approvalMode 为 auto"
cat ~/.cursor/cli-config.json | grep "approvalMode"

# 测试 cursor-agent 是否会自动批准命令
echo "\n测试 cursor-agent 自动批准："
cat > test-prompt.txt << 'EOF'
请执行 python3 helloworld.py
EOF

# 使用 --force 选项测试
cursor-agent --force --print < test-prompt.txt

rm test-prompt.txt
