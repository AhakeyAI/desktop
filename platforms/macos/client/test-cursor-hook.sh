#!/bin/zsh

# 模拟 Cursor 实际调用 hook 的方式
echo "模拟 Cursor 调用 beforeShellExecution hook:"

# 模拟 Cursor 实际发送的 JSON 格式
cat > cursor-request.json << 'EOF'
{
  "command": "python3 /Users/cjn/Desktop/keyboard1/ahakeyconfig/helloworld.py",
  "cwd": "/Users/cjn/Desktop/keyboard1/ahakeyconfig",
  "env": {}
}
EOF

# 测试 hook 响应
cat cursor-request.json | "/Users/cjn/Desktop/keyboard1/ahakeyconfig/dist/AhaKey Studio.app/Contents/MacOS/ahakeyconfig-agent" hook beforeShellExecution

echo "\n测试完成"
rm cursor-request.json
