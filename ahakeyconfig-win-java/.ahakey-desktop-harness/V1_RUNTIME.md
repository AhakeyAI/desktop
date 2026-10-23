# AhaKey Windows Harness 1.3.0 Runtime

本文件表示完整 v1 执行层已安装。事实索引 `.ahakey-desktop-harness/v1/*.json|yaml` 仍是历史/当前观察，不替代正式运行门禁。

主流程：Owner Task → DLA CHANGE → DIB IMPLEMENT → DLA VERIFY → 可选 RELEASE。

硬约束：
- CHANGE 未批准，DIB 不得实现。
- DIB 只在 IMPLEMENT / FIX / BUILD_ONLY 模式开工；OWNER_TEST 不授权 DIB。
- scope expansion / architecture / protocol change 回 CHANGE；architecture/protocol 强制 high-impact 独立审阅。
- 失败证据可以在候选漂移时保存，但不会使当前候选合格。
- Journey Registry 是 v1 新任务的 Contract 输入。
- JAR 和 installer 验收分离；Release Batch 由 Owner 启动，选择 Lite / Local Model / Both。
- 默认累计约 5 个已关闭 JAR 增量时只提醒 Owner，不自动打包。
- Owner 交互遵循 OWNER_COMMUNICATION；跨窗口接力 Prompt 必须直接显示在聊天正文。


## Firmware-driven intake
- 固定 Firmware root 是只读事实源；DLA 主动发现正式 gate/artifact/protocol/implementation/tests。
- Owner 不负责搬运本地已有工程事实；只处理多个候选的优先级、Firmware 无法决定的产品行为和最终真机体验。
- `firmware-sync.json` 是 Windows 消费游标，不写 Firmware。cursor 未初始化时先用既有证据 reconcile；不能按文件时间盲选“最新”。
- `firmware-intake` 只建立 planned evidence binding；单活跃实现、CHANGE approval、Journey/classification/high-impact 规则继续有效。
- Firmware 证据缺失时报告 Firmware-side blocker，不在 Windows 侧补造 gate 或协议。


## Contract revision runtime（v1.3）
`contract-reconcile` 是实现中产品语义修正的正式恢复路径。它保存 revision history、更新 effective approval/dispatch，并在可选 Owner 授权下修复旧 helper 造成的 guard-origin/start 引用不一致。所有写入先预校验，失败回滚。


## v1.3 Fast Feedback Lane
Owner Preview 是正式治理旁路的早期联调通道。原 DLA 对实际 diff 做 substantive review 并明确 pass 后，可 `preview-open`；DIB 在隔离 snapshot 构建，Owner 立即测试。high-impact fresh review、candidate、formal build 与 delivery evidence 可并行继续。Preview PASS/FAIL 不等于 Owner UAT。

## v1.3 Evidence Streams
IMPLEMENT 在 submit 时冻结 `IMPLEMENTATION_RECEIPT.json`；BUILD_ONLY 只写 BUILD_REPORT / BUILD_RECEIPT；OWNER TEST 独立写结果。后续 evidence 追加不反向使已审代码/candidate stale。

## v1.3 Preserved Foreign
仓内任务开始前已存在的 unrelated dirty 可 Owner-bound 记录为 preserved foreign。候选不包含它，也不要求 restore/stash/commit；若该文件在任务期间变化则重新阻塞。


## v1.3 Preview Defect Loop
Owner Preview 发现原 Contract 内实现问题时，DLA 使用 `preview-request-fix` 路由到 DIB `PREVIEW_FIX`。DIB `preview-fix-submit` 后由 DLA `preview-fix-review` 做轻量实际审阅；PASS 后直接重新 Preview build。Formal candidate/review 可以等 Preview 稳定后统一刷新，不因每个体验小缺陷重复完整 Formal Loop。

## v1.3 Governance Snapshot
运行时 `governance_snapshot()` 与安装器使用同一治理文件集合，明确包含 `OWNER_PREVIEW.md`、`EVIDENCE_STREAMS.md`、`PRESERVED_FOREIGN.md`。安装后不应因 seal 有路径而 snapshot 缺路径产生假 `PROTECTED_GOVERNANCE_CHANGED`。
