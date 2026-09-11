# 30 — C5GR2：结构化 trace、同步生命周期与点击路径收口

任务卡：`V03-C5-STUDIO-PAGE-COMMIT-COORDINATOR`（ready / C5GR2）
执行 owner：DSH；验收：Codex
基线：`91c7aa8`（C5GR1 提交）
日期：2026-09-11

## 1. 退审条目与本轮修复

| 编号 | 退审 finding | 修复 |
|---|---|---|
| Spec P1 | View 在点击路径用 frozen input 调 `observeIdentity`，使 production pre-port guard 恒真 | 移除点击路径的 `observeIdentity`；live identity **只**由 `onAppear` 与 `.onChange(overwriteConfirmationIdentity)` 推进。`onAppear` 在 refresh / intent context 就绪后显式 observe 当前 identity |
| Spec P1 | View 在 start 前写「正在提交…」，而 superseded/rejected 不更新文案，留下永久假提交 | 点击路径**不再写任何 status**；提交中只由 coordinator `isSubmitting` 与按钮 label 投影；valid returned/failed 才更新结果文案，stale/rejected 不触碰 status |
| Standards P2 | trace 由三个自由字段组成，产品类型可构造矛盾状态；反向矩阵只抽查 7 个字符串 | 改为 associated-case `AhaKeyStudioPageCommitTraceEvent`：`phase` / `portInvoked` / `category` 全部**派生**，矛盾组合不可构造；测试改为对全部 case 的**完全枚举**（见 §2） |
| Standards P2 | coordinator 把内部 `Task` 暴露给 View，View 又建第二个 Task 等待 | `start` 返回值改为 `AhaKeyStudioPageCommitStartResult { started, rejected(projection) }`，**不含 `Task`**；coordinator 自持 `inFlightTask`，终结结果经 `lastProjection` + `projectionRevision` 发布，View 用 `onChange` 消费，既不建 Task 也不需要闭包 |
| Standards P3 | `&+=` 理论回绕 | 全部改为 `Self.checkedIncrement`（`value + 1`，checked / fail-closed，溢出即 trap，绝不回绕） |
| Spec P2 / 卡片 L125 | trace 缺 `portInvoked`，无法区分「内部 Task 未调度」与「port 已进入但挂起」 | 新增 `.portInvoked` phase 与事件：`began` 只证明 Button 同步进入；`portInvoked` 证明内部 Task 已实际调用 port |
| 卡片 L126 | 未定义页面关闭/对象释放时的 cancellation 策略 | 新增 `cancelInFlight()`：取消在途 Task、清 in-flight、解除 `isSubmitting`、记录 `.cancelled`；`isStale` 纳入 attempt 身份，迟到的 port 结果不再被消费或投影。View 在 `onDisappear` 调用 |

## 2. 结构化 trace（矛盾的组合不可构造）

```swift
enum AhaKeyStudioPageCommitTraceEvent {
    case began(sequence:pageID:confirmed:)
    case portInvoked(sequence:pageID:confirmed:)
    case returned(sequence:pageID:confirmed:category:)
    case failed(sequence:pageID:confirmed:)
    case superseded(sequence:pageID:confirmed:portInvoked:)
    case rejected(sequence:pageID:)
    case cancelled(sequence:pageID:confirmed:portInvoked:)
}
```

派生表（由测试**逐 case 完全枚举**断言，非抽样）：

| case | phase | portInvoked | category | confirmed |
|---|---|---|---|---|
| `began` | `.began` | `false` | `.pending` | 关联值 |
| `portInvoked` | `.portInvoked` | `true` | `.pending` | 关联值 |
| `returned(accepted)` | `.returned` | `true` | `.accepted` | 关联值 |
| `returned(noOp)` | `.returned` | `true` | `.noOp` | 关联值 |
| `returned(requires…)` | `.returned` | `true` | `.requiresOverwriteConfirmation` | 关联值 |
| `returned(missingTrustedPageCache / unsupportedProfile / unsupportedPage)` | `.returned` | `true` | 同名 | 关联值 |
| `failed` | `.failed` | `true` | `.failed` | 关联值 |
| `superseded(portInvoked:false)` | `.superseded` | `false` | `.superseded` | 关联值 |
| `superseded(portInvoked:true)` | `.superseded` | `true` | `.superseded` | 关联值 |
| `rejected` | `.rejected` | `false` | `.inFlightRejected` | `false`（未进入 attempt） |
| `cancelled(portInvoked:false/true)` | `.cancelled` | 关联值 | `.cancelled` | 关联值 |

`testTraceEventDerivedFieldsAreExhaustivelyConsistent` 断言这张表，并断言枚举覆盖全部 7 个 phase；`testRuntimeTraceEventsStayWithinEnumeratedPhases` 断言运行期产生的事件全部落在该类型集合内，且「port 未调用时不得出现结果类别」。

