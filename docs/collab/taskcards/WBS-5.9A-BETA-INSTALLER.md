# 任务卡 WBS-5.9A-BETA-INSTALLER：0.2 最小签名安装链

计划/WBS：5.9A / v0.2
状态：`active / R2`
执行 owner：Cursor（Codex 验收）
基线：`RELEASE-0.2-COMPATIBILITY` accepted @ `d9d2cbba0faf34e931b60e9b6da452251ab4e5fd`
目标版本：v0.2 macOS Beta

目标：在不等待完整权限迁移、Windows 和统一固件的前提下，交付可签名、可安装、可覆盖升级、可卸载、可回滚的 macOS Studio + Runtime 安装链；签名 DMG 在下一张 USER-GATE 卡生成。

## 必须交付

1. 稳定 Bundle ID、Signing ID、Team ID 与 Runtime Mach service 身份。
2. macOS 13+ 正式登录项/后台 helper；macOS 12 支持范围若不在 0.2，安装器必须明确拒绝而不是半安装。
3. 清理或禁用旧 AhaKey Agent，保证任何时刻只有一个设备 owner；保留用户配置和第三方 Hook。
4. 原子安装、覆盖升级、失败回滚、卸载；失败后不得遗留双 Agent、失效 Mach service 或半份 App。
5. 产出可复现的未签名候选、签名输入清单、版本清单、安装/回滚说明与已知限制。

## 明确延后到 5.9B

- 全历史版本 Keychain/TCC 自动迁移矩阵。
- Windows 安装器。
- 完整 1.0 升级/降级支持矩阵与工厂渠道切换。

## 门禁与授权

- 本卡只实现安装器、打包脚本、签名配置检查和可注入的安装/回滚测试；不得实际使用 Developer ID 签名，不修改登录项或 `/Applications`。
- 实际签名、首次安装、覆盖升级、失败注入回滚、卸载重装和登录重启统一放到 `HIL-RELEASE-0.2` 的 USER-GATE 内执行。
- 完成后停手提审；不得自行进入 v0.2 HIL 或发布。

## 执行记录（append-only）

等待兼容策略 accepted；实际签名/安装窗口由下一张 HIL 卡申请。

## Codex 调度裁决：开放 5.9A 未签名安装链（2026-08-29 20:11）

`RELEASE-0.2-COMPATIBILITY` 已 accepted @ `d9d2cbb`。Cursor 可 ACK 后执行本卡既定范围：安装器/打包脚本、签名配置检查、可注入安装与回滚测试、未签名候选及文档。

不得实际使用 Developer ID 签名，不修改登录项或 `/Applications`，不安装、不启动 `HIL-RELEASE-0.2`、不发布、不 push。实际签名、首次安装、覆盖升级、回滚、卸载重装和登录重启继续等待下一张 USER-GATE 卡。

- 需要回复：是（@Cursor ACK `d9d2cbb` 后仅执行 WBS-5.9A）

### [2026-08-29 20:28] Codex：收到 Cursor ACK，翻 active

Cursor 20:22 已核对 `d90353b` 调度与产品基线 `d9d2cbb`。本卡 `ready` → `active`；继续严格禁止实际签名、安装、登录项和 `/Applications` 修改、HIL、发布与 push。

### 5.9A 执行（2026-08-29 20:45，停手提审）

Cursor ACK 后仅执行未签名安装链。未改任务卡状态字段或 queue。未实际 Developer ID 签名、未改登录项、未覆盖 `/Applications`、未启动 HIL、未发布、未 push。

1. **身份**：冻结 Bundle ID / Signing ID `lab.jawa.ahakeyconfig`、Team ID `P2VFVRZK7P`、Mach service `lab.jawa.ahakeyconfig.runtime`、正式 LaunchAgent label；与生产 XPC peer 策略对齐。
2. **规划器**：`AhaKeyReleaseInstallPlanner` 在可注入 host 上完成 macOS 12 拒绝、原子安装/覆盖升级、HIL/旧 Agent bootout、失败回滚、卸载并保留用户配置与第三方 Hook。LaunchAgent 模板含 MachServices。
3. **打包**：`pack-unsigned-candidate.sh` 强制 ad-hoc、拒绝 `INSTALL_TO_APPLICATIONS` 与 `REQUIRE_DEVELOPER_ID`；`check-release-identity.sh` 校验冻结清单。签名输入与安装/回滚说明写入 `Packaging/`。

门禁：安装规划 **11/11**；身份脚本通过；全量 `swift test` **604 执行 / 0 失败**（2 skip）；App+Agent Release 与产品范围 `git diff --check` 通过。产品 commit **`953071f`**。审查产品范围请用 `c638944...953071f`。

- 需要回复：是（@Codex 按 `c638944...953071f` 验收 WBS-5.9A；accepted 前不进入 HIL-RELEASE-0.2）

### [2026-08-29 21:12] Codex：5.9A 暂不 accepted，退 R1

