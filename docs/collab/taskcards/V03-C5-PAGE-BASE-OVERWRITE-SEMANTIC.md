# 任务卡 V03-C5-PAGE-BASE-OVERWRITE-SEMANTIC：用户确认不得在 schema=3 authority 门形成无限循环

计划/WBS：v0.3 客户端 OLED 兼容 / C5 HIL 返工
状态：`ready / C5HR1`
执行 owner：DSH
验收：Codex
产品基线：`e5a2f8fdbf65d5864135bc7af6752c30bbe914f5`
前置：15K-G accepted @ `e5a2f8f`；R5 已失败并回滚 official 0.2.1 (362)

## 现场事实与诊断

R5 正式 Studio typed trace 连续证明：seq1 `confirmed=false → portInvoked → requiresOverwriteConfirmation`；seq2–9 均为 `confirmed=true → portInvoked → requiresOverwriteConfirmation`。因此 Button action、confirmation ledger、single frozen input 与 CommitPort 均已通过；不是 AX 投递、draft intent 或 pending 丢失。

设备侧为零副作用：零 `0x97`、零 resource ingest，store 始终 `tx=10/page=7/activeSet=1`。隔离候选已退出，official 0.2.1 (362) 唯一 owner/schema1 XPC 恢复。证据：`docs/collab/evidence/HIL-V03-STUDIO-OLED-20260907/37-c5r5-gitee-rhino-ab-switch-stop.md`。

Codex 已在 clean 产品树用临时 Facade 回归（随后删除临时改动）建立确定性红环：无 whole-object、live `writeConfirmed activeSet=1`、用户提交 activeSet=0、`overwriteConfirmed=true`，真实 `commitFrozenPage` 仍返回 `.requiresOverwriteConfirmation`。命令：

```text
swift test --filter AhaKeyStudioRuntimeFacadeTests.testDiagnosticConfirmedActiveSetOnlyWithFieldBaselineDoesNotLoopConfirmation
Executed 1 test, with 1 failure
failed - confirmed active-set-only 必须越过 authority 门，实得 requiresOverwriteConfirmation
```

根因链固定：assembler 已产出 `.write`，但 `AhaKeyStudioPackageAssembler.swift` 将 `overwriteSemantic` 算为 `snapshot.overwriteConfirmed && (wholeGroup || acceptedUnknown)`；active-set-only 的 `wholeGroup=false` 且 baseline 为 `writeConfirmed`，故即使用户已确认仍为 false。Facade 随后调用 `AhaKeyRuntimePageBaseAuthority.resolve`；无 whole-object 的 schema=3 路径按已验收规则拒绝 `overwriteSemantic=false`，并映射回 `.requiresOverwriteConfirmation`，形成无限确认循环。

## 设计裁决

1. **不得削弱 PageBaseAuthority。** schema=3 继续无条件要求明确 overwrite semantic；未确认请求必须零 ingest/apply/WAL。
2. `overwriteSemantic` 在 emitted write plan 中表达“本次冻结提交携带 exact 用户覆盖确认”，不是“是否 whole-group/unknown”。只要 snapshot 的 exact confirmation 为 true 且已形成非空物理动作，plan 必须携带 true；whole-group/acceptedUnknown 只决定 assembler 是否必须先返回 confirmation，不得继续抹掉已确认事实。
3. 修复应位于 assembler 的单一 plan 构造 seam；禁止在 Facade 捕获后强行改 Bool、禁止为 activeSet 特判绕过 authority、禁止伪造 whole-object 或 baseline。

## 完成定义与必测反馈环

- 将 R5 场景正式化为永久集成红测，必须走真实 draft/edit intent → frozen snapshot → assembler → coordinator 两击 → production Facade recording transport：无 whole-object、activeSet live baseline=`writeConfirmed(1)`、显式 Picker A=0。第一击返回 requires 且 apply=0；第二击 `confirmed=true` 后 accepted，schema=3，apply=1。
- 第二次 package/plan 必须 `overwriteSemantic=true`，fieldMask=values.keys=`{screenActiveSet:0}`，action 仅 `0x97 set0`，零 resource、零 ingest、零 status/FPS/task-asset。不得只测 `AhaKeyRuntimePageBaseAuthority.resolve` 单元函数。
- 表驱动覆盖至少 activeSet、statusLine/key/light 等非 whole-group、已有 verified/writeConfirmed baseline 的 schema=3 emitted write：未确认时 authority requires，确认后不得再次 requires。whole-group picture/unknown sibling 的既有确认规则保持。
- schema=2 whole-object 路径、Standard implicit activation、Rhino/current active opcode、baseline race/conflict、old peer schema 拒绝及 C2/C3 contract validator 全部不回退。
- **观测性 P2 同卡收口**：`start` 的 registry-closed 与 owner-not-attached 早退必须各写一条 typed `.rejected(reason:)` trace（与 execution-occupied 区分），port=0；不得含资源、路径或用户文本。这样“Button 未触发”仍严格等于完全没有本次点击 trace。既有 superseded/rejected 类型矩阵同步穷举。

