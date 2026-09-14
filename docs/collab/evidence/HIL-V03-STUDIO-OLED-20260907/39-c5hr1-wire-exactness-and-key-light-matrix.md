# 39 — C5HR1：canonical wire 精确断言 + key/light schema=3 必测矩阵（tests-only）

任务卡：`V03-C5-PAGE-BASE-OVERWRITE-SEMANTIC`（ready / C5HR1）
执行 owner：DSH；验收：Codex
基线：`9b3fa6a`（C5H，产品修复已冻结）
日期：2026-09-14

## 1. 范围与边界

Codex 11:25 退审把 C5H 的产品核心判为 accepted/frozen，只留 **1×P1 必测缺口**，并要求 **tests-only** 补测：

- **P1-a end-to-end wire exactness**：R5 两击集成测试未断言 `compatibilityFingerprint.actions` 恰好一项
  `.setActiveSet`，也未锁 opcode=`0x97`、`logicalSet=0`、`physicalSlot=0`、`activation=.setActiveSetOpcode`、
  `subtype/displayState=nil`、`binding/session/geometry=.none`；也未显式排除 status/FPS/task-asset action。
- **P1-b typed matrix completeness**：非 whole-group 表只有 current/rhino activeSet 与 statusLine；
  key description/voice/shortcut 与 light brightness/mapping 的代表项缺失。

本轮改动 **tests-only，产品代码零改**：

```
ahakeyconfig-mac/Tests/AhaKeyConfigProtocolTests/AhaKeyStudioDraftPackageMappingTests.swift | 145 +++++++++++
ahakeyconfig-mac/Tests/AhaKeyConfigProtocolTests/AhaKeyStudioPageInteractionTests.swift    | 266 +++++++++++++++++++++
2 files changed, 411 insertions(+), 0 deletions(-)
```

`git diff --stat 9b3fa6a -- ahakeyconfig-mac` 只有上述两个文件、**0 deletions**；
`AhaKeyStudioPackageAssembler.swift` 以 sha256 复核为未改动（见 §4）。
未改 coordinator typed rejection、`AhaKeyRuntimePageBaseAuthority`、Facade、C3、Agent/BLE、View、ReleaseIdentity；
未签名/安装/启动 HIL/写设备/刷机/擦 EEPROM/断电/push。

## 2. P1-a 闭环：R5 端到端 canonical wire

`testConfirmedActiveSetOnlyWithWriteConfirmedBaselineDoesNotLoopConfirmation` 在既有
schema/fieldMask/bindings/resources 断言之后，补：

- `fingerprint.actions.count == 1`（不得多 action）；
- `fieldID == .screenActiveSet(modeSlot: 0)`；`command == .setActiveSet`；
  `opcode == 0x97` 且同时等于 `AhaKeyWireFrameBuilder.cmdSetActiveTaskPicSet`；
- `subtype == nil`、`logicalSet == 0`、`physicalSlot == 0`、`displayState == nil`；
- `activation == .setActiveSetOpcode`、`binding/session/geometry == .none`；
- `resourceIdentity == nil`、`encodedFrameCount == nil`；
- **显式否定** status/FPS/picture action；`lightMappingRows` 为空；`prepareStrategy`/`defaultBindOpcode` 为 nil；
- `family == .rhinoDualSet(sessionUpload: false)`。

这样任务卡「action 仅 0x97 set0」被永久锁在**真实 Facade 应用包**上，而不是只断言 schema/fieldMask。

## 3. P1-b 闭环：key/light schema=3 matrix（plan 层 + Facade 端到端）

代表项：`keyDescription`（0x73/0x75，key 有 wire 的真实标量字段）、`lightBrightness`（0x85）、
`lightMapping`（0x84，9-state 整行）。三例均为**非 whole-group、已有 verified live baseline、无 unknown sibling**，
因此未确认时 `assembler` 仍产出 plan（不由 wholeGroup/acceptedUnknown 前置门拦截），
`requires` 只能来自 `AhaKeyRuntimePageBaseAuthority` 的 schema=3 门——这正是 C5H 要锁的语义。

**plan 层（`AhaKeyStudioDraftPackageMappingTests`）**
`testOverwriteSemanticAndEmittedWireForKeyAndLightSchema3Matrix`：每个代表项

| 断言 | 未确认 | exact 确认后 |
|---|---|---|
| `overwriteSemantic` | `false` | `true` |
| `fieldMask` / `values.keys` | 仅该代表字段 | 仅该代表字段 |
| `compatibilityFingerprint.actions` | — | **恰好 1 项**，field/command/opcode/subtype 精确 |
| 其它 action 维度 | — | `logicalSet/physicalSlot/displayState=nil`，`activation/binding/session/geometry=.none`，无 resourceIdentity/encodedFrameCount |
| light 行 | — | 仅 `lightMapping` 行非空且为 9-state；其余为空 |
| `prepareStrategy` / `defaultBindOpcode` | — | `nil` |
| `resources` | — | 空 |

**Facade 端到端（`AhaKeyStudioPageInteractionTests`）**
`testNonWholeGroupKeyAndLightSchema3RequiresThenAccepts`：真实 `FrozenDraft → snapshot → assembler →
coordinator 两击 → production Facade → recording transport`，`authoritativeObject=nil`、该页全字段
verified durable baseline。每个代表项：

| 阶段 | 断言 |
|---|---|
| 第一击（未确认） | `.requiresOverwriteConfirmation`；snapshot `overwriteConfirmed=false`；**apply=0、ingest=0、无 appliedPackage** |
| 第二击（exact 同输入） | `secondInput == firstInput`；`.accepted`；apply=1、ingest=0 |
| 应用包 | `schemaVersion == fieldBaselineSchemaVersion`；`baseObjectFingerprint == nil`；`fieldBaselines != nil`；零 resourceBinding/零 resource |
| wire | actions 恰好 1 项；field/command/opcode/subtype 精确；activeSet/status/FPS/picture 显式否定；0x84 行只在该代表项出现 |

