# Owner 指派 + 有保护的交付
0.4 增加 Git/实际审阅/候选/失败追溯，不恢复五阶段重构，不新增全局产品基线审批。
当前WD-001已实现submit，应接DLA_REVIEW，不能WAIT_OWNER_TASK、new同名任务、重新approve、activate或覆盖start。
更新前机器检查和报告原样保留；缺新的review/Git/build receipt显示交付待完成，不是升级失败。最终状态以本地实际记录为准，不按聊天摘要伪造字段。


## v1.0 发布形态与交测
本节与 `DISTRIBUTION_DELIVERY.md` 是新增规则；旧规则中的引用OWNER_TEST文件不再足以完成Owner交接。
- 任务仍由Owner排期；保留全局baseline未批准的事实，不以其阻塞单项。
- Serial JAR integration 与 Owner-dispatched dual-variant packaging 分开；两版同一应用二选一可切换。
- 采用补充记录，不覆盖原Contract、批准、起点、review、candidate、BUILD_RECEIPT、FIRMWARE_IDENTITY、OWNER_TEST和test_packet。
- formal Firmware gate必须是可解析、匹配HEX/候选的正式PASS；READY_FOR_REGATE不是PASS。
- 已批准验收每条都有步骤/适用证据/明确Owner后置决定；不得静默删掉长时间休眠或非法值检查。
- 交测正文必须显示实际功能、形式、路径、来源、前置、操作/预期、恢复；不能只提供文档链接。
- 保留Git候选、实际diff审阅、HF01路径规范化和不重置起点。无生产改动不要求重复Git/构建。
- 配方为已观察脚本说明，不是立即执行授权或双版可构建证明。未知资源/安装切换只阻塞有关批次。

## v1.0 phase routing
- CHANGE: DLA only; Journey/classification/Contract/Owner approval.
- IMPLEMENT: DIB only; IMPLEMENT/FIX/BUILD_ONLY.
- VERIFY: DLA review, candidate, artifact, Owner UAT. OWNER_TEST does not authorize DIB implementation.
- RELEASE: separate Owner-dispatched packaging batch.


## Firmware-driven intake
- 固定 Firmware root 是只读事实源；DLA 主动发现正式 gate/artifact/protocol/implementation/tests。
- Owner 不负责搬运本地已有工程事实；只处理多个候选的优先级、Firmware 无法决定的产品行为和最终真机体验。
- `firmware-sync.json` 是 Windows 消费游标，不写 Firmware。cursor 未初始化时先用既有证据 reconcile；不能按文件时间盲选“最新”。
- `firmware-intake` 只建立 planned evidence binding；单活跃实现、CHANGE approval、Journey/classification/high-impact 规则继续有效。
- Firmware 证据缺失时报告 Firmware-side blocker，不在 Windows 侧补造 gate 或协议。


## v1.2 快速联调默认
对 device-related 小增量，DLA 实际 diff review pass 后优先开启 Owner Preview，使真机反馈与 formal fresh review/candidate 并行。不要把“所有治理证据完成”作为 Owner 首次摸到产品的前置条件。
