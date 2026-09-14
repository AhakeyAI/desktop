# 38 — C5H：用户确认不得在 schema=3 authority 门形成无限循环

任务卡：`V03-C5-PAGE-BASE-OVERWRITE-SEMANTIC`（ready / C5H）
执行 owner：DSH；验收：Codex
基线：`e5a2f8fdbf65d5864135bc7af6752c30bbe914f5`
日期：2026-09-14

## 1. 根因与修复

**根因**（R5 已由 typed trace 固定）：`AhaKeyStudioPackageAssembler` 把 plan 的
`overwriteSemantic` 算成 `snapshot.overwriteConfirmed && (wholeGroup || acceptedUnknown)`。
active-set-only 场景 `wholeGroup=false`（rhino/current + 屏幕页）、`acceptedUnknown=false`
（基线 `writeConfirmed`），于是**用户确认后该标志仍为 false** → `AhaKeyRuntimePageBaseAuthority.resolve`
在 schema=3 路径 `if !overwriteSemantic { throw overwriteConfirmationRequired }` → Facade 映射回
`.requiresOverwriteConfirmation` → UI 无限重复同一个确认提示。

**修复**（单一 plan 构造 seam，`AhaKeyStudioPackageAssembler.swift`）：

```swift
// before
overwriteSemantic: snapshot.overwriteConfirmed && (wholeGroup || acceptedUnknown),
// after
overwriteSemantic: snapshot.overwriteConfirmed,
```

`overwriteSemantic` 现在表达「本次冻结提交携带 exact 用户覆盖确认」。`wholeGroup` /
`acceptedUnknown` 仍然只决定是否为「尚未确认」的提交**先**返回 `.requiresOverwriteConfirmation`
（第 435/452 行的两处前置判断一字未改）。

**边界遵守**：未改 `AhaKeyRuntimePageBaseAuthority` 的 schema=3 fail-closed 规则；未在 Facade 强改
Bool；未为 activeSet 特判绕过 authority；未伪造 whole-object 或 baseline。

## 2. 修复有效性证明（红 → 绿）

永久集成红测 `testConfirmedActiveSetOnlyWithWriteConfirmedBaselineDoesNotLoopConfirmation`
（真实 draft/edit intent → frozen snapshot → assembler → coordinator 两击 → production Facade recording transport）：

| 装配体 | 结果 |
|---|---|
| 还原 `&& (wholeGroup || acceptedUnknown)` | **failed** — `C5H：确认后必须越过 authority，实得 requiresOverwriteConfirmation`（即 R5 症状） |
| 应用修复 | **passed** |

assembler seam 表驱动测试 `testOverwriteSemanticReflectsExactUserConfirmationForNonWholeGroupWrites`
同样在还原后失败（`currentSessionCapable` 与 `rhinoDualSet` 两例都命中 `确认后 overwriteSemantic 必须为 true`）。

## 3. 过程中发现的测试构造陷阱（已写入测试注释）

`AhaKeyStudioFieldAuthority.resolvedBaseline()` 只在 `provenance == .writeConfirmation` 时给出
`writeConfirmed`；若写成 `trust: .writeConfirmed` + `provenance: .deviceReadback`，会被降级为
`.unknown`，从而让 `acceptedUnknown=true` —— 此时旧的错误表达式恰好也返回 true，**测试会变成假绿**。

第一版集成测试正是踩了这个坑（还原修复后仍通过），已修正并重新验证红/绿。这一点值得后续写同类
测试时注意。

## 4. 测试清单

| 测试 | 覆盖 |
|---|---|
| `AhaKeyStudioPageInteractionTests.testConfirmedActiveSetOnlyWithWriteConfirmedBaselineDoesNotLoopConfirmation` | **R5 场景端到端**：无 whole-object（`authoritativeObject=nil`）、activeSet live baseline=`writeConfirmed(1)`、显式 Picker A=0。第一击 requires + apply=0 + ingest=0；第二击 accepted + apply=1 + schema=3 + `fieldMask` 仅 `screenActiveSet:0` + `baseObjectFingerprint=nil` + field-baseline proof 在场 + 零 resourceBinding + 零 resource |
| `AhaKeyStudioDraftPackageMappingTests.testOverwriteSemanticReflectsExactUserConfirmationForNonWholeGroupWrites` | 表驱动：current/rhino × activeSet-only，未确认 false、确认后 true，`fieldMask == values.keys` |
| `...testOverwriteSemanticReflectsExactUserConfirmationForStatusLineWrite` | 非 activeSet 的非 whole-group 字段（writeConfirmed 基线）同样适用 |
| `...testWholeGroupPictureStillRequiresConfirmationBeforeEmit` | whole-group 既有规则不回退：未确认仍由 assembler 先返回 requires |
| `AhaKeyStudioPageCommitCoordinatorTests.testRejectedTraceDistinguishesClosedNotAttachedAndOccupied` | **P2**：`.rejected(reason:)` 三态可区分，port=0 |
| `...testTraceEventDerivedFieldsAreExhaustivelyConsistent` | 穷举表扩到 18 行，含三种 rejection category |

