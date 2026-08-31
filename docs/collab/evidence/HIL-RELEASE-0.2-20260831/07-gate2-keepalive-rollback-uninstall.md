# HIL-RELEASE-0.2 Gate-2：保活 / 故障回滚 / 卸载演练（2026-08-31 22:08–22:15 +08）

用户授权：登出/重启保活、卸载、故障注入、自动回滚演练。Gate-1 accepted @ `eef125d`。唯一候选仍为 SHA-256 `9736c31c81070967875f2021f31b14e7d17bc2248f5916d55f6e245ec336ac26` / 产品钉 `5c4f440` / 0.2.0 (359)。未改业务代码、未刷机、未跑 HIL-CONFIG C1–C6、未 push、未从本会话执行 `reboot`/`shutdown`/`logout`。

安装入口与 Gate-1 相同：HIL CLI `hil-release-install`（R5 `AhaKeyReleaseInstaller.run` + `AhaKeyReleaseMacInstallHost` + `allowSystemMutation: true`；登录项绑定 `/Applications/AhaKey Studio.app`）。候选仍在 `FileManager.temporaryDirectory` 同级 `LaunchAgent.plist`。CLI 本轮仅扩展子命令 `upgrade --inject writeLaunchAgent` 与 `uninstall`，不改产品树。

## 1. Studio 退出 + Agent KeepAlive

AppleScript `quit` 返回用户取消 `-128`（未关窗）。改为 SIGTERM Studio GUI pid=75352；Agent 保持运行。

| 检查 | 结果 |
|---|---|
| Studio GUI | 退出后无 `AhaKeyConfig` 进程 |
| Agent 在 GUI 退出后 | pid=72067 仍 running；HIL print rc=113 |
| XPC（GUI 退出后） | handshake+snapshot `RESULT: ok`，exit 0 |
| pmset | Agent 继续持有 `PreventUserIdleSystemSleep`（“AhaKey Studio: Preventing idle sleep during coding tasks”） |
| KeepAlive | `kill` Agent 72067 后 launchd 在 ~0.5s 拉起 pid=76149 |
| XPC（KeepAlive 后） | `RESULT: ok`，exit 0 |
| 唯一 Runtime owner | 仅 `lab.jawa.ahakeyconfig.agent` |

原始：`raw/gate2-keepalive.txt`。359 App zip（不入库）：`/tmp/ahakey-hil-gate2-rollback/AhaKey-Studio-359-pre-gate2.zip` sha256 `9c511dae276138867f7de8739928bd2d31c27e0d4245ec23fc6c732bc8b4fa07`。

## 2. 故障注入 + 自动回滚

对同一 359 候选执行 `upgrade --inject writeLaunchAgent`。当前 App 为可恢复的 verified 359（非 fail-forward）。

```
PRE: app=true login=true owners=["lab.jawa.ahakeyconfig.agent"]
INSPECT: signedIdentityMatches
OUTCOME rolledBack=true failForward=false app=true login=true owners=["lab.jawa.ahakeyconfig.agent"]
original=injectedFailure(writeLaunchAgent)
steps=[bootout(agent), installApp, writeLaunchAgent]
inject_cli_rc=0
```

| 检查 | 结果 |
|---|---|
| 版本 | 仍为 **0.2.0 (359)** |
| App / Agent 签名 | identifier `lab.jawa.ahakeyconfig`，Team `P2VFVRZK7P`，`--verify --strict` rc=0 |
| 唯一 Runtime owner | `lab.jawa.ahakeyconfig.agent` pid=76870；HIL rc=113 |
| XPC | `RESULT: ok`，exit 0 |
| 登录项 | `/Applications/AhaKey Studio.app` 仍在 |
| `.ahakey-backup` / staging | 回滚后不存在 |

原始：`raw/gate2-inject-rollback.txt`。

## 3. 卸载 + 同一 SHA 重装

### 卸载

```
PRE: app=true login=true owners=["lab.jawa.ahakeyconfig.agent"]
OUTCOME rolledBack=false failForward=false app=false login=false owners=[]
steps=[bootout(agent), unregisterLoginItem, removeLaunchAgent, removeApp, verifyCleanUninstall, removeBackup]
uninstall_cli_rc=0
```

| 检查 | 结果 |
|---|---|
| App | `/Applications/AhaKey Studio.app` 不存在 |
| 官方 / HIL plist | 均不存在；print rc=113 / 113 |
| launchd | 无 `ahakey`/`jawa` 条目 |
| 登录项 | Studio 已移除；第三方 Typeless / QoderWork / BaiduNetdisk 保留 |
| 用户配置目录 | `~/Library/Application Support/AhaKeyConfig` 保留 |
| 用户身份 JSON | `ahatype.json` / `device-identity.json` 字节不变 |
| Hook 文件 | `.claude/settings.json`、`.cursor/hooks.json`、`.codex/config.toml`、`.kimi/config.toml` 字节不变 |
| staging / `.ahakey-backup` | 不存在 |

卸载期间仅 `diagnostics/power-protection.log` 校验和变化（Agent bootout 写日志），不是配置目录被删。

### 重装

请求因 `app=false` 走 `.install`（同一候选路径）：

```
PRE: app=false login=false owners=[]
INSPECT: signedIdentityMatches
OUTCOME rolledBack=false failForward=false app=true login=true owners=["lab.jawa.ahakeyconfig.agent"]
steps=[installApp, writeLaunchAgent, enable(agent), bootstrap(agent), registerLoginItem, verifySingleOwner]
```

| 检查 | 结果 |
|---|---|
| 版本 | **0.2.0 (359)** |
| App / Agent 签名 | identifier/Team 同上，strict rc=0 |
| 唯一 Runtime owner | pid=77220 running；HIL rc=113 |
| XPC | `RESULT: ok`，exit 0 |
| 登录项 | Studio 已重新登记 |
| plist | `KeepAlive=true` `RunAtLoad=true`；sha256 `231d3ca155ad9888b5b2876f539aada5e8605666b16270473c109236a95c50f5` |

`current-ide-state.json` 在 Agent bootstrap 后被运行时改写，属预期；身份 JSON 与 hook 文件仍与卸载前一致。

原始：`raw/gate2-uninstall-reinstall.txt`、`raw/gate2-official-agent.plist`、`raw/gate2-official-print-post.txt`。

## 4. 登出/重启保活 — 仅 PRE

本会话**没有**执行整机 logout/reboot（会打断 Cursor 与桌面）。PRE 快照：

- 0.2.0 (359)；App/Agent strict 签名通过。
- 唯一 owner pid=77220；HIL rc=113。
- 官方 plist `KeepAlive` + `RunAtLoad` 均为 true。
- 登录项已登记 Studio。
- Agent 持有防休眠断言。
- 系统蓝牙 AhaKey X1 `D4:6C:50:5C:F5:C0` VID `0x07D7` 仍在设备列表（BLE）。
- 无 `.ahakey-backup` / staging。`/Applications/AhaKey Studio.app.backup-20260510-micfix` 是 2026-05-10 用户旧树，不是安装器 residual，未触碰。

POST（重启后唯一 owner / XPC / 登录项 / RunAtLoad）需用户重启后再采集。原始：`raw/gate2-reboot-pre.txt`。

## 结论

Gate-2 **同会话范围完成**：Studio 退出后 Agent 保活与 KeepAlive 拉起、`writeLaunchAgent` 故障注入自动回滚到 359、生产卸载干净且用户配置保留、同一 SHA 重装恢复唯一 owner 与 XPC。整机登出/重启保活只完成 PRE，**不宣称重启后保活已验收**。未刷机、未跑 HIL-CONFIG、未 push。
