# V03-STUDIO-OLED-LEGACY-COMPATIBILITY C3B：page-only execution、CAS/FIFO 与 durable resume

日期：2026-09-04 22:15–22:48 +08
ACK Codex 22:10 / `lastReviewedCommit=c78c8656a4bf12ad11a6fbaac80b629a550ec3f7` / 产品基线 `1ed560b` / 已安装 `0.2.1 (362)`。未 overlay `/Applications`、未打包、未签名、未 kickstart、未刷机、未 push、未进 C3C/C4/C5/HIL。未改 `queue.md`。本提交从 HEAD board 只追加 Cursor ACK/完成记录，不含验收前已有的 Codex/Zcode/queue/status diff。

## C3B 行为

| 审查项 | 落地 |
|---|---|
| physical-slot 单一 mapping | 生成与校验都走 `Family.physicalSlot`；`AhaKeyRuntimePageSemantic` 不再调用 `AhaKeyOLEDSyncPlan.physicalTaskSetIndex` |
| 多帧多资源 prepare 同构 | 2 帧 × 2 资源：fingerprint `prepareStrategy.prepareCount` 与生产 `resourceUploadProgram` 的 `.prepareWrite` 次数、address/length、session-nilness 逐项一致；覆盖 Standard `0x80` 与 Rhino/current `0x9B` |
| page-only execution | 冻结 `fieldMask/actions/bindings/prepareStrategy` 生成 `page:chunk:` / `page:bind:` / `page:defaultBind` / `page:activate:` / `page:field:` / `page:local:`；禁止 `base:mode:*` 与 mask 外字段；不发额外 save/finish |
| 开始前 CAS | device ID、`Family` vs 密封 profile、confirmed=0 时 base object fingerprint；不一致零写 fail-closed。首个确认之后恢复只再检 device + compatibility |
| FIFO / resume | 同设备非 head 不得开始；断连/timeout → `paused/resumablePartial`；同进程重跑与 fresh store reopen 从首个未确认最小步骤继续，已确认 chunk 零重发 |
| 取消 / fail-fast | queued schema=2 可无写入移除；running/paused/resumable 返回 `.refused`；确定性拒绝停在首错并保留最小确认 |

不实现 60 秒 abandon、逐字段 baseline projection、Studio 页面锁/C4 UI。未改 C2 assembler、`AhaKeyDeviceProgramSteps`、Views、Hook、安装器。C3A 已关闭的 identity/prepare/WAL fail-closed 保持。

## 门禁（原始命令）

```
swift test --filter 'AhaKeyStudioPageModelTests|AhaKeyStudioPackageAssemblerTests|AhaKeyOLEDSyncPlanTests|AhaKeyStudioRuntimeFacadeTests|AhaKeyStudioDraftPackageMappingTests|AhaKeyRuntimeContractTests|AhaKeyRuntimePersistentStoreTests|AhaKeyRuntimePageOperationTests|AhaKeyRuntimePageExecutionTests|AhaKeyConfigurationTransactionEngineTests|AhaKeyConfigurationTransactionRunnerTests|AhaKeyAgentPageExecutionTests'
# 204/204

swift test
# 882 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK

git diff --check
# DIFF_CHECK_OK
```

## 审查范围（相对 `c78c865` / 调度 22:10）

修改：

- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePageSemantic.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimePageOperation.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyConfigurationTransactionEngine.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyConfigurationTransactionRunner.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimeContract.swift`
- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimePageOperationTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimePageExecutionTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyAgentTests/AhaKeyAgentPageExecutionTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyAgentTests/AhaKeyAgentRuntimeEndpointTests.swift`（handshake 广告 schema=1+2）
- 本证据；board/任务卡仅追加 Cursor 执行记录

未改 C2 assembler、DeviceProgramSteps、Views、Hook、安装器。未改 `queue.md` 状态。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/queue.md`、`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`，以及 Codex 未提交的验收/status。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

C3B 按任务卡收口 page execution / durable resume / 取消边界。停手提审，不自动进 C3C/C4。
