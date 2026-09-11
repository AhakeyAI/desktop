# 31 — C5GR3：取消 fence、per-attempt 执行占用与 returned 类型封闭

任务卡：`V03-C5-STUDIO-PAGE-COMMIT-COORDINATOR`（ready / C5GR3）
执行 owner：DSH；验收：Codex
基线：`26e955b`（C5GR2 提交）
日期：2026-09-11

## 1. 退审条目与本轮修复

| 编号 | 退审 finding | 修复 |
|---|---|---|
| Spec P1 | `start` 到内部 Task 调度之间缺少第二次 identity/cancellation pre-port 检查 | 新增 `admitPortEntry(_:)`：内部 Task 在**任何** `portCallCount`、`portInvoked` trace 或 port 调用之前，于 MainActor 同一 transition 上核 `Task.isCancelled` + exact in-flight execution + `observationRevision` + `currentIdentity`。失败只记 superseded/cancelled(`portInvoked=false`)，port 计数为 0 |
| Standards P1 | cancel 不构成 port 副作用 fence：cancel-before-schedule 后旧 Task 仍可能调用 Store | 取消后旧 Task 即使被调度，`admitPortEntry` 先判 `inFlight === execution`；已被释放则直接返回、零调用零 trace。controller 侧另有 `cancelRequested` 双重保险 |
| Standards P1 | cancel-after-port 立即释放 single-in-flight，可能出现新旧写并行 | port 已进入时**保留** per-attempt 执行占用（`inFlight` 不清），直到旧 port 真正返回/抛错；期间新的 `start` 一律 `.rejected(.ignoredInFlight)`。`Task.cancel()` 不再被当作「副作用已停止」的证明 |
| Standards P2 | `.returned(category:)` 仍接受完整 category enum | 新增 `AhaKeyStudioPageCommitReturnedResult`（仅 accepted / noOp / requires / missingTrustedPageCache / unsupportedProfile / unsupportedPage）；`.returned` 只接受该类型，`returned(pending/failed/superseded/rejected/cancelled)` **编译期不可构造** |
| Standards P2 | Task 与 coordinator 在 port 永久挂起时可能形成保留环 | port 调用段**不捕获 coordinator**：`start` 内 `Task { @MainActor [weak self] in ... }`，仅在 `self?.admitPortEntry(...)`（同步）与 `self?.settle(...)`（await 之后）处短暂强持有；await 期间只持有 per-attempt execution 与 port。新增 `deinit { inFlightTask?.cancel() }` |
| 卡片原文 | in-flight 状态收成 per-attempt typed record | 新增 `@MainActor final class AhaKeyStudioPageCommitExecution`：attempt / identity / revisionAtSubmit / sequence / pageID / confirmed / snapshot / retryResidual / port + `portInvoked` / `cancelRequested`。旧 Task 不可能改写新 attempt 的状态 |

## 2. 取消语义（本轮相对 C5GR2 的**语义变更**，请 Codex 确认）

| 路径 | C5GR2 行为 | C5GR3 行为 |
|---|---|---|
| cancel-before-port | 立即释放 slot | 立即释放 slot（不变）——pre-port fence 保证零 port 调用 |
| cancel-after-port | 立即释放 slot，允许新 start | **保留 slot**，新 start 被 rejected，直到旧 port 真正返回/抛错才释放 |
| 取消结算结果 | `.superseded` | `.cancelled`（`.superseded` 保留给 live identity 变化路径） |

理由：`Task.cancel()` 是协作式的，port 已进入后无法证明副作用已停止；立即释放 slot 会让新旧写并行。

UI 侧 `isSubmitting` 在取消时**立即**置 false（卡片允许「解除 UI submitting 可选」），但执行占用保留——两者分离，因此既不会永久显示「提交中」，也不会允许并行写。

trace 序列：`began → portInvoked → cancelled(请求) → superseded(结算)`。

## 3. 双次 pre-port fence

| 时机 | 检查 | 失败后果 |
|---|---|---|
| `start` 同步阶段 | `currentIdentity == input.confirmationIdentity` | 零 port，`.rejected(.superseded)` |
| 内部 Task 调度后、port 前 | `!Task.isCancelled`、`!cancelRequested`、`inFlight === execution`、`observationRevision == revisionAtSubmit`、`currentIdentity == identity` | 零 port、零 portCall 计数，trace 记 superseded/cancelled(`portInvoked=false`) |

第二条 fence 覆盖的正是「start 之后、Task 真正运行之前」的窗口。

## 4. returned 类型封闭

