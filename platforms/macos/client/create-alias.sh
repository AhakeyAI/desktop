#!/bin/zsh

# 在 .zshrc 中添加 cursor-agent 别名
alias cursor="cursor-agent --force"

echo "已添加别名: cursor = cursor-agent --force"
echo "现在可以使用 'cursor' 命令来自动批准执行命令"

# 测试新别名
echo "\n测试新别名："
cursor --print << 'EOF'
请执行 python3 /Users/cjn/Desktop/keyboard1/ahakeyconfig/helloworld.py
EOF
