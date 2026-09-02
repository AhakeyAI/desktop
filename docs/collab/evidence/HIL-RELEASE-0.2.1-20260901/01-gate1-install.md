# HIL-RELEASE-0.2.1 Gate-1：覆盖安装 + Runtime/XPC/Studio/BLE/Cursor Hook（2026-09-02 11:01–11:26 +08）

ACK Codex `41e16ff` / Gate-0 accepted。唯一候选 SHA-256 `9f109421531b196c9378abb2c0d2b1f5b52f62c902d6796ae37ee720610b46c3`，源 `1c024c5`，版本 **0.2.1 (360)**。未改业务代码、未刷机、未 push、未上传渠道、未 reboot/logout、未删除用户配置。未开始 `RELEASE-DMG-VERIFIER-CLEANUP`。

安装入口：HIL CLI `hil-release-install` 编译自 clean worktree `/tmp/ahakey-hil-release-021-1c024c5/ahakeyconfig-mac`（`AhaKeyReleaseInstaller.run` + `AhaKeyReleaseMacInstallHost` + `allowSystemMutation: true`）。登录项绑定 `/Applications/AhaKey Studio.app`。候选经只读挂载拷到 `FileManager.temporaryDirectory` 并保留同级 `LaunchAgent.plist`。

## 安装前快照（零 mutation）

- DMG SHA 重算匹配 `9f109421…046c3`。
- `/Applications/AhaKey Studio.app`：**0.2.0 (359)**，Developer ID `lab.jawa.ahakeyconfig` / Team `P2VFVRZK7P`，`--verify --strict` rc=0。
- 正式 plist sha256 `231d3ca155ad9888b5b2876f539aada5e8605666b16270473c109236a95c50f5`。HIL plist 已不存在（print rc=113）。
- 唯一 Runtime owner：`lab.jawa.ahakeyconfig.agent` pid=77220 running，disabled override = enabled。
- 登录项已含 `/Applications/AhaKey Studio.app`。
- 蓝牙：AhaKey X1 `D4:6C:50:5C:F5:C0` **Not Connected**（安装前现场）。515C / 507C Not Connected。
- 无 `.ahakey-backup` / staging / scratch。
- `~/.cursor/hooks.json` sha256 `f94297db…5de0e`（AhaKey `preToolUse` 指向 `/Applications/AhaKey Studio.app/.../ahakeyconfig-agent`，`failClosed: false`）。
- `ahatype.json` sha256 `a5cd44a0…4df971`。
- 回滚 zip：`/tmp/ahakey-hil-gate1-021-rollback/AhaKey-Studio-pre-gate1-021.zip` sha256 `86dfae2877ab1559a14225cdc861894b591864e5e36d607c6cdb66f54df2e8e2`（不入库）。

原始：`raw/gate1-021-pre-snapshot.txt`、`raw/gate1-021-official-agent.plist`、`raw/gate1-021-hooks-pre.json`。

## 安装

覆盖前退出当时的 359 Studio GUI（Agent KeepAlive 仍在）。入口 inspect：`signedIdentityMatches`。PRE：`app=true login=true owners=["lab.jawa.ahakeyconfig.agent"]`。请求 `.upgrade`。

```
OUTCOME rolledBack=false failForward=false app=true login=true owners=["lab.jawa.ahakeyconfig.agent"]
steps=[bootout(agent), installApp, writeLaunchAgent, enable(agent), bootstrap(agent), registerLoginItem, verifySingleOwner, removeBackup]
exit=0
```

## 即时验证

| 检查 | 结果 |
|---|---|
| 版本 | **0.2.1 (360)**，`AhaKeyGitCommit=1c024c5…` |
| App / Agent 签名 | identifier `lab.jawa.ahakeyconfig`，Team `P2VFVRZK7P`，`--verify --strict` rc=0 |
| 唯一 Runtime owner | 仅 `lab.jawa.ahakeyconfig.agent`（安装后 pid=48579，kickstart 后 pid=50849）running；HIL print rc=113 |
| Mach | `lab.jawa.ahakeyconfig.runtime` active |
| LaunchAgent | Label exact，RunAtLoad=true，KeepAlive=true，ProgramArguments 指向 `/Applications/.../ahakeyconfig-agent` |
| 登录项 | `/Applications/AhaKey Studio.app` 已登记 |
| `.ahakey-backup` / staging | 成功路径已删除（`removeBackup`） |
| XPC | 生产 `RuntimeXPCSmokeClient` handshake+snapshot `RESULT: ok`，exit 0（安装后与 Studio 退出后各一次） |
| 用户配置 / Hook 文件 | `ahatype.json` 与 `hooks.json` SHA 与安装前相同 |

## Studio / BLE / 灯效

安装时 X1 未在系统蓝牙 Connected。用户唤醒键盘后系统蓝牙显示 AhaKey X1 Connected（VID `0x07D7` / `D4:6C:50:5C:F5:C0`），但已于 11:05 扫描空列表的 Agent 未自动回收。HIL 对同一 official label 执行 `launchctl kickstart -k`（未改产品、未回滚）：

- `系统已连接: AhaKey X1` → 数据/命令/通知通道就绪
- `0x99` protocol v3 current，UUID 兜底身份 `4F3E`
- `status battery=51 light=5 switch=0`
- socket `{"switchState":0,"lightMode":5}`；`current-ide-state.json` 同步 `workMode=1`

随后只开 **一个** Studio：窗口显示 **AhaKey X1 已连接 / 51% / 自动批准**，Cursor 模式灯条点亮，既有键位（Key 1 录音等）仍在，未同步改动 0。截图 `raw/gate1-021-studio-window.png`（约 574KB，不入库）。

Studio 退出后：Agent pid=50849 仍 running；XPC `RESULT: ok`；socket 仍 `lightMode=5,switchState=0`；`pmset` 仅 Agent 持有 `PreventUserIdleSystemSleep`（`AhaKey Studio: Preventing idle sleep during coding tasks`）。

## Cursor Hook

| 场景 | 结果 |
|---|---|
| 断连 `switchState=null` 独立 `preToolUse` Write/Shell/StrReplace/Read | rc=0，stdout 空，**无** `permission: deny`；health `decision=unavailable` `hookVersion=cursor-0.2.1`（fail-open） |
| 畸形 stdin | rc=0，stdout 空 |
| 已连接 `switchState=0` 独立 `preToolUse` 同上四工具 | rc=0，stdout `{"permission":"allow"}`；health `decision=allow` `hookVersion=cursor-0.2.1` |
| 本会话真实 Cursor | Write / StrReplace / Read / Shell 均进入执行；`raw/gate1-021-cursor-tool-smoke.txt` `write_ok=1` `strreplace_ok=1` |
| 自动拨杆 vs 文件编辑 | 自动批准下四工具均为 allow，不是 deny；断连时也不 deny。未改 `hooks.json`。 |
| Studio 退出后 | 独立 Write 仍 `{"permission":"allow"}` |

`hooks.json` `failClosed: false` 未变。

## 结论

Gate-1 **完成**：唯一 SHA 覆盖升级成功；版本/签名/唯一 Runtime owner/XPC/login item/KeepAlive 通过；真机 X1 连接、51% 电量、自动批准拨杆与 lightMode=5 灯效同步通过；Cursor Write/Shell/StrReplace/Read 不被 `preToolUse` 误拦，离线 fail-open。停手提审。未卸载、未登出/重启、未故障注入、未刷机、未 push。
