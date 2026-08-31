# HIL-RELEASE-0.2 Gate-1：最终候选安装 + immediate smoke（2026-08-31 21:49–21:54 +08）

用户授权使用唯一候选 SHA-256 `9736c31c81070967875f2021f31b14e7d17bc2248f5916d55f6e245ec336ac26`。产品钉 `5c4f440a779452dd00282cd35fe915e2642678f0`。未改业务代码、未卸载、未登出/重启、未故障注入、未回滚演练、未刷机、未 push。

安装入口：HIL CLI `hil-release-install` 编译自 clean worktree `/tmp/ahakey-hil-release-02-5c4f440/ahakeyconfig-mac`（R5 `AhaKeyReleaseInstaller.run` + `AhaKeyReleaseMacInstallHost` + `allowSystemMutation: true`）。登录项读写绑定 `/Applications/AhaKey Studio.app`，不走 CLI 自身 `SMAppService.mainApp`。候选经只读挂载拷到 `FileManager.temporaryDirectory` 并保留同级 `LaunchAgent.plist`。

## 安装前快照（零 mutation）

- DMG SHA 重算匹配 `9736c31c…6ac26`。
- `/Applications/AhaKey Studio.app`：0.2.0 (323)，Developer ID，`--verify --strict` rc=0（fail-forward 现场）。
- 正式 plist sha256 `231d3ca155ad9888b5b2876f539aada5e8605666b16270473c109236a95c50f5`。
- HIL plist sha256 `bb8df32368e672103e1632b74fbf14d36124eeaef5b61f77ac7709003f6ed923`（未加载，print rc=113）。
- 唯一 Runtime owner：`lab.jawa.ahakeyconfig.agent` pid=6602 running，disabled override = enabled。
- 登录项无 Studio。
- 蓝牙：AhaKey X1 `D4:6C:50:5C:F5:C0` Connected；515C / 507C Not Connected。
- App zip：`/tmp/ahakey-hil-gate1-359-rollback/AhaKey-Studio-pre-gate1-359.zip` sha256 `3d3e7cca54ea8a6c73c97db1d1644436ef8ad0a8f3adb298945bb486f4e47155`（不入库）。
- 上次 Gate-1 残留 `/Applications/AhaKey Studio.app.ahakey-backup`（0.1.0 密封已坏）。R5 `replaceDirectoryAtomically` 在该路径存在时会 `backupAlreadyExists`。快照后将其 **搬到** `/tmp/ahakey-hil-gate1-359-rollback/AhaKey-Studio.app.ahakey-backup-leftover-0.1.0`（保留，未删除），以便安装器为当前可恢复的 323 App 建新 backup。

原始：`raw/gate1-359-pre-snapshot.txt`、`raw/gate1-359-pre-mutation.txt`、`raw/gate1-359-official-agent.plist`、`raw/gate1-359-hil-agent.plist`。

## 安装

入口 inspect：`signedIdentityMatches`。PRE：`app=true login=false owners=[lab.jawa.ahakeyconfig.agent]`。请求 `.upgrade`。

```
OUTCOME rolledBack=false app=true login=true owners=["lab.jawa.ahakeyconfig.agent"]
steps=[bootout(agent), installApp, writeLaunchAgent, enable(agent), bootstrap(agent), registerLoginItem, verifySingleOwner, removeBackup]
exit=0
```

## 即时验证

| 检查 | 结果 |
|---|---|
| 版本 | **0.2.0 (359)** |
| App / Agent 签名 | identifier `lab.jawa.ahakeyconfig`，Team `P2VFVRZK7P`，`--verify --strict` rc=0 |
| 唯一 Runtime owner | 仅 `lab.jawa.ahakeyconfig.agent` pid=72067 running；HIL print rc=113 |
| Mach | `lab.jawa.ahakeyconfig.runtime` active |
| 登录项 | `/Applications/AhaKey Studio.app` 已登记 |
| `.ahakey-backup` / staging | 成功路径已删除（`removeBackup`） |
| XPC | 生产 `RuntimeXPCSmokeClient` handshake+snapshot `RESULT: ok`，exit 0 |
| Studio | 进程 `AhaKeyConfig` pid=72303；窗口可见 |
| BLE | Studio 显示 **AhaKey X1 Connected / 54%**；系统蓝牙 X1 `D4:6C:50:5C:F5:C0` VID `0x07D7` Connected |

Studio GUI 的 `application.lab.jawa.ahakeyconfig.*` launchd 项是前台 App，不是第二 Runtime Agent owner。

截图留在 `raw/gate1-359-studio-window.png`（约 2.7MB，不入库）。未卸载、未登出/重启、未故障注入、未回滚演练。

## 结论

Gate-1 **完成**：R5 生产安装器对最终候选覆盖升级成功；版本/签名、唯一 Runtime owner、XPC、Studio、BLE 基本连接均通过。停手提审，等 Codex 验收后再申请登出/重启或卸载窗口。