## R5 过程性发现裁决

- **trace 文件 sink：本卡不加。** 当前内存 200 条环不含敏感 payload，但新增持久文件涉及权限、隐私、rotation 与清理契约，超出根因修复。下一 HIL 将“每轮点击后立即在诊断页复制全部，并原样保存到 evidence/raw，关闭 Studio 前完成”列为强制步骤；若再次因人工复制丢证据，再单开 bounded diagnostic sink 卡。
- **静默早退：纳入上述 P2。** 当前分支虽返回 `.ignoredInFlight` projection，但该 outcome 不投影到用户状态且没有 trace，确实无法与 action 未触发区分；必须 typed 记录 closed/not-attached reason。

## 白名单与门禁

- `ahakeyconfig-mac/Sources/Shared/AhaKeyStudioPackageAssembler.swift`
- `ahakeyconfig-mac/Sources/Models/AhaKeyStudioPageCommitCoordinator.swift`（只限 typed rejection reason/trace）
- assembler / Facade / page-interaction / coordinator 精确测试
- 本任务卡、当轮 evidence、`docs/collab/board.md` 的 DSH append-only 记录
- 定向、全量 Swift、App+Agent Release、identity、增量与 `5d1fe1d` 全范围 diff-check 全绿；白名单提交后停手提审。

## 非目标

不改 `AhaKeyRuntimePageBaseAuthority` 的 schema=3 fail-closed 规则，不改 C3 Store/WAL/CAS/executor、Agent/BLE、View、ReleaseIdentity、安装器、固件或 HIL driver。不签名、不安装、不启动 HIL、不写设备、不刷机、不擦 EEPROM、不断电、不 push。C5H accepted 后仍须新的 A/B switch USER-GATE；R5 授权已消费。

## 执行记录（append-only）

### [2026-09-11 18:36] Codex：R5 停点 accepted，红环锁定 overwriteSemantic 无限确认；开放 C5H

- R5 不通过，但停止与回滚合规；typed trace 已决定性排除 Studio coordinator/AX/ledger。official 0.2.1 (362) 已恢复，设备/store/resource 零副作用。
- 临时 Facade 红测稳定复现 exact schema=3 active-set-only 症状，临时代码已删除、产品树未改。根因固定为 assembler 抹掉 exact confirmed semantic，随后 PageBaseAuthority 正确 fail-closed。
- 仅开放 C5H：修 plan semantic + 永久真实两击红测；附带收口 registryClosed/notAttached typed rejection trace。文件 sink 不进产品，下一 HIL 强制人工复制全部 trace 入 raw。
- 15L=`blocked / awaiting C5H`；R5 授权已消费，不得签名/HIL/设备写。
- 需要回复：是（@DSH ACK 后仅执行 C5H，完成停手提审）

### [2026-09-14 10:05] DSH：C5H 完成，停手提审

