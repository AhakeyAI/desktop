# WBS 5.9A 安装 / 覆盖升级 / 卸载 / 回滚

入口是 `AhaKeyReleaseInstaller.run`；规划在 `AhaKeyReleaseInstallPlanner`，文件原子替换在 `AhaKeyReleaseMacInstallHost`。本卡测试只用沙箱 layout 与 Recording 系统控制，不修改 `/Applications`、不写真实 LaunchAgents、不调用 `SMAppService`。`AhaKeyReleaseLaunchdControl` 默认 `allowSystemMutation=false`，供后续 HIL 打开。

## 支持范围

- 允许：macOS 13+（Darwin ≥ 22）。
- 拒绝：macOS 12 及更早。拒绝时零写零擦，不得半安装。
- 未授权系统突变时，生产 `/Applications` 布局必须被拒绝。

## 原子安装 / 覆盖升级

1. 执行边界自行 `inspectCandidate`：Bundle / Agent / Mach / Signing 必须非空精确匹配；未签名候选必须是 ad-hoc，Developer ID 缺 Team/Signing 必须拒绝。不得跳过 inspect。
2. bootout 全部 `lab.jawa.ahakeyconfig.*` 竞争 owner（含 HIL leftover）。
3. 同卷 sibling staging 完整拷贝并校验后，再 `rename` / `replaceItemAt` 原子替换目标 `.app`。覆盖升级与回滚都不得 copy-over 到已有树。
4. 写入带 `MachServices = lab.jawa.ahakeyconfig.runtime` 的 LaunchAgent plist（原子写）。
5. bootstrap 正式 label，注册 macOS 13+ 登录项（真实 `SMAppService` 仅存在于 LaunchdControl，本卡不打开）。
6. 断言加载中的 ahakey label 只剩 `lab.jawa.ahakeyconfig.agent`。
7. 成功后删除备份。

失败则**必须真正恢复**：旧 App、旧 plist、旧 login item 与正式 owner。任何补偿失败都返回 `rollbackFailed`，不得在恢复失败时声称 `rolledBack=true`。新鲜安装失败则删除半份 App 与新 plist。回滚后仍验证单 owner（升级恢复正式 Agent；新鲜安装为零 owner）。不重新拉起 HIL leftover。

## 卸载

先把现有 App 原子搬到备份，再删 plist / 登录项。中途失败必须从备份恢复。成功后才删备份。

**必须保留：** `~/Library/Application Support/AhaKeyConfig` 以及第三方 Hook 文件（Claude/Cursor/Codex/Kimi）。卸载不得改这些文件。

## 路径安全

删除、复制、rename 前做 canonical / allowed-root 校验；拒绝 symlink 穿透、`source=destination`、backup/staging 预存在。`pack-unsigned-candidate.sh` 拒绝 `OUTPUT_DIR` 落在 `/Applications`（含 symlink 解析后）。

## 已知限制（5.9B / HIL）

- 本卡不实际 Developer ID 签名、不公证、不写登录项、不覆盖 `/Applications`。
- 不迁移历史 Keychain/TCC。
- 无 Windows 安装器。
- 真实干净安装、覆盖升级、登录重启由 `HIL-RELEASE-0.2` USER-GATE 执行。
