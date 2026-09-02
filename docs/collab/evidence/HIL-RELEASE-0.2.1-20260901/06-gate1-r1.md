# HIL-RELEASE-0.2.1 Gate-1 R1：覆盖安装 + BLE 两轮唤醒 + Hook 三态四工具（2026-09-02 19:31–19:51 +08）

ACK Codex `f59c7e1` / Gate-0 R1 accepted。唯一候选 SHA-256 `4662ce93dd6dfa55e7964a5db9749ab3e7e82813a9616b114c1032ce3bbe1f0d`，产品源 `0b4b5e1`（V021 `88e02aa` + verifier cleanup），版本 **0.2.1 (361)**。未改业务代码、未刷机、未 push、未上传渠道、未 reboot/logout、未删除用户配置、未 `launchctl kickstart`。未测 OLED / `0x97 status=3` / 断电保持 / C1。

安装入口：HIL CLI `hil-release-install` 编译自 worktree `/tmp/ahakey-hil-release-021-0b4b5e1`（`AhaKeyReleaseInstaller.run` + `allowSystemMutation: true`）。登录项绑定 `/Applications/AhaKey Studio.app`。候选从公证 DMG 拷到 `$TMPDIR/ahakey-gate1-361-candidate/`，同级 `LaunchAgent.plist`。

## 安装前快照（零 mutation）

- 本机当时为 **0.2.1 (360)** 调试基线（SHA `9f109421…610b46c3`，无 V021 wake）。
- 唯一 Runtime owner：`lab.jawa.ahakeyconfig.agent` pid **50849**；HIL print rc=113。
- 登录项已含 `/Applications/AhaKey Studio.app`。
- `~/.cursor/hooks.json` sha256 `f94297db…5de0e`；`ahatype.json` sha256 `a5cd44a0…4df971`。
- 回滚 zip（不入库）：`/tmp/ahakey-hil-gate1-361-rollback/AhaKey-Studio-pre-gate1-361.zip` sha256 `63f27628…9d1b`。

原始：`raw/gate1-361-pre-snapshot.txt`、`raw/gate1-361-official-agent.plist`、`raw/gate1-361-hooks-pre.json`。

## 安装

入口 inspect：`signedIdentityMatches`。请求 `.upgrade`。

```
OUTCOME rolledBack=false failForward=false
steps=[bootout(agent), installApp, writeLaunchAgent, enable(agent), bootstrap(agent), registerLoginItem, verifySingleOwner, removeBackup]
exit=0
```

安装时键盘已在系统 Connected。新 agent pid **85410** 于 19:33:38 同秒出现 `蓝牙就绪` 与 `系统已连接`（安装 bootstrap，不是 kickstart）。

## 即时验证

| 检查 | 结果 |
|---|---|
| 版本 | **0.2.1 (361)**，`AhaKeyGitCommit=0b4b5e1…` |
| App / Agent 签名 | identifier `lab.jawa.ahakeyconfig`，Team `P2VFVRZK7P`，`--verify --strict` rc=0 |
| 唯一 Runtime owner | 仅 `lab.jawa.ahakeyconfig.agent`（安装后 pid=85410）running；HIL print rc=113 |
| Mach | `lab.jawa.ahakeyconfig.runtime` active |
| LaunchAgent | Label exact，RunAtLoad=true，KeepAlive=true |
| 登录项 | `/Applications/AhaKey Studio.app` 已登记 |
| XPC | `RuntimeXPCSmokeClient` handshake+snapshot `RESULT: ok` |
| Hook / ahatype | SHA 与安装前相同 |

原始：`raw/gate1-361-install.txt`、`raw/gate1-361-post-verify.txt`。

## BLE 两轮唤醒（Gate-1 R1 核心）

### 第 1 轮 — 现场监控 PASS

空扫描已确认（19:37:01 起，status null，OS disconnected）。用户开机后：

- 19:40:18 OS Connected，pid 仍 **85410**
- 19:40:19 Runtime `switchState=0`，**dt=1.025s** ≤2s
- 无 kickstart

原始：`raw/gate1-361-ble-wake-monitor.txt`。

### KeepAlive 重启（须披露，不是 kickstart）

约 19:40:27 agent 在写日志中途崩溃；launchd KeepAlive 拉起 pid **89889**，`runs=2`。日志在 `ahakeyconfig-agent.log` 约 30832 行处有 UTF-8 拼接。监控随后把 `bt=None` 当成空扫描并打出 `ROUND2_OK`：**作废**（PID 已变，且当时 OS 仍 Connected）。

### 第 2 轮 — 用户关机再开机；日志重建 PASS

独立空扫描：19:41:04 pid **89889**，status null，`os_disconnected`。用户于 ~19:42 开机：