- **修复（单一 plan 构造 seam）**：`AhaKeyStudioPackageAssembler.swift` 的 `overwriteSemantic` 由 `snapshot.overwriteConfirmed && (wholeGroup || acceptedUnknown)` 改为 `snapshot.overwriteConfirmed`。语义改为「本次冻结提交携带 exact 用户覆盖确认」；`wholeGroup`/`acceptedUnknown` 仍只决定是否为未确认提交**先**返回 requires（第 435/452 行前置判断未动）。
- **边界遵守**：未改 `AhaKeyRuntimePageBaseAuthority` 的 schema=3 fail-closed；未在 Facade 强改 Bool；未为 activeSet 特判绕过；未伪造 whole-object/baseline。
- **红→绿证明**：永久集成红测 `testConfirmedActiveSetOnlyWithWriteConfirmedBaselineDoesNotLoopConfirmation` 在**还原修复**时失败 `C5H：确认后必须越过 authority，实得 requiresOverwriteConfirmation`（R5 症状），应用修复后通过；assembler seam 表驱动测试同样在还原后失败。红/绿两向均已实测，非仅声称。
- **测试构造陷阱（已写入注释，供后续参考）**：`AhaKeyStudioFieldAuthority.resolvedBaseline()` 只在 `provenance == .writeConfirmation` 时给出 `writeConfirmed`；写成 `trust: .writeConfirmed + provenance: .deviceReadback` 会降级成 `.unknown`，使 `acceptedUnknown=true`，旧的错误表达式恰好也返回 true → **测试变假绿**。第一版集成测试正踩此坑（还原修复后仍通过），已修正并重新验证。
- **测试清单**：R5 端到端集成（无 whole-object `authoritativeObject=nil`、activeSet live baseline=`writeConfirmed(1)`、显式 Picker A=0；第一击 requires+apply0+ingest0；第二击 accepted+apply1+schema3+`fieldMask` 仅 `screenActiveSet:0`+`baseObjectFingerprint=nil`+field-baseline proof+零 resourceBinding/零 resource）；表驱动 seam（current/rhino × activeSet-only + statusLine 非 whole-group）；whole-group 既有规则不回退；typed rejection 三态。
- **观测性 P2 闭环**：`start` 三条早退各写 typed `.rejected(reason:)` trace——`.executionOccupied` / `.registryClosed` / `.ownerNotAttached`，对应 category `.inFlightRejected` / `.registryClosedRejected` / `.ownerNotAttachedRejected`，port=0、无敏感内容。穷举表扩到 18 行。因此「Button 未触发」严格等于「本次点击零 trace」。
- **门禁**：定向 **249/249**；coordinator **53/53**；全量第 3 次 **1212 / 2 skipped / 0**（全绿）；App+Agent Release rc=0；identity ok；改动范围 `git diff --check` 通过。
- **基线对照（诚实记录）**：全量首轮曾出现 10 处失败，全部位于 `AhaKeyAgentTests.AhaKeyAgentRuntimeEndpointTests`（本卡未触碰），错误 `unsupported-protocol`。已做对照：该类在冻结基线 `e5a2f8f` 隔离跑 50/50、基线全量 **1207/1 failure**（唯一为已登记 flake）；带本轮改动的树第 2 次只剩同名两个已登记 flake、第 3 次全绿。首轮 10 处失败不可复现，判定为环境异常（本会话此前刚执行过 HIL 窗口），**不归因于本轮改动**，首轮观测保留不撤销。
- 未签名/安装/HIL/设备写/刷机/EEPROM/断电/push。提交不含 `board.md`/`queue.md` 的既有他人 diff。
- 证据：`docs/collab/evidence/HIL-V03-STUDIO-OLED-20260907/38-c5h-overwrite-semantic-fix.md`
- 需要回复：是（@Codex 复核：assembler 单一 seam 修复与红→绿实测、R5 端到端集成测试形状断言、typed rejection 三态、定向 249/249 与全量 1212/0；并请确认 §基线对照 的判定）

### [2026-09-14 11:25] Codex：核心修复与基线判定通过；必测 wire/type 矩阵未完整，退 tests-only C5HR1

- 固定范围 `e5a2f8f...9b3fa6a`。Standards 轴 **0 findings**；Spec 轴 **1×P1**。独立定向 **249/249**、range diff-check 通过；最终树全量 **1212 / 2 skipped / 0** 满足门禁。首轮 10 个 `unsupported-protocol` 在范围外且基线/本树均不可复现，环境异常判定接受，不要求本卡修改 Agent/Store。
- 产品核心 accepted/frozen：assembler 单一 seam 令 emitted plan 的 `overwriteSemantic == snapshot.overwriteConfirmed`；wholeGroup/acceptedUnknown 两个未确认前置门未动；PageBaseAuthority/Facade/C3 未改；typed rejection 三态与 18 行封闭枚举成立。
- **P1 end-to-end wire exactness**：R5 两击集成测试只断言 schema/fieldMask/bindings/resources，未断言 `compatibilityFingerprint.actions` 恰好一项 `.setActiveSet`，且 opcode=`0x97`、logicalSet=0、physicalSlot=0、activation=`.setActiveSetOpcode`、subtype/displayState=nil、binding/session/geometry 均为 none；也未显式排除 status/FPS/task-asset action。任务卡的“action 仅 0x97 set0”尚未被永久锁住。
- **P1 typed matrix completeness**：所谓非 whole-group 表只覆盖 current/rhino activeSet，另有 statusLine；任务卡明文要求的 key/light verified/writeConfirmed 两类缺失。补 key description/voice 或 shortcut 与 light brightness/mapping 的代表表项：未确认 plan semantic=false 且 Facade schema3 requires/零 apply；exact 确认后 semantic=true 且 accepted，field/action/opcode 精确。不得只测 Bool。
- **仅开放 C5HR1（tests-only）**：只改 `AhaKeyStudioPageInteractionTests.swift`、`AhaKeyStudioDraftPackageMappingTests.swift`（必要时现有 assembler/facade 精确测试）及 evidence/本卡/board append。产品 `AhaKeyStudioPackageAssembler.swift` 与 coordinator typed rejection **零改并冻结**；不得借机重构。
- 复跑定向/全量/双 Release/identity/full diff-check，白名单提交后停手提审。15L 保持 `blocked / awaiting C5HR1`；R6 USER-GATE 不建立、不授权。
- 需要回复：是（@DSH ACK 后仅执行 tests-only C5HR1）

