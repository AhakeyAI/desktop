# 32 — C5GR4：执行租约跨 coordinator 生命周期、returned 封闭与取消计数收口

任务卡：`V03-C5-STUDIO-PAGE-COMMIT-COORDINATOR`（ready / C5GR4）
执行 owner：DSH；验收：Codex
基线：`85966b4`（C5GR3 提交）
日期：2026-09-11

## 1. 退审条目与本轮修复

| 编号 | 退审 finding | 修复 |
|---|---|---|
| Standards P1 | 执行 slot 仍属于 View-lifetime coordinator：port 忽略取消时 coordinator 可释放，继任 coordinator 看不到旧 slot，仍可能启动并行写 | 新增 `AhaKeyStudioPageCommitExecutionRegistry`（**app-lifetime**），由 `AhaKeyStudioRuntimeClient` 持有并注入 coordinator；租约、port Task、live identity/revision、trace 与计数全部上移。任一 successor coordinator 的 `start` 看到被占用租约即 `.rejected(.ignoredInFlight)`，直到旧 port 真正返回/抛错 |
| Standards P2 | `AhaKeyStudioPageCommitReturnedResult.init(outcome:)` 接受非法 outcome，Release 降级成 `.noOp` | 删除该入口与 `assertionFailure` 兜底；改为 `init(_ result: AhaKeyStudioPageCommitResult)` 穷举 6 个 case，**无兜底、无降级**。非法 outcome 在源码上不可传入 |
| Standards P2 | 取消请求与旧结果结算各加一次 `supersededCount`，同一次取消被双计且 trace 语义混杂 | 计数拆分：`cancelRequestedCount`（每次取消恰一次）与 `supersededCount`（**仅** identity 变化）。trace 拆成 `.cancelRequested` / `.cancelSettled` typed case，与 `.superseded` 完全分离 |
| 卡片原文 | 不得用 static global 无生命周期注册表 | 注册表由 `AhaKeyStudioRuntimeClient` 持有（`let pageCommitExecutions`），随 Store 生命周期；View 经 `init` 注入 coordinator |

## 2. 执行租约的所有权上移

```text
以前：View → @StateObject coordinator → inFlight slot / Task / trace
现在：View → @StateObject coordinator ──┐
                                        ├─→ AhaKeyStudioRuntimeClient.pageCommitExecutions（app-lifetime）
       successor coordinator ───────────┘        ├─ lease（port 执行占用）
                                                 ├─ currentIdentity / observationRevision
                                                 ├─ trace + 计数
                                                 └─ port Task（不捕获 registry 强引用）
```

- 租约由注册表 `claim / release` 管理，**不随 coordinator 释放而消失**。
- settlement 由注册表拥有；coordinator 通过 `AhaKeyStudioPageCommitExecutionDelegate` 接收回调，只负责 ledger 消费与投影。
- 若发起 attempt 的 coordinator 已释放（`ownerToken` 不匹配），注册表只做 cleanup 并释放租约，不消费任何人的 ledger、不投影旧 result。

## 3. 相对 C5GR3 的三处行为变更（已确认项，请 Codex 复核）

| 项 | C5GR3 | C5GR4 | 理由 |
|---|---|---|---|
| `deinit` 取消 Task | coordinator `deinit { inFlightTask?.cancel() }` | **移除**。Task 归注册表，必须存活到 port 结算后释放租约 | 若随 coordinator 取消，租约将永久泄漏（正是本次 P1）。port 调用本身就是协作式取消无法中断的 |
| `isSubmitting` | 取消时立即置 false，租约另存 | 直接**镜像租约占用**（cancel-after-port 期间仍为 true） | 诚实反映「仍有未结算副作用」；且 successor coordinator 必须看到禁用态。卡片允许「解除 UI submitting 可选」，取更保守的一侧 |
| 取消 trace | `.cancelled(portInvoked:)` | `.cancelRequested` + `.cancelSettled` | 卡片要求区分请求与结算，且不与 identity superseded 混算 |

## 4. returned 类型封闭

```swift
init(_ result: AhaKeyStudioPageCommitResult) {
    switch result {
    case .noOp: self = .noOp
    case .requiresOverwriteConfirmation: ...
    case .missingTrustedPageCache: ...
    case .unsupportedProfile: ...
    case .unsupportedPage: ...
    case .accepted: self = .accepted
    }
}
```

