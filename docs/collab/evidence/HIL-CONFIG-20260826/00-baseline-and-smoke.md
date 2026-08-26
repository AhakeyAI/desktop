# HIL-CONFIG 2026-08-26 — 基线与 XPC smoke 证据

## 基线
- commit: b7798ba（WBS-5.6 accepted 基线 19eb4dc + 文档/注释后续）
- agent 构建: ahakeyconfig-mac/.build/release/ahakeyconfig-agent
  sha256: 030956ae7cb8c349995f8696f6d06bae978c1170982a20498044e5b705a8ed29
- 临时 launchd: lab.jawa.ahakeyconfig.agent.hil（~/Library/LaunchAgents/lab.jawa.ahakeyconfig.agent.hil.plist）
- 原状记录：正式 lab.jawa.ahakeyconfig.agent 在运行（无 MachServices 键），未被停止或修改。

## launchd 登记验证
- launchctl print 显示 endpoints: lab.jawa.ahakeyconfig.runtime { active=1, managed=1 }
- agent PID 14388 运行中，日志 agent-hil.log。

## XPC smoke（真实双进程，生产签名要求）
- 负向（adhoc 签名 client）：RESULT: rejected，exit=3 —— libxpc 在 payload 处理前拒绝，符合 WBS-5.2 设计。
- 正向（Developer ID P2VFVRZK7P + identifier lab.jawa.ahakeyconfig 签名 client）：
  HANDSHAKE ok，runtime=0.1.0(development)，interface=1.1，schema=[3]，
  capabilities=[configuration, diagnostics, snapshot]，RESULT: ok，exit=0。
