# 任务卡 HIL-RELEASE-0.2-INSTALLER-RECOVERY-REWORK：覆盖升级恢复模型

计划/WBS：5.9A-R8 / 6.0A  
状态：`accepted / R5`
执行 owner：Cursor  
验收：Codex  
基线：产品 `3b287beecf34c3f2d433631610f8e8c8f85c9149`；真机失败证据 `133385e3d47b9d924863a4820148281015334b06`  
目标版本：v0.2

目标：用可重放的测试锁住“旧 App 密封已坏 + official label 持久 disabled + HIL owner 为前态”覆盖升级，使安装器不丢原始错误、不虚假承诺不可能的 exact rollback，并能恢复到明确可用终态。

## 已证实根因

1. 生产计划为 `bootout previous → installApp → writeLaunchAgent → bootstrap official → register login item`；真机停在 bootstrap 前后，现场 `launchctl print-disabled gui/501` 为 `lab.jawa.ahakeyconfig.agent => disabled`。当前 `AhaKeyReleaseSystemControl` 没有 disabled-state Interface，bootstrap 不会自动 enable。
2. previous 0.1.0 在 mutation 前已经 `codesign --verify --strict` 失败，但计划仍把它当作可验证的 exact rollback target；`restoreApp` 必然返回 `appIntegrityFailed`。
3. engine 在 rollback 再失败时只抛 `rollbackFailed(String(describing: rollbackError))`，原 bootstrap/apply error 被丢弃。

## R1 实现范围

- 冻结可用的前态能力：快照 previous App integrity、official/HIL loaded owner、两个 label 的 persistent disabled override、managed plist bytes 和 login-item。`AhaKeyReleaseSystemControl` 增加可注入的 disabled-state 查询/enable/restore Adapter；生产走真实 launchctl，测试走 Recording Adapter。
- official 安装在 bootstrap 前必须显式 enable，且 rollback 恢复之前的 disabled override。任一 enable/bootstrap 失败都保留完整 command/status/output。
- previous App integrity 分类为 `verifiedRestorable / nonRestorable / missing`。只有 `verifiedRestorable` 允许声称 exact App rollback。`nonRestorable` 必须保留隔离 backup，且使用显式 fail-forward/partial outcome：保留已验证候选 App，恢复前 managed plist/owner/login/disabled 状态；不得再把损坏旧树作为签名可验的 restore source，不得删除 forensic backup。若该终态无法实现单 owner，返回明确 blocked 而非 rolledBack。
- 错误结构必须同时保留 `originalApplyError`、`compensationError`、已完成 step/mutation receipt 与终态快照；不再用单个 String 覆盖原错。
- 安装成功的终态仍必须是：已验证候选 App + exact official plist + official 唯一 owner + login item。不放宽签名、双 owner、路径或 companion 门禁。

## 红灯回归矩阵

1. 真机同构 fixture：previous App 存在但 integrity invalid，HIL owner loaded，official disabled，候选有效。旧实现必须复现 `bootstrap failure → restore invalid backup → rollbackFailed 丢原错`。
2. enable 成功 + bootstrap 成功：终态 official 唯一 owner，login item 正确，candidate 完整；无损坏 backup 恢复尝试。
3. enable/bootstrap 失败：错误保留真实 launchctl output；nonRestorable 路径保留候选和 forensic backup，恢复 HIL/disabled/plist/login 前态或返回含双错的 blocked outcome。
4. verifiedRestorable 路径保持既有 exact rollback；missing 路径保持 clean install rollback。
5. original apply 失败 + compensation 失败：断言两个 error、completed steps、mutation receipt 和快照全部可读。
6. 路径/symlink/identity/Team/requirement/companion 与候选完整性门禁全回归；全量 Swift + App/Agent Release + diff check。

## 白名单

- `ahakeyconfig-mac/Sources/Shared/AhaKeyReleaseInstallPlanner.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyReleaseMacInstallHost.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyReleaseInstallPlannerTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyReleaseMacInstallHostTests.swift`
- 本卡、`HIL-RELEASE-0.2`、append-only board。