## 3. `began` / `portInvoked` 的 HIL 判读

| 观测 | 结论 |
|---|---|
| 无 `began` | Button action 未触发（同步进入前就断了） |
| 有 `began`、无 `portInvoked` | 内部 Task 未调度 / 生命周期停点 |
| 有 `portInvoked`、无 `returned` | port 已进入但挂起 |
| 有 `returned(confirmed=true)` 但设备无 `0x97` | 停点在 port 之后（Runtime/设备层） |

对应测试：`testBeganWithoutPortInvokedMeansInternalTaskNotScheduled`、`testPortInvokedWithoutReturnedMeansPortHung`。

## 4. 生命周期与取消策略

- `start` 同步建立 attempt 并落 `began`，然后由 coordinator 自己 `Task { @MainActor ... }` 执行 port；返回值不含 `Task`。
- 终结结果经 `lastProjection` + `projectionRevision`（单调 checked 递增）发布；重复同值投影也能被 View 观察到，且 View 无需闭包、无需建 Task（也避免与 `@StateObject` 形成引用环）。
- `cancelInFlight()`：页面关闭时取消在途 attempt，立即解除 `submitting` 与 in-flight；迟到的 port 结果因 `inFlightAttempt != attempt` 被判 stale，只产生 `.superseded`，不消费、不写 `lastOutcome`。
- View 在 `.onDisappear` 调用 `cancelInFlight()`。

## 5. 测试

coordinator 专项由 20 项增至 **26 项**。本轮新增/改写：

- `testClickPathDoesNotPublishLiveIdentityNorWriteStatusNorCreateTask`（静态门）：`writeCurrentPage` 函数体内不得出现 `observeIdentity`、不得出现「正在提交」、不得出现 `Task {` / `Task<`，且必须调 `pageCommitCoordinator.start(`。
- `testTraceEventDerivedFieldsAreExhaustivelyConsistent`：14 行穷举表，覆盖全部 case 的确认/未确认与 port 前后分支。
- `testRuntimeTraceEventsStayWithinEnumeratedPhases`：运行期事件落在枚举集合内且语义自洽。
- `testBeganWithoutPortInvokedMeansInternalTaskNotScheduled` / `testPortInvokedWithoutReturnedMeansPortHung`：新增 `portInvoked` 的两种停点。
- `testCancelInFlightClearsSubmittingAndLateResultIsNotConsumed`：取消后立即解除 submitting、迟到 accepted 不被消费、取消后可立刻开始新 attempt。
- `testCancelBeforePortInvokedAlsoReleasesSubmitting`：`began` 后、port 前取消。
- `testCheckedIncrementDoesNotWrap`：checked increment 的基线行为。
- `testStartIsSynchronous…` 更新为不加 `Task` 的事件等待，并断言 rejected 本身也是一次终结投影事件。
- 原字符串反向矩阵两测删除（被关联类型 + 完全枚举取代）。

## 6. 门禁结果

| 门禁 | 结果 |
|---|---|
| 定向（10 个 Studio/Runtime 测试类） | **214 / 214，0 失败** |
| coordinator 专项 | **26 / 26，0 失败** |
| 全量 Swift | **1177 tests / 2 skipped / 0 failures**（首次即通过） |
| App Release | rc=0 |
| Agent Release | rc=0 |
| `check-release-identity.sh` | `release identity ok` |
| C5GR2 改动范围 `git diff --check` | 通过 |

## 7. 已冻结项未被破坏

同步 `began`、coordinator 内聚双 ledger、single frozen input（且与展示 identity 同源）、post-await stale 不消费、冻结 pageID 投影、recording/production port、非敏感 bounded trace（环形 64）、active-only mapping（真实 mapping→Facade 用例经 `start` 走通）。

## 8. 本轮仍不能证明的事

结构化 trace、同步生命周期、取消策略与点击路径收口都是 **host 可判定**的；R4 的真实停点仍须下一次 HIL 的 trace 判定。本卡第 50 行口径不变：host 全绿不等于 HIL 症状已修复。

## 9. 白名单与未做项

改动文件：

- `ahakeyconfig-mac/Sources/Models/AhaKeyStudioPageCommitCoordinator.swift`
- `ahakeyconfig-mac/Sources/Views/AhaKeyStudioView.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigProtocolTests/AhaKeyStudioPageCommitCoordinatorTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigProtocolTests/AhaKeyStudioPageInteractionTests.swift`
- 本任务卡执行记录、本 evidence、`board.md` append-only 记录

未做 / 未触碰：C2 assembler、C3 schema/WAL/CAS/executor、Agent/BLE、ReleaseIdentity、安装器、固件；未签名、未安装、未启动 HIL、未写设备、未刷机、未擦 EEPROM、未断电、未 push。提交不含 `board.md`/`queue.md` 的既有他人 diff。