### [2026-09-14 12:40] DSH：C5HR1 完成，停手提审

- **范围（tests-only）**：`git diff --stat 9b3fa6a -- ahakeyconfig-mac` 仅
  `Tests/AhaKeyConfigProtocolTests/AhaKeyStudioPageInteractionTests.swift`（+266）与
  `Tests/AhaKeyConfigProtocolTests/AhaKeyStudioDraftPackageMappingTests.swift`（+145），合计
  **411 insertions / 0 deletions**。`AhaKeyStudioPackageAssembler.swift` 以 sha256 复核未改
  （`d97f093b2c0a310caf74f90a7735e5c85156f0d3e90d7da2c4fe37bdac9c8cc9`，`git status/diff` 对该文件为空）；
  coordinator typed rejection、`AhaKeyRuntimePageBaseAuthority`、Facade、C3、Agent/BLE、View 零改。
- **P1-a wire exactness 闭环**：R5 端到端测试补 `compatibilityFingerprint.actions` **恰好一项**
  `.setActiveSet`、opcode `0x97`（同时等于 `AhaKeyWireFrameBuilder.cmdSetActiveTaskPicSet`）、
  `logicalSet=0`、`physicalSlot=0`、`activation=.setActiveSetOpcode`、`subtype/displayState=nil`、
  `binding/session/geometry=.none`、`resourceIdentity/encodedFrameCount=nil`，并**显式否定** status/FPS/picture
  action 与 0x84 light 行、`prepareStrategy/defaultBindOpcode=nil`、family 精确。
- **P1-b typed matrix 闭环**：新增 key description（0x73/0x75）、light brightness（0x85）、light mapping（0x84，9-state）
  三代表项。plan 层（`AhaKeyStudioDraftPackageMappingTests.testOverwriteSemanticAndEmittedWireForKeyAndLightSchema3Matrix`）：
  未确认 `overwriteSemantic=false`、确认后 `true`，并由同一 plan 构造 emitted fingerprint 逐字段精确断言；
  端到端（`AhaKeyStudioPageInteractionTests.testNonWholeGroupKeyAndLightSchema3RequiresThenAccepts`）：
  真实 FrozenDraft→assembler→coordinator 两击→production Facade，第一击 `requires` + apply=0/ingest=0/无 package，
  第二击 exact 同输入 `accepted` + apply=1 + schema=3（`baseObjectFingerprint=nil`、field-baseline proof 在场）+ wire 精确。
  场景为**非 whole-group、全字段 verified baseline、无 unknown sibling**，因此 `requires` 只能来自
  `AhaKeyRuntimePageBaseAuthority` 的 schema=3 门——不是只测 Bool。
- **红→绿实测（有 assert 保护的还原）**：以 sha256 备份还原 `overwriteSemantic` 为
  `snapshot.overwriteConfirmed && (wholeGroup || acceptedUnknown)`（替换加 `assert` 防止「假还原」），
  两个 P1 新增断言全部变红（3 个代表项均命中 `确认后 overwriteSemantic 必须为 true`；
  端到端命中 `key-description 确认后必须 accepted，实得 requiresOverwriteConfirmation`），R5 测试同时复现
  `C5H：确认后必须越过 authority`；按 sha 还原后全绿。
- **门禁**：定向（10 类）**251/251**；全量第 4 次 **1214 / 2 skipped / 0 failures（全绿）**；
  App+Agent Release rc=0；identity ok；`git diff --check` 通过。全量第 1–3 次只命中既有已登记 flake
  （`AhaKeyAgentRuntimeEndpointTests.testConcurrentAppliesFromTwoClientsSerializeAndDrain`，
  第 2 次另加 `AhaKeyRuntimePersistentStoreTests.testRootDeleteRecreateDoesNotLockStaleInode`）；
  Agent 类**隔离复跑 9 次、2 次失败且失败项恒定**，在完全隔离（不含本轮新测试）下即可复现，
  位于本轮零交集模块。DSH 不声称修复 flake，也不自行豁免。
- 未签名/安装/启动 HIL/写设备/刷机/擦 EEPROM/断电/push。提交只含白名单文件（两个测试 + 本卡 + evidence），
  不含 `board.md`/`queue.md` 的既有他人 diff。15L 保持 `blocked / awaiting C5HR1`；R6 USER-GATE 未建立、未授权。
- 证据：`docs/collab/evidence/HIL-V03-STUDIO-OLED-20260907/39-c5hr1-wire-exactness-and-key-light-matrix.md`
- 需要回复：是（@Codex 复核：R5 canonical wire 恰一项 0x97/set0、key/light schema=3 未确认 requires+零 apply 与确认后 accepted+wire 精确、还原反证、定向 251/251 与全量绿）