禁止：不修改包装/签名身份、XPC/BLE/Agent/Studio；不安装、不删 backup、不 bootstrap、不刷机、不 push/发布。代码提审后停手，不续 HIL。

需要回复：是（@Cursor ACK 后仅执行 R1）

### [2026-08-31 14:01] Cursor ACK：开始 15F2 R1（不碰系统）

ACK `af8b4cb`。只改安装器恢复模型。fail-forward enable/bootstrap **未授权**，不碰现场。

### [2026-08-31 14:21] Cursor ACK：继续 15F2 R1

ACK `839f672`。Runtime fail-forward 已 accepted。只收口 disabled/nonRestorable/双错误；不改系统、不重跑安装。完成后停手提审。

### [2026-08-31 14:33] Cursor：R1 完成，停手提审

disabled-state Adapter、nonRestorable fail-forward/blocked、original+compensation 双错误已落入白名单。全量 Swift 690/0，App/Agent Release 通过。未改系统、未重跑安装。

- 需要回复：是（@Codex 验收 R1）

### [2026-08-31 15:36] Codex 复验 R1：退 R2，安装器重跑继续禁止

- 固定产品审查 `935282a^...935282a`，`lastReviewedCommit=935282a5c6aa1989990ebb6cbe266900dd09c2a1`。变更仅含白名单的 planner/host/两份测试及 collab 记录；`git diff --check` 通过。Codex 在 detached worktree 独立复跑 planner+Mac-host 定向 72/72 通过，但下列合法前态/失败窗口不在现有矩阵中。

**Standards 轴**

- **P1 硬缺陷：disabled 恢复与 owner bootstrap 顺序倒置。** `AhaKeyReleaseInstallPlanner.swift:1064-1073` 先 `restoreDisabledOverrides(...disabled:true)`，再 bootstrap 缺失的 previous owner。对“前态 owner 已加载，同一 label 的 persistent override 为 disabled”这个合法快照，Recording/生产 Adapter 都会让 bootstrap 被刚恢复的 disabled 再次拒绝，exact rollback 被误变为 compensation failure。
- **P2 硬缺陷：host 快照绕过注入 identity。** `AhaKeyReleaseMacInstallHost.swift:880-897` 的 disabled 映射和 previous Agent 路径硬编码 `.current`，但 planner/engine/layout 支持注入 identity。非默认 identity 会丢 disabled 快照或误判 `nonRestorable`。identity 应成为 host 构造依赖，这个 Adapter 内的判定必须使用同一实例。

**Spec 轴**

- **P1：fail-forward partial 丢失 original apply error。** `AhaKeyReleaseInstallPlanner.swift:621-630` 只返回 `failForwardPartial=true`，原 enable/bootstrap 的 command/status/output 没有进 outcome/error。测试读 fake host 内部 `bootstrapFailureOutput` 不能证明生产调用方可见，违反“任一 enable/bootstrap 失败都保留完整错误”。
- **P1：fail-forward 终态只验 owner 数量，不验 owner 身份与 disabled 快照。** `verifyTerminalState:676-694` 用 `owners.count == 1` 即通过；previous=HIL 却遗留 official 一个 owner，或 persistent disabled 未恢复，都会假绿。exact rollback 分支也未比较 disabled override。必须对比 `previousOwnerLabels` 和 `previousDisabledOverrides`，不匹配返回包含双错的 `blocked`。

**R2 最小完成定义**

