# 33 — C5GR5：owner capability、幂等取消与生命周期收口

任务卡：`V03-C5-STUDIO-PAGE-COMMIT-COORDINATOR`（ready / C5GR5）
执行 owner：DSH；验收：Codex
基线：`c6aa890`（C5GR4 提交）
日期：2026-09-11

## 1. 退审条目与本轮修复

| 编号 | 退审 finding | 修复 |
|---|---|---|
| Standards P1 | 共享 registry 缺少 owner capability：`attach` 覆盖唯一 weak delegate，`observe/start/cancel` 均未校验 owner；迟到 `onDisappear` 或并存窗口可取消/supersede 他人执行；completion 还会被路由给 successor 后因 token 不匹配而丢弃 | 引入 `AhaKeyStudioPageCommitOwnerCapability`：`activate/deactivate` 管理 active capability；`observeIdentity`/`start` 只允许 exact active owner；`requestCancel`/`settleCancelBeforePort` 只允许 **lease 的 owner capability**；**每个 capability 独立 observation**，successor 的观察不影响 inherited execution；completion/discard 路由给 execution 冻结的 originating **weak** delegate |
| Standards P2 | 重复取消会重复计数与重复 trace | `requestCancel` 幂等：`lease.cancelRequested` 已置位时 no-op（不计数、不追加 trace）。一次 `.cancelRequested`、一次 `.cancelSettled` |
| Standards P2 | Hung port 仍形成 `client → registry → execution → port → client` 闭环 | ①生产 port 改为**弱持有** client（`weak var store`），client 已释放时 fail-closed 抛 `runtimeOffline`；②新增显式 `registry.shutdown()`：fence 新请求、放弃在途租约、取消 port Task |

## 2. Owner capability 的边界

| 操作 | 校验 | 效果 |
|---|---|---|
| `observeIdentity(_:by:)` | `activeCapability == capability` | 迟到/已 detach 的 owner 不得推进 live observation |
| `start(_:port:)` | 同上 + `lease == nil` | 非 active owner 一律 rejected |
| `requestCancel(by:)` | `lease.ownerCapability == capability` | **只有发起者能取消自己的 attempt**；并存窗口 / 迟到 onDisappear 无法取消他人 |
| `settleCancelBeforePort(_:by:)` | 同上 | 同上，且重复调用因租约已释放而 no-op |
| completion / discard 路由 | `execution.originator`（weak） | origin 已释放则只做 cleanup，**不交给无关 successor** |

**多窗口 / 迟到 handoff 规则**（写入注册表文档注释）：

1. 同一 Store 只允许一个 active capability；新 coordinator `activate` 即接管观察权。
2. 继任者可以观察 inherited occupancy（`isSubmitting` / `hasInheritedExecution`），但**不得取消或 supersede** inherited execution。
3. 每个 capability 的 observation 独立存储；successor 改变自己页面的 identity 不会 stale 掉前一个 owner 的在途写。
4. 只有 originating owner 能取消自己的 attempt；origin 消失后该 attempt 只能自然结算（port 返回/抛错）。
5. `shutdown()` 是唯一的强制收口路径，由 client/registry 释放或停机时调用。

## 3. 实现过程中发现并修复的一个真实缺陷

把 observation 改成 per-capability 后，`revision` 用 `Self.checkedIncrement(revisionCounter)` 赋值但**没有把返回值写回计数器**（`checkedIncrement` 是纯函数），导致 revision 恒为 1，A→B→A 往返不再失效。

被既有测试 `testStaleRoundTripBToADuringAwaitStillSupersedes` 立刻抓住，已改为先写回计数器再取用。这条正是「identity 回绕也必须失效」的守护测试，说明该断言有实际价值。

## 4. 生命周期契约

```text
client ──strong──▶ registry ──strong──▶ execution ──strong──▶ port
   ▲                                                          │
   └────────────────── weak（不再闭环）────────────────────────┘
```

- 生产 port 的 `store` 为 `weak`；client 释放后 port 调用的下一次 attempt 直接 fail-closed。
- `shutdown()` 在 port 挂起且忽略取消时仍能释放租约，并把 capability/observation 一并清空。
- port Task 段不捕获 registry 强引用（`[weak self]` + 仅同步段持强引用），await 期间只持 execution 与 port。

## 5. 测试

coordinator 专项由 34 项增至 **39 项**，交互测试 +1。本轮新增：

- `testForeignCapabilityCannotCancelOrSupersedeInheritedExecution`：并存窗口下 foreign **不能**取消（`cancelRequestedCount` 仍 0）、**不能** supersede（即使 observation identity 不同）；owner 自己取消仍有效；completion 路由回 owner，`foreign.lastProjection == nil`、`supersededCount == 0`。
- `testLateOnDisappearFromDetachedOwnerCannotCancelOtherOwner`：已 detach 的 owner 迟到 `cancelInFlight` 不影响新 owner 租约；detach 后其 `start` 也 rejected。
- `testRepeatedCancelAfterPortIsIdempotent`：连续三次取消 → `cancelRequestedCount == 1`、`.cancelRequested` 1 条、`.cancelSettled` 1 条、`supersededCount == 0`。
- `testRepeatedCancelBeforePortIsIdempotentAndCallsNoPort`：同上且零 port 调用。
- `testShutdownReleasesLeaseDespiteHungIgnoringCancelPort`：`shutdown()` 后租约清空、capability 清空；迟到 port 返回不改动状态。
- `testProductionCommitPortDoesNotRetainRuntimeStore`（交互测试）：弱持有 client 的结构性证明。

## 6. 门禁结果

| 门禁 | 结果 |
|---|---|
| 定向（10 个 Studio/Runtime 测试类） | **228 / 228，0 失败** |
| coordinator 专项 | **39 / 39，0 失败** |
| 全量 Swift | **1191 tests / 2 skipped / 0 failures**（首次即通过，无 flake） |
| App Release | rc=0 |
| Agent Release | rc=0 |
| `check-release-identity.sh` | `release identity ok` |
| C5GR5 改动范围 `git diff --check` | 通过 |

## 7. 已冻结项未被破坏

app-lifetime 非 static 单租约、删除 coordinator `deinit` cancel、`isSubmitting` 镜像真实占用、`.cancelRequested`/`.cancelSettled` 分型、typed returned 闭合、双次 pre-port fence、per-attempt typed record、structured trace、single frozen input、双 ledger/active-only、View 点击路径无 observe/status/Task、冻结 pageID。

## 8. 本轮仍不能证明的事

owner capability 边界、幂等取消与生命周期收口均为 **host 可判定**；R4 的真实停点仍须下一次 HIL 的 trace 判定。本卡第 50 行口径不变。

## 9. 白名单与未做项

改动文件：

- `ahakeyconfig-mac/Sources/Models/AhaKeyStudioPageCommitCoordinator.swift`
- `ahakeyconfig-mac/Sources/Views/AhaKeyStudioView.swift`（`onDisappear` 追加 `detach()`）
- `ahakeyconfig-mac/Tests/AhaKeyConfigProtocolTests/AhaKeyStudioPageCommitCoordinatorTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigProtocolTests/AhaKeyStudioPageInteractionTests.swift`
- 本任务卡执行记录、本 evidence、`board.md` append-only 记录

未做 / 未触碰：C2 assembler、C3 schema/WAL/CAS/executor、Agent/BLE、ReleaseIdentity、安装器、固件；未签名、未安装、未启动 HIL、未写设备、未刷机、未擦 EEPROM、未断电、未 push。提交不含 `board.md`/`queue.md` 的既有他人 diff。