固定验收范围 `c6389448a6f1f20d05def6c033b8db0b712a51f7...953071fd225b21063b3bfc0f13bf12c1b3fea564`，`lastReviewedCommit=953071fd225b21063b3bfc0f13bf12c1b3fea564`。独立复跑规划器 11/11、身份脚本与 diff check 均通过，但门禁没有覆盖下列发布阻塞，5.9A 暂不 accepted：

1. **P1 候选与签名身份 fail-open**：`candidate=nil` 可跳过检查；Developer ID 报告缺 Team ID 或 Signing ID 时仍会通过。执行边界必须自行 inspect，并要求 Bundle/Agent/Mach/Team/Signing 全部精确、非空匹配；补 nil/错值/未检查候选负向测试。
2. **P1 非原子安装**：当前 `copyTree(candidate, /Applications/...)` 是原地递归复制，无法保证无旧文件混合或崩溃半包。改为同卷 sibling staging，完整校验与必要落盘后再原子 rename/swap；覆盖升级与恢复均不得 copy-over。
3. **P1 回滚/卸载不可信**：补偿操作的 `try?` 会吞掉失败，却仍报告 `rolledBack=true`；卸载在删除 App 后失败也没有可恢复备份。必须保存并恢复精确的旧 App、plist、login item 与实际旧 owner label 集合；恢复失败必须显式返回失败，成功/回滚后都验证单 owner。
4. **P1 路径安全缺失**：所有 destructive path 在执行前做 canonical/allowed-root 校验，拒绝 symlink 穿透、`..`、source=destination、backup 预存在和 `/Applications` 输出绕行。`pack-unsigned-candidate.sh` 不能只检查环境变量，`OUTPUT_DIR=/Applications/...` 也必须拒绝。
5. **P1 缺生产执行器**：不能只交付 protocol + FakeHost。补真实 macOS host/入口，覆盖文件原子替换、launchctl、登录项以及候选 inspection；本卡只编译和在沙箱/fixture 中验证，仍不得实际安装或修改系统。
6. **P2 身份单一来源与签名清单**：消除 Swift/JSON/plist/shell 多份手写常量，至少增加跨产物强一致性门禁；裸 Agent 的签名命令显式使用 `--identifier lab.jawa.ahakeyconfig`，并让候选校验实际确认 ad-hoc、拒绝 Developer ID。

R1 仅改 5.9A 的身份、安装引擎/生产 host、打包/校验脚本、对应测试与 Packaging 文档。禁止实际 Developer ID 签名、安装、登录项或 `/Applications` 修改、HIL、发布、push；`HIL-RELEASE-0.2` 继续保持 draft / USER-GATE。

- 需要回复：是（@Cursor ACK 后执行 5.9A R1；完成后停手重提）

### 5.9A R1 执行（2026-08-29 21:40，停手重提）

ACK `1225884` 后只做未签名安装链硬化。未改任务卡状态字段或 queue。未实际 Developer ID 签名、未改登录项、未覆盖 `/Applications`、未启动 HIL、未发布、未 push。

1. **身份 fail-closed**：`AhaKeyReleaseInstaller.run` 自行 inspect；nil/未知签名/缺 Team 或 Signing 一律拒绝。未签名必须 ad-hoc 且 Signing ID 精确匹配。
2. **原子替换**：同卷 sibling staging + `replaceItemAt`/`rename`；覆盖升级丢掉旧树多余文件，不再 copy-over。
3. **回滚**：补偿不再 `try?`；恢复失败返回 `rollbackFailed`。卸载先原子挪走 App，失败可恢复。成功/回滚后验证单 owner。
4. **路径**：canonical/allowed-root；拒绝 allowed-root 内 symlink、source=destination、backup/staging 预存在。packer 对 `OUTPUT_DIR=/Applications/...`（含 realpath）拒绝。
5. **生产 host**：`AhaKeyReleaseMacInstallHost` + `AhaKeyReleaseLaunchdControl`（默认拒绝系统突变）。沙箱/fixture 验证文件原子替换与 ad-hoc inspect。
6. **单一来源**：`Packaging/ReleaseIdentity.json` 与 Swift 嵌入 JSON、XPC peer、`build.sh`/`check-release-identity.sh` 对齐；Agent/App `codesign --identifier lab.jawa.ahakeyconfig`。

门禁：规划器 **26/26**；Mac host **5/5**；全量 `swift test` **624 执行 / 0 失败**（2 skip）；App+Agent Release；`check-release-identity.sh` 通过；产品 `git diff --check` 通过。产品 commit **`6ff0201`**。审查 R1 产品范围请用 `3ea8a71...6ff0201`。

- 需要回复：是（@Codex 按 `3ea8a71...6ff0201` 验收 WBS-5.9A R1；accepted 前不进入 HIL-RELEASE-0.2）

### [2026-08-29 22:05] Codex：R1 暂不 accepted，退 R2 真实执行边界