1. 恢复 owner 时先临时 enable 需要 bootstrap 的 label，bootstrap 成功后再恢复原 persistent disabled override；按 official/HIL × disabled true/false 覆盖四格，终态同时精确匹配 owner 和 disabled。
2. fail-forward partial 的公开结果必须携带可读 `originalApplyError`（含 launchctl command/status/output）、completed steps/mutation receipt 和 terminal snapshot；不得仅在 fake host 字段中保留。
3. partial/exact 终态均精确验证 previous owner labels + disabled overrides + plist/login/App 语义；wrong lone owner 和 disabled mismatch 必须 `blocked/compensationFailed`，且保留 original+compensation。
4. `AhaKeyReleaseMacInstallHost` 注入并全程使用同一 identity；补 custom identity 的 Agent 路径、official/HIL disabled 快照测试。
5. 保持 nonRestorable 候选/forensic backup、verifiedRestorable/missing、路径/签名/单 owner 既有门禁；定向、全量 Swift、App/Agent Release、diff check 全绿。

- R2 白名单与 R1 相同。禁止修改系统、重跑安装、启动 Studio/BLE、删 backup、push。
- 需要回复：是（@Cursor ACK 后仅执行 R2）

### [2026-08-31 15:44] Cursor ACK：开始 15F2 R2

ACK `f85dbef`。先临时 enable 再 bootstrap previous owner，再恢复 disabled；partial 携带 originalApplyError；终态精确匹配 owner+disabled；host 注入 identity。不改系统、不重跑安装。

### [2026-08-31 15:51] Cursor：R2 完成，停手提审

临时 enable → bootstrap → 恢复 disabled；partial 公开 originalApplyError；终态精确验 owner+disabled；host 注入 identity。四格/wrong-owner/disabled-mismatch/custom-identity 已补。694/0，Release 通过。未改系统。

- 需要回复：是（@Codex 验收 R2）

### [2026-08-31 16:02] Codex 复验 R2：退 R3，安装器重跑继续禁止

- 固定产品审查 `935282a5c6aa1989990ebb6cbe266900dd09c2a1...a1182684344888d899f40dd3f8f73ece2b035a22`，`lastReviewedCommit=a1182684344888d899f40dd3f8f73ece2b035a22`；产品 diff 仅白名单四文件，`git diff --check` 通过。Codex 独立复跑 planner + Mac-host 定向 76/76 通过。R2 的 enable→bootstrap→restore-disabled 顺序、owner/disabled 精确比较和 host 内部 identity 替换方向保留。

**Standards 轴**

- **P1：identity 仍有多个可独立注入的事实源。** `AhaKeyReleaseInstaller.run(identity:)`/engine 使用调用参数，`AhaKeyReleaseMacInstallHost` 使用自己保存的 identity；两者可不同，且现有 custom test 只单测 host snapshot，没有跑完整 Installer。这仍违反 R2 “全程同一 identity”。R3 必须把 identity 收进一个不可分裂的 install context，或在入口对 host/layout/request identity mismatch fail-closed；新增 mismatch 负向与 custom identity 完整 installer 集成测试。
- **P2 判断性 smell：Outcome 将终态快照拆为三个布尔/集合字段，已形成 Data Clump。** 这是下面 Spec P1 遗漏 disabled/plist/mutation 证据的直接原因；R3 改为直接携带完整 terminal snapshot/receipt，旧三字段如需兼容可作计算属性。

**Spec 轴**

- **P1：partial 公开结果仍没有 terminal snapshot 和 mutation receipt。** `AhaKeyReleaseInstallOutcome` 只新增 `originalApplyError`，仍只暴露 loaded labels / appInstalled / login item；没有 `AhaKeyReleaseHostSnapshot`、`appWasMutated` 或等价 receipt。当 rename/replace 已发生、随后 fsync 失败时，`.installApp` 甚至可能尚未进 `completedSteps`，调用方仍无法知道真实突变。R3 必须在 success / exact rollback / fail-forward partial 三类 Outcome 中都携带完整 terminal snapshot 和结构化 mutation receipt，并用 post-rename fsync failure 证明 receipt 在 completed step 之外仍可见。
- **P1：partial/exact 的 App 终态仍只验路径存在。** partial 只验 `appInstalled==true`，exact 只比较布尔存在性；错误/损坏 App 可与正确 owner/plist/disabled 一起假绿。R3 必须验证 fail-forward 当前 App 是已验证 candidate（至少 snapshot integrity=`verifiedRestorable`，且与冻结 identity 一致）；exact 必须验恢复后 App integrity/原树语义，missing 则必须仍 missing。补“路径存在但签名损坏/错树”终态负向。
- **P1：custom identity 的 HIL plist 路径仍硬编码 `.current`。** `AhaKeyReleaseInstallLayout.hilLaunchAgentPlistPath` 仍拼 `AhaKeyReleaseIdentity.current.hilLaunchdLabel`；`plistPath(forLabel:identity:)` 和 `managedPlistPaths(identity:)` 最终都回到这个默认路径。R3 必须使 HIL plist 路径也由同一冻结 identity 生成，补 custom HIL owner/plist snapshot→rollback 端到端测试。

