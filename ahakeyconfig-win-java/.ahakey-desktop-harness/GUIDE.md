# 日常入口
先读适用AGENTS、当前角色Skill、RULES、GUARDED_DELIVERY、STATE、任务change.json/Contract/REFERENCES/verification与最新交接。
- 安装和结构：`python .agents/skills/ahakey-desktop-harness/scripts/desktop.py doctor`，`status`，`validate`。
- 本任务交付缺口：`... desktop.py guard-status --id WD-001`。这是清单；PENDING是尚未完成，不是自动授权或假PASS。
- DLA审阅：`review-pack --id WD-001 --role DLA`，查看输出实际diff，填写本项REVIEW.json，再用原`record-check --check review`附JSON和必要Markdown。
- Git：`candidate-plan`只生成需Owner审核的精确暂存计划；不自动执行。Owner提交后`candidate-check --commit HEAD --owner-record <实际Owner记录>`。
- 可运行产物：DIB按已授权范围`build-open`，运行核验过的构建命令，`build-finish`列全runtime目录/依赖、日志和入口。详见GUARDED_DELIVERY。
- 交测：完成OWNER_TEST.md/JSON、Firmware身份JSON，`request-test`；Owner反馈后如实record-check real_device/owner_uat，失败request-fix。
- 收口：archive-plan / Owner存档 / archive-check / close；结束WAIT_OWNER_TASK。
不需要每轮read-only调查new任务或Git。模板不是完成记录。CLI帮助是参数合同：`... desktop.py <command> --help`。


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


## Firmware-driven intake
- 固定 Firmware root 是只读事实源；DLA 主动发现正式 gate/artifact/protocol/implementation/tests。
- Owner 不负责搬运本地已有工程事实；只处理多个候选的优先级、Firmware 无法决定的产品行为和最终真机体验。
- `firmware-sync.json` 是 Windows 消费游标，不写 Firmware。cursor 未初始化时先用既有证据 reconcile；不能按文件时间盲选“最新”。
- `firmware-intake` 只建立 planned evidence binding；单活跃实现、CHANGE approval、Journey/classification/high-impact 规则继续有效。
- Firmware 证据缺失时报告 Firmware-side blocker，不在 Windows 侧补造 gate 或协议。


## v1.3 常用新命令
- `candidate-preserve-foreign --id <WD> --path <file> --owner-record <record> --role DLA`：保留任务开始前已存在的仓内 dirty，不进入当前 candidate。
- `preview-open --id <WD> --role DLA`：原 DLA 实际 diff review pass 后生成隔离 Preview source。
- `preview-finish ... --role DIB`：绑定 Preview 构建产物、日志和启动入口。
- `preview-result --id <WD> --token <token> --status pass|fail --owner-record <record> --role DLA`：记录 Owner Preview 结果，不冒充 formal UAT。