两击之间输入逐字段相等由 `XCTAssertEqual(secondInput, firstInput)` 固定，确认来自 coordinator
的 exact 冻结确认账本（不是测试手改 Bool）。

## 4. 红 → 绿实测（非仅声称）

产品修复以 **sha256 保护的备份**还原，并对「替换是否真的发生」加 `assert`（沿用既有教训：
未断言成功替换的还原脚本会输出 "reverted" 却未改文件）：

```
backup: /tmp/c5hr1-assembler.bak  sha256 d97f093b2c0a310caf74f90a7735e5c85156f0d3e90d7da2c4fe37bdac9c8cc9
revert: overwriteSemantic: snapshot.overwriteConfirmed,  ->  ... && (wholeGroup || acceptedUnknown),   [assert count==1]
restore: sha256 复核 == d97f093b...cc9，git status/diff 对该文件为空
```

| 装配体 | 结果 |
|---|---|
| 还原 `&& (wholeGroup \|\| acceptedUnknown)` | **failed**：`testOverwriteSemanticAndEmittedWireForKeyAndLightSchema3Matrix` 3 个代表项全部命中 `确认后 overwriteSemantic 必须为 true`；`testNonWholeGroupKeyAndLightSchema3RequiresThenAccepts` 命中 `key-description 确认后必须 accepted，实得 requiresOverwriteConfirmation`；R5 测试命中 `C5H：确认后必须越过 authority，实得 requiresOverwriteConfirmation` |
| 应用修复（sha 复核） | **passed**（定向 251/251、全量绿） |

即：两个 P1 的新增断言在错误产品语义下**必然变红**，不是恒真断言。

## 5. 门禁

| 门禁 | 结果 |
|---|---|
| 定向（10 个 Studio/Runtime 测试类） | **251 / 251，0 失败**（C5H 为 249，本轮 +2） |
| 全量 Swift 第 1 次 | 1214 / 2 skipped / **1 failure** —— 仅已登记 flake `AhaKeyAgentRuntimeEndpointTests.testConcurrentAppliesFromTwoClientsSerializeAndDrain` |
| 全量 Swift 第 2 次 | 1214 / 2 skipped / **2 failures** —— 两个已登记 flake（同一 Agent concurrency + `AhaKeyRuntimePersistentStoreTests.testRootDeleteRecreateDoesNotLockStaleInode`） |
| 全量 Swift 第 3 次 | 1214 / 2 skipped / **1 failure** —— 同一已登记 Agent concurrency flake |
| 全量 Swift 第 4 次 | **1214 / 2 skipped / 0 failures（全绿）** |
| `swift build -c release --product AhaKeyConfig` | rc=0 |
| `swift build -c release --product ahakeyconfig-agent` | rc=0 |
| `zsh scripts/check-release-identity.sh` | `release identity ok` |
| `git diff --check 9b3fa6a -- ahakeyconfig-mac` | 通过 |

**flake 归因（如实记录，不自行豁免）**：第 1–3 次全量命中的失败项均为既有已登记 flake
（C5GR6/C5GR7/C5GR8/C5H 轮次同一清单）。本轮新增诊断：

- `AhaKeyAgentRuntimeEndpointTests` **隔离复跑 9 次**：7 次 50/50 绿，2 次失败且失败项恒为
  `testConcurrentAppliesFromTwoClientsSerializeAndDrain`（`running != accepted`，串行协调器排队断言）。
  该失败在**完全隔离**（不含本轮任何新测试）下即可复现，且位于本轮零交集的 Agent 模块。
- `AhaKeyRuntimePersistentStoreTests` 隔离复跑 3 次均 91/91 绿；其失败只在全量负载下出现。

结论：全量前三次的红均属既有并发 flake，**不归因于本轮改动**；第 4 次取得任务卡要求的全量绿。
DSH 不声称修复 flake，也不自行豁免；若 Codex 认为仍须另开稳定性卡，DSH 服从调度。

## 6. 测试清单（本轮新增/加固）

| 测试 | 覆盖 |
|---|---|
| `AhaKeyStudioPageInteractionTests.testConfirmedActiveSetOnlyWithWriteConfirmedBaselineDoesNotLoopConfirmation`（加固） | R5 端到端 canonical wire：唯一 `.setActiveSet` + 0x97 + logical/physical set0 + activation + 全部其它维度 none + 显式否定 status/FPS/picture |
| `AhaKeyStudioPageInteractionTests.testNonWholeGroupKeyAndLightSchema3RequiresThenAccepts`（新增） | keyDescription / lightBrightness / lightMapping 三代表项真实 Store→Facade 两击：未确认 requires + 零 apply/ingest；确认后 accepted + schema=3 + wire 精确 |
| `AhaKeyStudioDraftPackageMappingTests.testOverwriteSemanticAndEmittedWireForKeyAndLightSchema3Matrix`（新增） | 同三代表项 plan 层：未确认 semantic=false、确认后 true，并由同一 plan 构造 emitted fingerprint 逐字段断言 |

既有 `testOverwriteSemanticReflectsExactUserConfirmationForNonWholeGroupWrites`（current/rhino activeSet）、
`...ForStatusLineWrite`（writeConfirmed statusLine）、`testWholeGroupPictureStillRequiresConfirmationBeforeEmit`
（whole-group 既有规则）保持不变、继续通过。