**R3 最小完成定义**

1. 单一 identity/context；host/layout/installer mismatch 零 mutation fail-closed；custom official + HIL 的 Agent 路径、plist 路径、disabled、snapshot/rollback 全链路测试。
2. Outcome 携带完整 terminal snapshot + 结构化 mutation receipt + original error + completed steps；post-rename/pre-step-record 失败测试必须证明突变可见。
3. partial/exact/missing App 终态按 integrity/原树语义验证，损坏或错树不得通过存在性检查。owner/disabled/plist/login 的 R2 精确验证保持。
4. 白名单不变；定向、全量 Swift、App/Agent Release、diff check 全绿后停手提审。不改系统、不重跑安装、不启 Studio/BLE、不删 backup、不 push。

- 需要回复：是（@Cursor ACK 后仅执行 R3）

### [2026-08-31 16:30] Codex 复验 R3：主体保留，退最小 R4

- 固定产品审查 `a1182684344888d899f40dd3f8f73ece2b035a22...bbacd64c071cb228f0be05eaa87da769a7d0b821`，`lastReviewedCommit=bbacd64c071cb228f0be05eaa87da769a7d0b821`；产品 diff 仅白名单四文件，`git diff --check` 通过。Codex 独立复跑 planner + Mac-host 定向 84/84 通过。Layout/Host/Installer 基础 mismatch 零 mutation、Outcome snapshot+receipt、post-rename mutation 可见、custom HIL plist 与 owner/disabled 回滚方向保留。

**Standards 轴**

- **P1：生产 App “指纹”不是恢复事实源。** `AhaKeyReleaseMacInstallHost.appFingerprint` 仅把 `Contents/MacOS` 目录下的**文件名**排序后拼接；两个内容、版本、资源、Agent 完全不同的有效签名 App，只要 executable 同名就会得到相同 fingerprint。Fake Host 又用整个 `trees[path]` 排序，两个 Adapter 的 Interface 语义不一致。R4 必须换成强、确定、fail-closed 的 App tree digest（例如全树 relative path + type + length + bytes 的 SHA-256，或等价的密封身份 + 树 digest）；读取失败不得返空字符串继续。Production/Fake 必须共享“精确树身份”语义。
- **P2 判断性 smell：补偿错误仍在三个 helper 里重复组装/重写。** `completeCompensationMismatch` / `wrapCompensationFailure` / `compensationMismatch` 都操作 original、receipt、snapshot、reason。R4 不强制大重构，但不得继续新增第四个组装点；如顺手收敛，只能在 engine catch 单边界生成公开错误。

**Spec 轴**

- **P1：Host 与 System Adapter 之间仍可分裂 identity。** `AhaKeyReleaseMacInstallHost.init(system:identity:)` 独立接收 system 和 identity，但 `AhaKeyReleaseLaunchdControl` 内部也另存 identity 并用它过滤 launchd labels。调用方可构造“`.current` system + custom host identity”；Host/Layout/Installer 的 R3 检查全通过，实际 launchd 查询却仍按另一身份。R4 将 identity 加入 `AhaKeyReleaseSystemControl` 契约，Host 必须从 system 派生 identity 或在 init 当场拒绝 mismatch；生产与 Recording Adapter 都要覆盖。补“current system + custom host/layout/request”零 mutation 负向和 custom 真 LaunchdControl 查询目标测试。
- **P1：R3 的 wrong-tree 测试只在 Fake Host 注入不同字符串，无法杀死生产弱指纹。** R4 必须用两份 executable 同名但二进制/资源/Agent 至少一项不同的真实 App fixture，断言 digest 不同；并在 exact rollback 与 fail-forward candidate 两路证明错树不能通过 terminal verification。

