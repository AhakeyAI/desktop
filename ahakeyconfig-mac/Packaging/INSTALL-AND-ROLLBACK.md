# WBS 5.9A 安装 / 覆盖升级 / 卸载 / 回滚

入口是 `AhaKeyReleaseInstaller.run`；规划在 `AhaKeyReleaseInstallPlanner`，文件原子替换在 `AhaKeyReleaseMacInstallHost`。产品入口是 `AhaKeyReleaseInstaller.productionHost()` + `AhaKeyReleaseInstallLayout.production()`。本卡测试只用沙箱 layout 与 Recording 系统控制，不修改 `/Applications`、不写真实 LaunchAgents、不调用 `SMAppService.register`。`AhaKeyReleaseLaunchdControl` 默认 `allowSystemMutation=false`，供后续 HIL 打开。只读查询（`launchctl list` / `launchctl print gui/<uid>/<label>`、`SMAppService.mainApp.status`）不要求 mutation 开关。

## 支持范围

- 允许：macOS 13+（Darwin ≥ 22）。
- 拒绝：macOS 12 及更早。拒绝时零写零擦，不得半安装。
- 未授权系统突变时，生产 `/Applications` 布局必须被拒绝。
- 前态 owner 只能是正式 `lab.jawa.ahakeyconfig.agent` 与 HIL `lab.jawa.ahakeyconfig.agent.hil`。其它 `lab.jawa.ahakeyconfig.*` label、或已加载但磁盘上没有对应 plist，必须在任何 mutation 前 fail-closed（`ambiguousPreviousOwners`）。

## 原子安装 / 覆盖升级

1. 执行边界自行 `inspectCandidate`：App 与 Agent 分别 `codesign --verify --strict`；Bundle / Agent 二进制 / Mach / Signing / Agent Signing 必须非空精确匹配；App 与 Agent 签名种类必须一致。未签名候选必须是 ad-hoc 且两端都没有 Team ID；Developer ID 缺 Team/Signing 必须拒绝。不得跳过 inspect。
2. 记录实际旧 owner 集合、每个受管 plist 的存在性+bytes（官方与 HIL）、login-item 状态和 App 是否存在。bootout 这些 owner。
3. Candidate 必须落在明确 allowed root 下，并从该 root 起检查整条父级链（含父目录 symlink）。可信根由 `.production` / `.sandboxed` 构造器冻结（`trustedRoots`），不得从可变的 backup/staging/scratch 路径反推。install / restore / remove / write / rename 的输入都只对这些根校验；恶意 layout 把 backup 指到任意目录也不能自授权。
4. 同卷 sibling staging 完整拷贝后：fsync 树，再对 staging 内 App/Agent 做与入口相同的完整性与签名校验，最后 `rename` / `replaceItemAt` 原子替换目标 `.app`。覆盖升级与回滚都不得 copy-over 到已有树。**rename/replace 一旦发生，随后真实目录 fsync/清理失败也必须由生产 mutation boundary 转成 `failedAfterAppMutation`（带 underlying hostFailure）**，不得只在测试里直接抛 receipt。回滚按 checkpoint 恢复精确旧树。
5. 写入 LaunchAgent plist：同目录 `O_CREAT|O_EXCL|O_NOFOLLOW` 随机临时文件，完整 fsync 后 `rename` 覆盖目标，不得先删除旧文件，不得跟随预置 symlink。rename 前把原文件（若存在）独占备份到同目录；rename 之后 hook、目录 fsync 或最终文件 fsync 失败时，必须恢复旧 bytes，或在原先不存在时删除目标并 fsync 目录。恢复失败显式 `rollbackFailed`。成功与失败后都不得留下 `.ahakey-*.tmp`。
6. bootstrap 正式 label，注册 macOS 13+ 登录项（真实 `SMAppService.register` 仅存在于 LaunchdControl，本卡不打开）。
7. 成功终态必须同时成立：App 存在、login-item 已注册、官方 plist 精确等于本次写入 bytes、唯一 owner 为正式 Agent。Host 假成功（例如未真正写 plist）不得 accepted。

失败则按 **mutation receipt** 补偿：host 在切换已发生但步骤未正常返回时报告 `failedAfterAppMutation`。尚未切换时不得删除或改动原 App 树。只有存在可信 backup 才从 backup 恢复，且 restore 同样经过 path guard。回滚必须恢复每个受管 plist 的存在性+bytes（原值为 nil 则不得残留新官方 plist）、实际旧 owner、login-item 和 App 是否存在。任何补偿失败都返回 `rollbackFailed`。新鲜安装若已替换 App，则删除半份 App 与新 plist。

`launchctl` bootout/bootstrap 非零退出码必须抛错。`launchctl print` 仅在退出码 `113` 且输出行前缀为 `Could not find service "<label>"` 时视为未加载。权限、domain、command、泛化 `no such process` 以及其他非零必须传播。

## 卸载

先把现有 App 原子搬到备份，再删除全部受管 plist（官方与 HIL）和登录项。中途失败必须从备份恢复，并恢复卸载前记录的 owner 集合与 plist 快照。成功终态：App 不存在、login-item 未注册、受管 plist 均不存在、零 owner。成功后才删备份。

**必须保留：** `~/Library/Application Support/AhaKeyConfig` 以及第三方 Hook 文件（Claude/Cursor/Codex/Kimi）。卸载不得改这些文件。

## 路径安全

删除、复制、写入、rename 前做 canonical / allowed-root 校验；拒绝 symlink 穿透（含 candidate 父目录）、`source=destination`、backup/staging 预存在。白名单是构造器冻结的 `trustedRoots`，layout 各字段在 mutation 前逐项校验；不得按待操作路径自我扩权。`pack-unsigned-candidate.sh` 拒绝 `OUTPUT_DIR` 落在 `/Applications`（含 symlink 解析后）。

## 已知限制（5.9B / HIL）

- 本卡不实际 Developer ID 签名、不公证、不写登录项、不覆盖 `/Applications`。
- 不迁移历史 Keychain/TCC。
- 无 Windows 安装器。
- 真实干净安装、覆盖升级、登录重启由 `HIL-RELEASE-0.2` USER-GATE 执行。
