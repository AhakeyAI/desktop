#!/bin/zsh

# 测试 hook 执行
echo "测试 preToolUse hook:"
echo '{"tool_name":"Read","name":"read"}' | "/Users/cjn/Desktop/keyboard1/ahakeyconfig/dist/AhaKey Studio.app/Contents/MacOS/ahakeyconfig-agent" hook preToolUse

echo "\n测试 beforeShellExecution hook:"
echo '{"command":"python3 /Users/cjn/Desktop/keyboard1/ahakeyconfig/helloworld.py"}' | "/Users/cjn/Desktop/keyboard1/ahakeyconfig/dist/AhaKey Studio.app/Contents/MacOS/ahakeyconfig-agent" hook beforeShellExecution

echo "\n测试 beforeMCPExecution hook:"
echo '{"command":"test command"}' | "/Users/cjn/Desktop/keyboard1/ahakeyconfig/dist/AhaKey Studio.app/Contents/MacOS/ahakeyconfig-agent" hook beforeMCPExecution