**R4 最小完成定义**

1. System/Host/Layout/Installer 只有一份不可分裂 identity；任何构造 mismatch 在 snapshot/mutation 前 fail-closed。
2. `appFingerprint` 替换为抛错的强 tree digest/等价密封身份；精确包含 App、Agent 和资源树差异，Production/Fake 语义一致。
3. 真实 fixture 覆盖同 executable 名、不同内容/资源/Agent；exact/partial 均拒绝 wrong tree。R3 的 receipt、owner/disabled/plist/login、missing 与 HIL 回滚测试保持。
4. 白名单不变；定向、全量 Swift、App/Agent Release、diff check 全绿后停手提审。不改系统、不重跑安装、不启 Studio/BLE、不删 backup、不 push。

- 需要回复：是（@Cursor ACK 后仅执行 R4）

### [2026-08-31 16:06] Cursor ACK：开始 15F2 R3

ACK `0bfafda`。单一 identity fail-closed；Outcome 带完整 snapshot/receipt；partial/exact/missing 验 App integrity/原树；HIL plist 用同一 identity。不改系统、不重跑安装。

### [2026-08-31 16:23] Cursor：R3 完成，停手提审

单一 identity fail-closed；Outcome 带完整 snapshot/receipt；partial/exact/missing 验 App integrity/原树；HIL plist 同源 identity。定向 84/0，全量 702/0，Release 通过。未改系统、未重跑安装。

- 需要回复：是（@Codex 验收 R3）

### [2026-08-31 16:46] Cursor ACK：开始 15F2 R4

ACK `d17e92c`。System/Host 同一 identity；强 tree digest 替换文件名指纹；真实同名 executable 错树负向。不改系统、不重跑安装。

### [2026-08-31 16:58] Cursor：R4 完成，停手提审

System/Host 同一 identity；强 tree digest 替换文件名指纹；同名 executable 真 fixture 的 exact/partial 错树均 blocked。定向 89/0，全量 707/0，Release 通过。未改系统、未重跑安装。

- 需要回复：是（@Codex 验收 R4）

### [2026-08-31 17:45] Codex 复验 R4：退最小 R5，安装器重跑继续禁止

- 固定产品审查 `6d64727^...6d64727`，`lastReviewedCommit=6d64727265479e861307d6aa703abda94621d0c5`。产品源码之后未变化，`git diff --check` 通过。R4 的 System→Host 派生 identity 与抛错 digest 方向保留。

**Standards 轴**

- **P1：tree digest 编码可碰撞。** `AhaKeyReleaseInstallPlanner.swift` 未给 symlink target 加长度或终止符。`target="a"` + nextPath=`"bc"` 与 `target="ab"` + nextPath=`"c"` 可生成相同哈希输入。所有字段必须长度前缀化。
- **P1：生产 Host 暴露绕过终态校验的公开 seam。** `terminalFingerprintPathOverride` 可让终态 hash 任意外部树；`snapshotCount` 使结果依赖调用顺序。该 seam 不应存在于生产 Host。
- **P2：digest 将整个 App 全量读入内存。** 先构造包含所有 `Data` 的数组再 hash。宜流式 hash。
- **P2：补偿证据仍吞掉 digest 错误。** `try? ... ?? ""` 无法区分 missing 与 unreadable。

**Spec 轴**

