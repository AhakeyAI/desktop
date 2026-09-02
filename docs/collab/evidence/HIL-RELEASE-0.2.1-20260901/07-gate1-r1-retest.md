# HIL-RELEASE-0.2.1 Gate-1 R1 最小复验（2026-09-02 20:03–20:07 +08）

ACK Codex `a953dad` / `lastReviewedCommit=9ec2b09`。Hook 三态不重做。未改业务代码、未重打 DMG、未 kickstart、未 reboot/刷机/push。Studio GUI 全程 ABSENT。

## 1. official bootout/bootstrap 恢复 `ahakey.sock` — 通过

污染前：pid **89889** / `runs=2`；路径 `ahakey.sock` `Connection refused`；`private/hook.sock` 可连；Studio ABSENT。

```
launchctl bootout gui/501/lab.jawa.ahakeyconfig.agent   # rc=0；随后 print rc=113
rm stale ahakey.sock path leftover from --verify-runtime
launchctl bootstrap gui/501 ~/Library/LaunchAgents/lab.jawa.ahakeyconfig.agent.plist  # rc=0
```

恢复后：pid **9292** / `runs=1`；唯一 official owner；HIL print rc=113；`ahakey.sock` `{"lightMode":0,"switchState":1}` 可读写；hook.sock OK；XPC `RESULT: ok`；pmset Agent 持有 `PreventUserIdleSystemSleep`。

原始：`raw/gate1-361-r2-socket-restore.txt`。

## 2. Studio 退出后真实 Hook → 灯效/固件 — 通过

本会话真实 Cursor **Write** 与 **StrReplace**（`raw/gate1-361-r2-hook-light.txt`）。pid 仍 9292。socket `{"switchState":1,"lightMode":5}`。agent 日志在 12:05:15Z 连续 `固件已应用 LED/OLED 状态命令 0x90` / `AA BB 90 02 CC DD`。

## 3. 两轮 BLE（OS Connected T0）— 按裁决停止

监控规则：空扫描 = `os_disconnected` **且** `switchState is null`（从不把缺失 BT 当断开）；T0 = OS Connected；pid 变化立即停止。键盘当时仍 Connected，尚未请用户关机。

20:06:20 监控启动，pid0=**9292**。20:06:40 **PID_CHANGED 9292→10220** `runs=2`。立即 `STOP_PID_CHANGED`，**没有**把 KeepAlive 后继当下一轮。

launchd unified log：

```
20:06:39.989 gui/501/lab.jawa.ahakeyconfig.agent [9292]: exited due to SIGPIPE | sent by ahakeyconfig-agent[9292], ran for 114694ms
20:06:40.007 Successfully spawned ahakeyconfig-agent[10220] because inefficient
```

`~/Library/Logs/DiagnosticReports` **没有**本日新 `.ips`（SIGPIPE 不会生成 crash report）。8 月 28 日旧 ips 与本事件无关。agent 日志在 KeepAlive 衔接处再次出现截断 UTF-8。

原始：`raw/gate1-361-r2-ble-wake.txt`、`raw/gate1-361-r2-pid-change/index.txt`、`raw/gate1-361-r2-pid-change/unified-ahakey.txt`、`raw/gate1-361-r2-pid-change/agent-log-tail.txt`。

## 结论

socket 恢复与 Studio-closed Hook→0x90 已取证。两轮 BLE **未开始**：测试 pid 在等待空扫描时因 **SIGPIPE** 被 KeepAlive 替换。按完成定义停止，不使用 pid 10220 续跑。未改代码、未重打 DMG、未重测 Hook 三态。

- 需要回复：是（@Codex 裁定 SIGPIPE/KeepAlive 是否阻断整卡，以及是否另开产品修复）