- 11:41:01Z `连接断开` / `已断开，4s 后重连`
- 11:41:06Z `直连已知设备`
- **11:42:02Z `已连接: AhaKey X1`**
- 11:42:03Z `status battery=21 light=0 switch=0`

同秒对上用户「我现在开机了」。本轮走已知设备直连，**没有** `系统已连接` 行。pid 保持 **89889**，`runs=2`，无 kickstart。迟到的 live monitor（19:42:05 已 Connected）不能当 T0，已中止。

跨两轮 PID **不是**不变（85410→89889，KeepAlive）。**每轮内部 PID 稳定**。无人工 kickstart。

原始：`raw/gate1-361-ble-wake-round2-reconstruct.txt`；作废 live `ROUND2_OK` 见 `raw/gate1-361-ble-wake-monitor.txt`。

## Studio

`open -a "AhaKey Studio"` 曾打到 `$TMPDIR` 安装候选的 App Translocation 副本，不是 `/Applications`。已杀掉 translocated 进程、删除候选目录，再用绝对路径启动：

`/Applications/AhaKey Studio.app/Contents/MacOS/AhaKeyConfig` pid **92191**，agent 仍 89889。

Studio GUI 在手动档验证前已退出。截图 `raw/gate1-361-studio-window.png` 误摄到 Cursor 桌面而非 Studio 窗口，**不入库、不作 GUI 判据**。

## Cursor Hook

| 场景 | 独立 `preToolUse` Write/Shell/StrReplace/Read | 本会话真实 Cursor |
|---|---|---|
| `switchState=0` 自动 | rc=0，stdout `{"permission":"allow"}`；health `decision=allow` | Write/StrReplace/Read/Shell 均执行；`raw/gate1-361-cursor-tool-smoke.txt` `write_ok=1` `shell_ok=1 19:35:43` |
| 断连 `switchState=null` | rc=0，stdout 空，无 deny；health `decision=unavailable` | 离线 Shell `offline_shell_ok=1 19:37:47` |
| `switchState=1` 手动 | rc=0，stdout 空，`allow=0` `deny=0`；health `decision=defer_to_native` | 同文件 `manual_write_ok=1` / `manual_strreplace_ok=1` / `manual_read_ok=1` / `manual_shell_ok=1 19:50:46`；无 hook deny（Cursor 原生批准可出现） |

手动态 socket 快照（探针前 19:47:53）：`{"lightMode":5,"switchState":1}`，pid 89889。`current-ide-state.json` 仍 `switchState=1`。

`hooks.json` / `ahatype.json` SHA 未变。探针不是「真实 IDE」；真实四工具只计本会话 Cursor 工具调用。

原始：`raw/gate1-361-hook-probe-auto.txt`、`raw/gate1-361-hook-probe-offline.txt`、`raw/gate1-361-hook-probe-manual.txt`、`raw/gate1-361-cursor-tool-smoke.txt`。

## Studio 退出后 Runtime 续跑

GUI **ABSENT**。Agent pid **89889** `runs=2` 仍 running；唯一 owner；XPC `RESULT: ok`；`pmset` Agent 持有 `PreventUserIdleSystemSleep`（`AhaKey Studio: Preventing idle sleep during coding tasks`）；`private/hook.sock` 可连；登录项仍指向 `/Applications/AhaKey Studio.app`。

**测试污染（须披露）**：手动探针前误跑 `$AGENT --verify-runtime`，该进程挂起并替换了 `ahakey.sock` 路径 inode。杀掉后路径 `connect` 返回 Connection refused；89889 仍持旧 unix fd。未 kickstart、未重启 agent。状态改读 XPC + `current-ide-state.json` + hook.sock。灯效由拨杆/固件确认路径继续（手动态 `switchState=1`）。

原始：`raw/gate1-361-studio-exit.txt`。

## 结论

Gate-1 R1 **完成、停手提审**：唯一 SHA `4662ce93…` 覆盖安装 0.2.1 (361) 成功；签名/唯一 owner/XPC/login/KeepAlive 通过。两轮空扫描→唤醒均在 2s 内出现 Runtime 状态、无 kickstart；跨轮 PID 因 KeepAlive 崩溃从 85410 变为 89889，须 Codex 裁定是否仍满足「PID 不变」。Hook 自动 allow / 手动 defer_to_native / 离线 fail-open，且本会话真实四工具未被 `preToolUse` 误拦。Studio 退出后 Runtime/XPC/防休眠继续。unix `ahakey.sock` 路径在 `--verify-runtime` 污染后失效，不掩盖。

未卸载、未登出/重启、未刷机、未 push、未测 OLED/C1。