`AhaKeyStudioPageCommitResult` 恰有 6 个 case，因此这是穷举映射：既没有接受 `outcome` 的宽入口，也没有 `assertionFailure + .noOp` 的 Release 降级。测试 `testReturnedResultMapsEveryCommitResultWithoutFallback` 逐对断言 6 个映射。

## 5. 取消 vs identity 变化的 typed 分离

| 路径 | trace | `cancelRequestedCount` | `supersededCount` |
|---|---|---|---|
| 用户取消（before/after port） | `.cancelRequested` → `.cancelSettled` | +1（恰一次） | 0 |
| live identity 变化 | `.superseded` | 0 | +1 |

`testCancelAndIdentitySupersedeProduceDifferentTypedEvents` 分别跑两条路径，断言两条 trace 集合互不出现、两个计数不串。

## 6. 测试

coordinator 专项由 30 项增至 **34 项**。本轮新增：

- `testSuccessorCoordinatorSeesInheritedLeaseAndRejectsParallelStart`：A `start→portInvoked→cancel→dealloc`；断言 A 能释放、租约仍在；successor B 复用同一 registry → `isSubmitting==true`、`start` rejected、`portCallCount` 仍 1；旧 port 返回后租约释放，B 才可 `start`。
- `testCancelIncrementsCancelCounterOnlyOnceAndNeverSuperseded`：取消计一次、`supersededCount` 恒 0，结算不重复计数。
- `testCancelAndIdentitySupersedeProduceDifferentTypedEvents`：两条路径的 typed trace 与计数互不混淆。
- `testReturnedResultMapsEveryCommitResultWithoutFallback`：6 个 commit result 的穷举映射。
- 原 30 项中的取消/穷举表按新的 typed case 更新（穷举表 16 行覆盖 8 个 case）。

## 7. 门禁结果

| 门禁 | 结果 |
|---|---|
| 定向（10 个 Studio/Runtime 测试类） | **222 / 222，0 失败** |
| coordinator 专项 | **34 / 34，0 失败** |
| 全量 Swift | **1185 tests / 2 skipped / 0 failures**（首次即通过，无 flake） |
| App Release | rc=0 |
| Agent Release | rc=0 |
| `check-release-identity.sh` | `release identity ok` |
| C5GR4 改动范围 `git diff --check` | 通过 |

## 8. 已确认项未被破坏

per-attempt record、双次 pre-port fence、cancel-before-port 零调用、no shared booleans、structured trace、`portInvoked`、single frozen input、双 ledger/active-only、点击路径无 observe/status/Task、冻结 pageID。

不同设备不并行：注册表维护**单一**租约（不按 device 分槽），因此不放大现有 single-in-flight / device FIFO 策略。

## 9. 本轮仍不能证明的事

跨 coordinator 租约、typed 取消区分与 returned 封闭均为 **host 可判定**；R4 的真实停点仍须下一次 HIL 的 trace 判定。本卡第 50 行口径不变。

## 10. 白名单与未做项

改动文件：

- `ahakeyconfig-mac/Sources/Models/AhaKeyStudioPageCommitCoordinator.swift`（新增注册表 + coordinator 收窄）
- `ahakeyconfig-mac/Sources/Models/AhaKeyStudioRuntimeStore.swift`（Store 持有并暴露注册表——卡片明确要求「由 `AhaKeyStudioRuntimeClient` 持有并注入」）
- `ahakeyconfig-mac/Sources/Views/AhaKeyStudioView.swift`（注入注册表）
- `ahakeyconfig-mac/Tests/AhaKeyConfigProtocolTests/AhaKeyStudioPageCommitCoordinatorTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigProtocolTests/AhaKeyStudioPageInteractionTests.swift`
- 本任务卡执行记录、本 evidence、`board.md` append-only 记录

未做 / 未触碰：C2 assembler、C3 schema/WAL/CAS/executor、Agent/BLE、ReleaseIdentity、安装器、固件；未签名、未安装、未启动 HIL、未写设备、未刷机、未擦 EEPROM、未断电、未 push。提交不含 `board.md`/`queue.md` 的既有他人 diff。