固定验收范围 `3ea8a71a3327d3ff3ef055f13142494cc820d6c6...6ff0201380ed2eedda77399c0c3a8661f895e396`，`lastReviewedCommit=6ff0201380ed2eedda77399c0c3a8661f895e396`。独立复跑 planner 26/26、Mac host 5/5、身份脚本和产品 diff check 均通过；R1 已闭合 nil/字段身份、copy-over、基本路径与 packer 防护，但真实执行边界仍有以下 P1：

1. **回滚会删除尚未替换的旧 App**：升级/卸载在首个 bootout 后、`installApp/removeApp` 前失败时，backup 尚不存在；`restoreApp` 看到 backup 不存在却会删除当前 `applicationsAppPath`。R2 必须按实际 mutation checkpoint 补偿：未移动/替换 App 时保持原树原样；只有存在可信 backup 才恢复。补首个 bootout 后失败的 exact-tree 测试。
2. **回滚终态没有恢复精确旧状态**：当前固定 bootstrap 正式 label，忽略 `previousOwnerLabels`；终态也只查 owner，不核对 App、plist、login item。记录并恢复实际旧 owner 描述与对应 plist/登录项；回滚后精确比较旧 App 是否存在、旧 plist bytes、旧 owner 集合和 login-item 状态。无法安全描述的多 owner 前态必须在任何 mutation 前 fail-closed。
3. **生产 launchd/login 状态仍是 stub**：`loadedLaunchdLabels()` 恒为空，`loginItemRegistered` 是进程内布尔值，`runLaunchctl` 不检查退出码。用真实 `launchctl print gui/<uid>/<label>`/等价只读查询和 `SMAppService` status 建立 snapshot；bootout/bootstrap 非零必须抛错。补 Recording/fixture 覆盖旧正式、HIL、命令失败与 bootstrap 后单 owner。提供产品可调用的 production installer factory/入口，但本卡仍不得执行系统 mutation。
4. **候选身份只验证外层 App 描述**：安装入口没有单独验证 Agent 签名，也没有 `codesign --verify --strict` 完整性校验；正确 App 外壳可夹带错误/篡改 Agent。App 与 Agent 分别做完整性验证、精确 signing/team/ad-hoc 检查；staging copy 后在切换前重复同一完整校验，不只检查 Agent 文件存在。
5. **路径与持久化边界未完全闭合**：candidate 只检查末节点 symlink，父目录 symlink 仍可穿透；`removeTree/writeFile` 等 destructive path 也未统一经过 guard。所有复制、删除、写入、rename 输入均走 validated path；candidate 引入明确 allowed root 并检查整条父级链。staging 与关键目录在原子切换前后做必要 fsync；plist 写入不得先删旧文件再 rename，避免崩溃缺失窗口。

R2 仅改安装/身份/路径 host、真实只读状态适配、对应测试与 Packaging 文档；保留 R1 已通过的 planner 语义与 packer 防护。禁止真实签名、安装、登录项或 `/Applications` 修改、HIL、发布、push；`HIL-RELEASE-0.2` 继续 draft / USER-GATE。

- 需要回复：是（@Cursor ACK 后只执行 WBS-5.9A R2，完成后停手重提）

### 5.9A R2 执行（2026-08-29 22:24，停手重提）

ACK `57a8153` 后只修真实执行边界。未改任务卡状态字段或 queue。未实际 Developer ID 签名、未改登录项、未覆盖 `/Applications`、未启动 HIL、未发布、未 push。

1. **Mutation checkpoint 回滚**：未 `installApp`/`removeApp` 时保持原 App 树；仅在有可信 backup 时恢复。首个 bootout 后失败的 exact-tree 测试覆盖 official+HIL。
2. **精确旧 owner**：记录并恢复实际 owner 集合、plist bytes、login-item 与 App 是否存在；不再固定 bootstrap 正式 Agent。未知 label 或缺失 plist 在 mutation 前 fail-closed。
3. **真实只读状态**：`AhaKeyReleaseLaunchdControl` 用 `launchctl list` / `print gui/<uid>/<label>`，非零退出抛错；login 读 `SMAppService.mainApp.status`。`AhaKeyReleaseInstaller.productionHost()` 入口存在，默认禁止系统突变。
4. **App/Agent 完整性**：分别 `codesign --verify --strict` 与精确 signing/team/kind；staging 切换前重验。
5. **路径与持久化**：candidate 明确 allowed root + 整条父链；destructive path 走 guard；staging/关键目录 fsync；plist 同目录 temp + `rename` 覆盖，不先删旧文件。

门禁：规划器 **34/34**；Mac host **11/11**；全量 `swift test` **638 执行 / 0 失败**（2 skip）；App+Agent Release；`check-release-identity.sh` 通过；产品 `git diff --check` 通过。产品 commit **`11c5a2b`**。审查 R2 产品范围请用 `6ff0201...11c5a2b`。

- 需要回复：是（@Codex 按 `6ff0201...11c5a2b` 验收 WBS-5.9A R2；accepted 前不进入 HIL-RELEASE-0.2）
