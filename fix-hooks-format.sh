#!/bin/zsh

# 修复 hooks.json 格式为正确的对象格式
echo '{"version": 1, "hooks": {"preToolUse": {"command": "/Users/cjn/Desktop/keyboard1/ahakeyconfig/dist/AhaKey Studio.app/Contents/MacOS/ahakeyconfig-agent", "args": ["hook", "preToolUse"], "enableOnStartup": true}, "beforeShellExecution": {"command": "/Users/cjn/Desktop/keyboard1/ahakeyconfig/dist/AhaKey Studio.app/Contents/MacOS/ahakeyconfig-agent", "args": ["hook", "beforeShellExecution"], "enableOnStartup": true}, "beforeMCPExecution": {"command": "/Users/cjn/Desktop/keyboard1/ahakeyconfig/dist/AhaKey Studio.app/Contents/MacOS/ahakeyconfig-agent", "args": ["hook", "beforeMCPExecution"], "enableOnStartup": true}, "postToolUse": {"command": "/Users/cjn/Desktop/keyboard1/ahakeyconfig/dist/AhaKey Studio.app/Contents/MacOS/ahakeyconfig-agent", "args": ["hook", "postToolUse"], "enableOnStartup": true}, "sessionStart": {"command": "/Users/cjn/Desktop/keyboard1/ahakeyconfig/dist/AhaKey Studio.app/Contents/MacOS/ahakeyconfig-agent", "args": ["hook", "sessionStart"], "enableOnStartup": true}, "sessionEnd": {"command": "/Users/cjn/Desktop/keyboard1/ahakeyconfig/dist/AhaKey Studio.app/Contents/MacOS/ahakeyconfig-agent", "args": ["hook", "sessionEnd"], "enableOnStartup": true}, "stop": {"command": "/Users/cjn/Desktop/keyboard1/ahakeyconfig/dist/AhaKey Studio.app/Contents/MacOS/ahakeyconfig-agent", "args": ["hook", "stop"], "enableOnStartup": true}}}' > ~/.cursor/hooks.json

echo "已修复 hooks.json 格式"
cat ~/.cursor/hooks.json

# 创建诊断目录
mkdir -p ~/Library/Application Support/AhaKeyConfig/diagnostics

echo "\n测试 hook 执行："
echo '{"command":"python3 /Users/cjn/Desktop/keyboard1/ahakeyconfig/helloworld.py"}' | "/Users/cjn/Desktop/keyboard1/ahakeyconfig/dist/AhaKey Studio.app/Contents/MacOS/ahakeyconfig-agent" hook beforeShellExecution

# 检查日志文件
echo "\n检查诊断日志："
ls -la ~/Library/Application Support/AhaKeyConfig/diagnostics/
