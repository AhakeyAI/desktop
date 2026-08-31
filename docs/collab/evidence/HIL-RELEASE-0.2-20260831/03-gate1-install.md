# HIL-RELEASE-0.2 Gate-1：安装尝试与 rollbackFailed（2026-08-31 12:29–12:37 +08）

源码产品钉 `3b287beecf34c3f2d433631610f8e8c8f85c9149`。唯一允许候选 SHA-256 `0c3ec9a6f5031e2497be786d32a4d5ba4d02bd474e5b7e124f04201b92f33618`。未改业务代码、未重启、未卸载演练、未刷机、未 push。回滚异常后按调度停手，未再 mutation。

## 安装前快照（零 mutation）

- DMG SHA 重算匹配。
- `/Applications/AhaKey Studio.app`：0.1.0 (70)，密封已坏（与 Gate-0 相同）。
- 正式 plist sha256 `61da75e0ece09f3bf422770aa707b7cb99af865ff4d004e2b1e1da9d84055804`。
- HIL plist sha256 `bb8df32368e672103e1632b74fbf14d36124eeaef5b61f77ac7709003f6ed923`。
- 已加载 owner 仅 `lab.jawa.ahakeyconfig.agent.hil`（未运行，Mach `lab.jawa.ahakeyconfig.runtime` managed/watching）。正式 label 未加载。
- System Events 登录项无 Studio。
- 蓝牙 On；AhaKey 515C / X1 / 507C 均 **Not Connected**。
- App zip 回滚副本：`/tmp/ahakey-hil-gate1-rollback/AhaKey-Studio-pre-gate1.zip` sha256 `4518d47e33d3648ed17a1ad77e4d92eeca5459d03b76982128e2fbaace91844c`（不入库）。

原始：`raw/gate1-pre-snapshot.txt`、`raw/gate1-official-agent.plist`、`raw/gate1-hil-agent.plist`。

## 安装入口

生产 `AhaKeyReleaseInstaller.run` + `AhaKeyReleaseMacInstallHost` + `AhaKeyReleaseLaunchdControl(allowSystemMutation: true)`。HIL CLI 不走 `SMAppService.mainApp`（那会登记 CLI 自身）：登录项读写绑定 `/Applications/AhaKey Studio.app` 的 System Events login item。候选经只读挂载拷到 `FileManager.temporaryDirectory`（生产 `candidateAllowedRoots`）并保留同级 `LaunchAgent.plist`。

入口 inspect：`signedIdentityMatches`。PRE：`app=true login=false owners=[lab.jawa.ahakeyconfig.agent.hil]`。请求 `.upgrade`。

## 失败

```
INSTALL_ERROR: rollbackFailed("rejected(...identityRejected(...appIntegrityFailed))")
exit=1
```

引擎在 rollback 失败时丢弃原始 apply 错误，只回传 rollback 原因。备份树 0.1.0 密封已坏，`restoreApp` → `replaceDirectoryAtomically` → `verifyStagedApp` 对旧树 `codesign --verify --strict` 失败。

## 停手时系统状态（只读）

| 对象 | 状态 |
|---|---|
| `/Applications/AhaKey Studio.app` | **0.2.0 (323)**，Developer ID，`--verify --strict` 通过；exe SHA 与候选相同 |
| `/Applications/AhaKey Studio.app.ahakey-backup` | 仍在；0.1.0 (70)，密封仍坏 |
| 正式 plist | **已写成新 bytes**（含 MachServices / 正式 ProgramArguments）；sha ≠ 安装前 |
| HIL plist | 未改（仍 `bb8df323…6ed923`） |
| launchd | **零 owner**：official 与 HIL `print` 均为 not found |
| 登录项 | 未增加 Studio |
| Agent 日志 | `~/Library/Logs/ahakeyconfig-agent.log` 不存在（bootstrap 很可能未成功落盘） |

未打开 Studio，未跑 XPC/BLE smoke。旧 DMG SHA `4426b3c9…ce793b` 未使用。

## 结论

Gate-1 **未完成**。覆盖升级发生了 App 切换与正式 plist 写入，但终态校验/后续步骤失败后补偿无法恢复密封已坏的 0.1.0，留下新 App + 旧 backup + 新正式 plist + 零 Runtime owner。属调度所述 **回滚异常 / P0**，立即停手提审。

不在本卡改安装器。未授权前不手动删 backup、不 bootstrap、不回灌 zip、不卸载。

原始：`raw/gate1-install.txt`、`raw/gate1-post-failure.txt`。