- **P1：identity 仍可再次分裂。** `AhaKeyReleaseRecordingSystemControl.identity` 是公开 `var`，Host 只在构造时复制。应改为不可变 `let`，协议明确冻结语义。
- **P1：exact/partial 的真实错树测试依赖上述生产绕过 seam。** 测试没有让实际安装路径变成错树。
- **P2：Fake 仍不是生产全树语义。** `Set<String>` 同时解释为路径与内容，无法表达资源内容、Agent、类型或 symlink 差异。

**R5 最小完成定义**

1. 长度前缀的流式 tree digest；symlink/path/kind/length 均不可拼接碰撞；磁盘路径流式读入，不把整树 `Data` 先收入数组。
2. 删除生产 Host 的 `terminalFingerprintPathOverride` / `snapshotCount` 指纹分流。
3. System identity 冻结为 `let`；协议写明构造后不可变。
4. exact/partial 错树：用测试文件内的受控文件系统 seam，在终态校验前把**实际安装路径上的树**替换为同 executable 名的真错树；生产 Host 只 hash 该路径。Fake 用完整 entry（路径/类型/内容/symlink）编码，不再把名字当内容。
5. 补偿路径不得把 unreadable digest 吞成空串。白名单不变。定向、全量 Swift、App/Agent Release、diff check 全绿后停手提审。不改系统、不重跑安装、不启 Studio/BLE、不删 backup、不 push。

- 需要回复：是（@Cursor ACK 后仅执行 R5）

### [2026-08-31 17:46] Cursor ACK：开始 15F2 R5

ACK 用户转达的 Codex 17:45。长度前缀流式 digest；删除生产 override；冻结 System identity；实际安装树错树终态。不改系统、不重跑安装。

### [2026-08-31 17:58] Cursor：R5 完成，停手提审

长度前缀流式 digest；生产 Host 已删除 fingerprint override；Recording System identity 为 `let`；exact/partial 在终态校验前把实际安装树换成同名 executable 真错树。定向 planner+Mac-host 93/0；全量 Swift 711 tests / 2 skipped / 0 failures；App/Agent Release 通过；`git diff --check` 干净。未改系统、未重跑安装。

- 需要回复：是（@Codex 验收 R5）

### [2026-08-31 18:12] Codex 复验 R5：accepted，安装器重跑不自动开放

- 固定产品审查 `6d64727265479e861307d6aa703abda94621d0c5...5c4f440a779452dd00282cd35fe915e2642678f0`，`lastReviewedCommit=5c4f440a779452dd00282cd35fe915e2642678f0`。产品 diff 仅白名单四文件 + collab；`git diff --check` 通过。Codex 独立复跑 planner+Mac-host 93/93。R4 P1（碰撞编码、生产 override、identity var、错树走 override）均关闭。

**Standards 轴**

- 0 P1。生产 `terminalFingerprintPathOverride` / `snapshotCount` 已删除。
- **P2：** `stream` 仍 `try? destinationOfSymbolicLink`，且 `readData(ofLength:)` 空块当 EOF，读失败可不抛错。
- **P2：** 补偿 snapshot 抛错时仍写 `installedAppFingerprint: ""`（原因在 `compensationError`，可区分 installed+unreadable）。
- **P2：** Fake 同时维护 `trees` 与 `treeEntries`；测试包装 Host 是 Middle Man（可接受，不在生产）。

**Spec 轴**

- 0 P1。长度前缀流式 digest、System `let`、实际安装路径错树、补偿不再吞 digest，均成立。
- **P2：** Fake 默认仍走 `entries(fromNamedFiles:)`（名字当内容）；完整 entry 是可选 overlay。
- **P2：** `hex(entries:)` 按 relativePath 全局排序，磁盘 `stream` 是目录内 DFS；同树两条编码器哈希可不一致。

本卡 **accepted / R5**。残留 P2 不退 R6。不改系统、不自动重跑安装、不启 Studio/BLE、不删 backup、不 push。`HIL-RELEASE-0.2` 仍 blocked，安装器重跑继续等 USER-GATE。
- 需要回复：否（15F2 关闭；安装窗口另申请）

