# HIL-RELEASE-0.2.1 Gate-1 R2：覆盖安装 361→362 + 同 pid 两轮 BLE + Hook 灯效（2026-09-02 23:19–23:30 +08）

ACK Codex `07bc824` / Gate-0 R2 accepted。唯一候选 SHA-256 `aa27aef0597ebaf659fa1fd04ca58acdf432f1e18899008678f516e048be0d4a`，产品源 `1ed560b`（V021 SIGPIPE R3），版本 **0.2.1 (362)**。未改业务代码、未刷机、未 EEPROM 擦除、未 push、未上传渠道、未 reboot/logout、未删除用户配置、未 `launchctl kickstart`。未重做 Hook 自动/手动/离线三态。未测 OLED / `0x97 status=3` / 断电保持 / C1。Studio GUI 全程 **ABSENT**。

安装入口：HIL CLI `hil-release-install` 编译自 worktree `/tmp/ahakey-hil-release-021-1ed560b`（`AhaKeyReleaseInstaller.run` + `allowSystemMutation: true`）。登录项绑定 `/Applications/AhaKey Studio.app`。候选从公证 DMG 拷到 `$TMPDIR/ahakey-gate1-362-candidate/`，同级 `LaunchAgent.plist`。安装后删除该候选目录，避免 `open -a` 命中 App Translocation。未跑 `$AGENT --verify-runtime`。

## 安装前快照（零 mutation）

- 本机当时为 **0.2.1 (361)**（`AhaKeyGitCommit=0b4b5e1…`）。
- DMG SHA 重算匹配 `aa27aef0…e0d4a`（`sha_match=1`）。
- 唯一 Runtime owner：`lab.jawa.ahakeyconfig.agent` pid **51992** / `runs=1`；HIL print rc=113。
- 登录项已含 `/Applications/AhaKey Studio.app`。
- `~/.cursor/hooks.json` sha256 `f94297db…5de0e`；`ahatype.json` sha256 `a5cd44a0…4df971`。
- 回滚 zip（不入库）：`/tmp/ahakey-hil-gate1-362-rollback/AhaKey-Studio-pre-gate1-362.zip` sha256 `0a1139d1…4b77`。

原始：`raw/gate1-362-pre-snapshot.txt`、`raw/gate1-362-official-agent.plist`、`raw/gate1-362-hooks-pre.json`。

## 安装

入口 inspect：`signedIdentityMatches`。请求 `.upgrade`。

```
OUTCOME rolledBack=false failForward=false
app=true login=true owners=["lab.jawa.ahakeyconfig.agent"]
steps=[bootout(agent), installApp, writeLaunchAgent, enable(agent), bootstrap(agent), registerLoginItem, verifySingleOwner, removeBackup]
exit=0
```

原始：`raw/gate1-362-install.txt`。

## 即时验证

| 检查 | 结果 |
|---|---|
| 版本 | **0.2.1 (362)**，`AhaKeyGitCommit=1ed560bb5626048926eba499efe5394fd95304d3` |
| App / Agent 签名 | identifier `lab.jawa.ahakeyconfig`，Team `P2VFVRZK7P`，`--verify --strict` rc=0 |
| 唯一 Runtime owner | 仅 `lab.jawa.ahakeyconfig.agent` pid **65466** / `runs=1`；HIL print rc=113 |
| Mach | `lab.jawa.ahakeyconfig.runtime` active |
| LaunchAgent | Label exact，RunAtLoad=true，KeepAlive=true |
| 登录项 | `/Applications/AhaKey Studio.app` 已登记 |
| XPC | `RuntimeXPCSmokeClient lab.jawa.ahakeyconfig.runtime positive` handshake+snapshot `RESULT: ok` |
| `ahakey.sock` | `{"switchState":0,"lightMode":4}` 可读写 |
| `private/hook.sock` | connect OK |
| Studio GUI | ABSENT |
| Hook / ahatype | SHA 与安装前相同 |

原始：`raw/gate1-362-post-verify.txt`、`raw/gate1-362-xpc.txt`。

## BLE 两轮唤醒（Gate-1 R2 核心）

监控规则：空扫描 = `os_disconnected` **且** `switchState is null`（从不把缺失 BT 当断开）；T0 = OS Connected 观察时刻；pid 变化立即停止；不得 kickstart。系统蓝牙名本机显示为 **AhaKey 505C**（非历史 `AhaKey X1` 字符串）。冻结 pid0=**65466**。

### 第 1 轮

- 23:26:57.338 `EMPTY_SCAN_CONFIRMED`：status null，`os_disconnected`，pid **65466**
- 23:27:32.431 `T0_OS_CONNECTED` names=`AhaKey 505C`
- 23:27:33.739 `ROUND1_OK` **dt=1.321s** ≤2s；status `switchState=0`；`runs=1`；无 kickstart

### 第 2 轮

第 1 轮通过后约 1.7s，OS 再次 `os_disconnected` 且 status null（真实空扫描，不是 profiler 缺失）。

- 23:27:35.475 `EMPTY_SCAN_CONFIRMED_R2`，pid 仍 **65466**
- 23:28:17.377 `T0_OS_CONNECTED` names=`AhaKey 505C`
- 23:28:18.558 `ROUND2_OK` **dt=1.249s** ≤2s；status `switchState=0`；`runs=1`
- 23:28:18.565 `BOTH_ROUNDS_OK`

跨两轮 PID **不变**（65466→65466），`runs=1`。无人工 kickstart，无 KeepAlive 拉起。

原始：`raw/gate1-362-ble-wake-monitor.txt`。

## 两轮后 Runtime / XPC / 防休眠

23:28:51 复查：pid **65466** / `runs=1`；HIL rc=113；Studio ABSENT；XPC `RESULT: ok`；`ahakey.sock` / `hook.sock` 均可；`pmset` Agent 持有 `PreventUserIdleSystemSleep`（`AhaKey Studio: Preventing idle sleep during coding tasks`）；键盘仍 Connected `AhaKey 505C`。

原始：`raw/gate1-362-post-ble.txt`。

## Studio 关闭下真实 Hook → 灯效

本会话真实 Cursor **Write** 与 **StrReplace**（`raw/gate1-362-hook-light-marker.txt`）。Studio GUI ABSENT。pid 仍 **65466**。agent 日志：

- `15:29:18Z` / `15:29:34Z` / `15:29:56Z`–`15:29:57Z`：`→ LED 状态 2: AA BB 90 02 CC DD` 与 `← 固件已应用 LED/OLED 状态命令 0x90`

未重做 Hook 三态探针。

原始：`raw/gate1-362-hook-light.txt`、`raw/gate1-362-hook-light-log.txt`。

## 未做

reboot/logout、刷固件、EEPROM 擦除、push、上传发布渠道、删除用户配置、kickstart、`--verify-runtime`、Studio GUI、Hook 三态重测、OLED/`0x97`/断电保持/C1。