```swift
enum AhaKeyStudioPageCommitReturnedResult: String {
    case accepted, noOp, requiresOverwriteConfirmation,
         missingTrustedPageCache, unsupportedProfile, unsupportedPage
}
case returned(sequence:pageID:confirmed:result: AhaKeyStudioPageCommitReturnedResult)
```

`AhaKeyStudioPageCommitReturnedResult(outcome)` 的初始化器对非返回类 outcome 采用 `assertionFailure` + 不可达兜底，因此产品代码也不会把非返回结果塞进 `.returned`。

测试 `testTraceEventDerivedFieldsAreExhaustivelyConsistent` 断言 6 个返回结果**全部**被枚举，且集合恰好等于这 6 个。

## 5. 测试

coordinator 专项由 26 项增至 **30 项**。本轮新增：

- `testIdentityChangeBeforeInternalTaskSchedulingCallsNoPort`：`start(A)` 后、Task 调度前 observe B → 零 port、零计数、trace `superseded(portInvoked=false)`。
- `testCancelBeforePortInvokedCallsNoPort`：`began` 后取消 → 释放 slot，旧 Task 被调度后仍零 port 调用。
- `testCancelAfterPortInvokedKeepsSlotUntilPortReturns`：取消后 `inFlight != nil`、新 `start` 被 `.rejected(.ignoredInFlight)`；旧 port 返回后只做 cleanup（`.cancelled`、不写 `lastOutcome`）、释放 slot、新 `start` 恢复可用。
- `testCancelledLateResultDoesNotMutatePendingOrIntent`：取消后的旧 accepted 返回不改动 pending / edit intent / `lastOutcome`。
- `testCoordinatorDeallocatesDespiteHungIgnoringCancelPort`：`weak` coordinator 在 port 忽略取消且永久挂起时仍必须释放（无保留环）。
- 原 `testCancelInFlight…` 按上述语义变更改写（`.superseded` → `.cancelled`，并新增「新 start 必须被 rejected」断言）。

## 6. 门禁结果

| 门禁 | 结果 |
|---|---|
| 定向（10 个 Studio/Runtime 测试类） | **218 / 218，0 失败** |
| coordinator 专项 | **30 / 30，0 失败** |
| 全量 Swift 第 3 次 | **1181 tests / 2 skipped / 0 failures** |
| App Release | rc=0 |
| Agent Release | rc=0 |
| `check-release-identity.sh` | `release identity ok` |
| C5GR3 改动范围 `git diff --check` | 通过 |

### 全量前两次的 flake（如实记录，非本轮引入）

- `AhaKeyAgentTests.AhaKeyAgentRuntimeEndpointTests.testConcurrentAppliesFromTwoClientsSerializeAndDrain`（第 1 次失败，第 2/3 次通过；隔离复跑通过）。
- `AhaKeyConfigSharedTests.AhaKeyRuntimePersistentStoreTests.testRootDeleteRecreateDoesNotLockStaleInode`（第 1、2 次 `TIMEOUT` ≠ `BLOCKED`，第 3 次通过；隔离复跑通过）。这是 Codex 在 C4R13/C4R14 已点名的既有稳定性问题。

两者与本轮改动零文件交集，判定为 full-suite 并发下的既有 flake，不声称由本轮修复或引入。

## 7. 已确认项未被破坏

点击路径无 observe/status/Task（静态门）、onAppear live identity、同步 began、post-await superseded、冻结 pageID 投影、`portInvoked` 判读、checked increment、双 ledger 内聚、single frozen input、recording/production port、非敏感 bounded trace、active-only mapping。

## 8. 本轮仍不能证明的事

取消语义、执行占用保留、retain-cycle 释放与 returned 类型封闭均为 **host 可判定**；R4 的真实停点仍须下一次 HIL 的 trace 判定。本卡第 50 行口径不变。

## 9. 白名单与未做项

改动文件：

- `ahakeyconfig-mac/Sources/Models/AhaKeyStudioPageCommitCoordinator.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigProtocolTests/AhaKeyStudioPageCommitCoordinatorTests.swift`
- 本任务卡执行记录、本 evidence、`board.md` append-only 记录

（View 本轮零改动——取消策略与 pre-port fence 全部收在 coordinator 内部。）

未做 / 未触碰：C2 assembler、C3 schema/WAL/CAS/executor、Agent/BLE、ReleaseIdentity、安装器、固件；未签名、未安装、未启动 HIL、未写设备、未刷机、未擦 EEPROM、未断电、未 push。提交不含 `board.md`/`queue.md` 的既有他人 diff。