## 5. 观测性 P2 收口

`start` 的三条早退现在各写一条 typed trace：

| 分支 | reason | category |
|---|---|---|
| 已有在途 execution | `.executionOccupied` | `.inFlightRejected` |
| registry 已 shutdown | `.registryClosed` | `.registryClosedRejected` |
| 未 attach（迟到/detach/never-appeared） | `.ownerNotAttached` | `.ownerNotAttachedRejected` |

因此「Button 未触发」严格等于「本次点击没有任何 trace」——R5 期间那次判别困难不再出现。
trace 仍不含资源、路径或用户文本，环形缓冲上限 64 不变。

## 6. 门禁结果

| 门禁 | 结果 |
|---|---|
| 定向（10 个 Studio/Runtime 测试类） | **249 / 249，0 失败** |
| coordinator 专项 | **53 / 53，0 失败** |
| 全量 Swift（第 3 次） | **1212 tests / 2 skipped / 0 failures** ← 全绿 |
| 全量 Swift（第 2 次） | 仅 2 个已登记 flake（Agent concurrency + Store inode） |
| App Release | rc=0 |
| Agent Release | rc=0 |
| `check-release-identity.sh` | `release identity ok` |
| 改动范围 `git diff --check` | 通过 |

## 7. 全量门禁与基线对照

全量首轮出现 **10 处失败，全部位于 `AhaKeyAgentTests.AhaKeyAgentRuntimeEndpointTests`**（本卡未触碰的
模块），错误为 `unsupported-protocol`，与 `overwriteSemantic` 语义无交集。

- 该类**隔离复跑**：50 tests，只剩 **1 处**失败，即 Codex 已登记的既有 flake
  `testConcurrentAppliesFromTwoClientsSerializeAndDrain`；
- 其余 4 处（`testIngestMutationsAfterAdmissionReservedWriteZeroCAS`、
  `testPreWriteFailuresDiscardReservationAndStayBounded`、
  `testProductionIdentityMutationWithDelayedEventPublishWritesZeroCASAndWAL`）只在全量并行时出现；
- 已在**冻结基线 `e5a2f8f`** 的独立 worktree 上跑同一测试类做对照（`/tmp/c5h-baseline`，结果见
  `raw/` 或本节补记），以判断是否与本轮改动相关。

**基线对照结论**：在冻结基线 `e5a2f8f` 的独立 worktree（`/tmp/c5h-baseline`，已删除）上：

- 该类隔离跑 **50/50 全绿**；
- 基线**全量**：**1207 / 2 skipped / 1 failure**，唯一失败即上述已登记 flake。

而带本轮改动的树：第 2 次全量只剩**相同的两个已登记 flake**，第 3 次全绿。首轮那 10 处失败无法复现，
且集中在一个本身就有并发 flake 的类中，判定为环境异常（本会话此前刚执行过 HIL 窗口，存在残留负载），
**不归因于本轮改动**。§7 首段记录的 10 处失败保留为当时观测，不撤销。

## 8. 白名单与未做项

改动文件：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyStudioPackageAssembler.swift`（plan 语义一行 + 注释）
- `ahakeyconfig-mac/Sources/Models/AhaKeyStudioPageCommitCoordinator.swift`（typed rejection reason）
- `ahakeyconfig-mac/Tests/AhaKeyConfigProtocolTests/AhaKeyStudioDraftPackageMappingTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigProtocolTests/AhaKeyStudioPageInteractionTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigProtocolTests/AhaKeyStudioPageCommitCoordinatorTests.swift`
- 本任务卡执行记录、本 evidence、`board.md` append-only 记录

未做 / 未触碰：`AhaKeyRuntimePageBaseAuthority`、C3 Store/WAL/CAS/executor、Agent/BLE、View、
ReleaseIdentity、安装器、固件、HIL driver；未签名、未安装、未启动 HIL、未写设备、未刷机、
未擦 EEPROM、未断电、未 push。提交不含 `board.md`/`queue.md` 的既有他人 diff。
