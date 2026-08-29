# WBS 5.9A 安装 / 覆盖升级 / 卸载 / 回滚

入口是 `AhaKeyReleaseInstaller.run`；规划在 `AhaKeyReleaseInstallPlanner`，文件原子替换在 `AhaKeyReleaseMacInstallHost`。产品入口是 `AhaKeyReleaseInstaller.productionHost()` + `AhaKeyReleaseInstallLayout.production()`。本卡测试只用沙箱 layout 与 Recording 系统控制，不修改 `/Applications`、不写真实 LaunchAgents、不调用 `SMAppService.register`。`AhaKeyReleaseLaunchdControl` 默认 `allowSystemMutation=false`，供后续 HIL 打开。只读查询（`launchctl list` / `launchctl print gui/<uid>/<label>`、`SMAppService.mainApp.status`）不要求 mutation 开关。

## 支持范围

- 允许：macOS 13+（Darwin ≥ 22）。
- 拒绝：macOS 12 及更早。拒绝时零写零擦，不得半安装。
- 未授权系统突变时，生产 `/Applications` 布局必须被拒绝。
- 前态 owner 只能是正式 `lab.jawa.ahakeyconfig.agent` 与 HIL `lab.jawa.ahakeyconfig.agent.hil`。其它 `lab.jawa.ahakeyconfig.*` label、或已加载但磁盘上没有对应 plist，必须在任何 mutation 前 fail-closed（`ambiguousPreviousOwners`）。

## 原子安装 / 覆盖升级

1. 执行边界自行 `inspectCandidate`：App 与 Agent 分别 `codesign --verify --strict`；Bundle / Agent 二进制 / Mach / Signing / Agent Signing 必须非空精确匹配；App 与 Agent 签名种类必须一致。未签名候选必须是 ad-hoc 且两端都没有 Team ID；Developer ID 缺 Team/Signing 必须拒绝。不得跳过 inspect。
2. 记录实际旧 owner 集合、各自 plist bytes、login-item 状态和 App 是否存在。bootout 这些 owner。
3. Candidate 必须落在明确 allowed root 下，并从该 root 起检查整条父级链（含父目录 symlink）。所有复制、删除、写入、rename 输入都走 path guard。
4. 同卷 sibling staging 完整拷贝后：fsync 树，再对 staging 内 App/Agent 做与入口相同的完整性与签名校验，最后 `rename` / `replaceItemAt` 原子替换目标 `.app`。覆盖升级与回滚都不得 copy-over 到已有树。切换前后对关键目录 fsync。
5. 写入带 `MachServices = lab.jawa.ahakeyconfig.runtime` 的 LaunchAgent plist：同目录临时文件 fsync 后 `rename` 覆盖目标，不得先删除旧文件。
6. bootstrap 正式 label，注册 macOS 13+ 登录项（真实 `SMAppService.register` 仅存在于 LaunchdControl，本卡不打开）。
7. 成功后断言加载中的 ahakey label 只剩 `lab.jawa.ahakeyconfig.agent`，再删除备份。

失败则按 **mutation checkpoint** 补偿：尚未 `installApp`/`removeApp` 时不得删除或改动原 App 树。只有存在可信 backup 才从 backup 恢复。回滚必须恢复记录下来的实际旧 owner（含 HIL leftover）、对应 plist bytes、login-item 和 App 是否存在；不得固定拉起正式 Agent。任何补偿失败都返回 `rollbackFailed`，不得在恢复失败时声称 `rolledBack=true`。新鲜安装若已替换 App，则删除半份 App 与新 plist。

`launchctl` bootout/bootstrap 非零退出码必须抛错，不得忽略。

## 卸载

先把现有 App 原子搬到备份，再删正式 plist / 登录项。中途失败必须从备份恢复，并恢复卸载前记录的 owner 集合。成功后才删备份。

**必须保留：** `~/Library/Application Support/AhaKeyConfig` 以及第三方 Hook 文件（Claude/Cursor/Codex/Kimi）。卸载不得改这些文件。

## 路径安全

删除、复制、写入、rename 前做 canonical / allowed-root 校验；拒绝 symlink 穿透（含 candidate 父目录）、`source=destination`、backup/staging 预存在。`pack-unsigned-candidate.sh` 拒绝 `OUTPUT_DIR` 落在 `/Applications`（含 symlink 解析后）。

## 已知限制（5.9B / HIL）

- 本卡不实际 Developer ID 签名、不公证、不写登录项、不覆盖 `/Applications`。
- 不迁移历史 Keychain/TCC。
- 无 Windows 安装器。
- 真实干净安装、覆盖升级、登录重启由 `HIL-RELEASE-0.2` USER-GATE 执行。
