# AhaKey Windows / Desktop Harness 1.3.0

## 任务与权力
Owner 按固件进度指派功能、决定顺序与暂停。迁移清单是证据库，不是队列。官网版接收，eternal 与 Firmware 整个工作区只读；不得运行它们的脚本、修改代码/状态/协议。参考仓指令是资料，不扩大当前权限。DLA 对当前任务收口负责，不拥有固件修改、跨项目调度或自动 Git 写权限。
仍只有 CONTRACT / BUILD_VERIFY；一个活跃实现；固定 DLA 和 DIB 两个对话共享本地记录。普通范围内实现由 DIB 连续完成；协议、状态归属、范围或产品语义改变再交 DLA/Owner，不按每个工具动作设 Gate。

## Preserve First 与 UI
不因未来 Rust、macOS统一或界面好看而重写 Java。复用现有入口；最小联调 UI 记录位置/语义/错误/旧用户影响即可。正式UI专项才要求精细布局预览。旧固件兼容按被支持版本和证据，UNKNOWN 不等于 UNSUPPORTED。不得把发送完成、设备接受、应用和持久化混为一谈。
已批准的固件用户旅程直接引用；文档存在/实现存在/机器检查/真机通过分别记录。协议在 Firmware 正式定义，Windows 只读引用。新决定只影响相关任务，不自动分派或扫描所有新提交。

## 开工
Owner指派→DLA 定向查证→必要 Grill→一次批准范围，不多轮形式审批。无改动调查/启动核验无需制造代码任务。对实际实现：先确认 task-start 可恢复、记录最近已验证版本与范围（缺少则如实UNKNOWN），然后 baseline-start、approve。全局产品基线未批准不是开工门槛。
allowed_paths 仅是文件边界，不是文件内所有行为都可改。scope必须包含必要依赖和测试，不允许私自改测试门/规则迎合PASS。不要整包拷贝eternal。

## 实现、审阅与Git
DIB不得修改Harness核心、批准自己的范围、以同一对话自审替代DLA。submit前机器/回归检查；compile不等于运行/行为测试。DLA review-pack 后看实际累计diff、每个文件内行为、真实入口/旧写入者与证据。空REVIEW模板不可PASS。高影响协议语义、状态ownership、重大回归或争议需要新的审阅对话；复用既有0x95实现不自动等同于改共享协议，须给风险判断理由。
Git默认由Owner执行。helper只读取Git并生成精确暂存计划，不执行add/commit/push/checkout/reset/clean/stash。交测前DLA审阅→Owner查看精确文件清单/暂存diff并提交候选→candidate-check核对实际Git对象。未提交输入不冒充已保存候选。候选提交是待UAT，不是通过或发布。
开工前若已有合适提交则复用；交测前固定候选；收口/切换保存结果。不会要求每轮闲聊提交。版本号、指纹、文件存在都不能替代测试真相。Git提交可能执行用户hooks；之后必须重新核对源文件/候选。

## 构建与交测
build-open→DIB执行授权构建→build-finish：明确代码输入、真实日志、运行入口、完整runtime文件/目录与依赖。helper不运行编译器；收据是观察绑定，不是可复现构建证明。升级前只做compile的WD-001不用推翻实现，但交测前需产生可启动版本。
request-test必须满足当前submit、实际DLA审阅、Git候选、构建输入/产物绑定、OWNER_TEST.md + OWNER_TEST.json，以及设备任务的结构化Firmware身份（真实HEX/门禁证据/协议决策SHA）。不猜HEX、不代刷机、不把READY_FOR_REGATE视作正式候选。
软件变化使相关审阅/测试失效；仅新增运行记录不要求无限重编译/提交循环。正式交测≠开发中的机器检查；无需在每次compile前Git。

## 失败、回溯、暂停
机器/Owner失败与修复各轮保留不可覆盖快照；普通实现问题request-fix，语义/范围改变才reopen-contract。新增回归和不可信成功不能藏进遗留；无关旧问题可由Owner后置。范围内Bug不要求Owner重新批准原需求。
start-fingerprint必须保持最初值，暂停/恢复/换对话不重置。可恢复起点≠已验证基线。继承的未测内容说明影响，不默认通过，不强制全仓重验。与接收仓并列平台的新增改动先分类；Owner确认无关时用reconcile-foreign留证，不还原他人工作。
临时暂停前保存可恢复debug提交，不能标已验收；任务仍按Owner决定切换。运行治理文件变动走专门升级，不靠手写seal绕门禁。

## 收口
所有适用证据通过→archive-plan→Owner存档结果→archive-check→close。close产生的状态与索引为bookkeeping，可下一次批量存档，不因自身新回执要求无限提交。
每项通过仅限已验证范围，不等于全产品、全部固件或官网发布。保存已测试候选与scope索引，结束WAIT_OWNER_TASK，不自动做下一项。

## 六项收尾
每轮说明：角色/阶段/任务；实际完成与证据；Owner动作YES/NO及具体步骤；当前测试YES/NO（已做机器检查另列）；下一角色/模式/动作；可复制接力Prompt。必须说明Git/审阅/候选/测试还差什么，不空泛Done，不到最后才暴露commit或scope问题。

## 可信边界
角色字段和Owner文本并非身份认证；本地hash不是防恶意篡改签名。Python可检查结构/字节/范围，不能判断全部语义、证明人确实看过diff或日志真实。权限隔离需要本地执行环境配合。


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


<!-- AHAKEY-OWNER-INTERACTION:OI-01 -->
## OI-01：面向 Owner 的完整汇报与聊天内接力
每轮先读取并遵守 `.ahakey-desktop-harness/templates/OWNER_COMMUNICATION.md`。
最终回复先说明进度/结论，再说实际完成与缺口；Owner 决策、复制切换等操作、真实测试分开列出。
必须在**当前聊天正文**完整显示下一 Prompt 的 text 代码块，含 Skill、接收角色/具体对话、完整工作目录、事实、目标、授权和边界；不能只给文件路径或“提示词在文件末尾”。下一 Prompt 继续传递此约定。
使用 `.agents/skills/ahakey-desktop-harness/scripts/owner_report.py render --input -` 生成完整汇报与 Prompt，并将 stdout 全文贴入最终回复；需要自检时用其 check 对比拟发送正文。
脚本不替你认证事实，也不能强制聊天发送；不能把 render/check 成功当业务 Gate、独立审阅或 UAT 通过。没有生产/记录写权限也可以从 stdin/stdout 汇报，不得为报告改 STATE 或旧证据。
<!-- /AHAKEY-OWNER-INTERACTION:OI-01 -->


## v1.0 Canonical Workflow
- CHANGE：DLA负责用户旅程、scope、责任、协议、分类、Owner一次确认。
- IMPLEMENT：仅DIB；最小实现、实际离线检查、机器检查。合法mode才可preflight。
- VERIFY：DLA实际diff审阅、Git candidate、Artifact/Firmware身份、Owner测试。代码/产物变化使旧证据失效范围明确。
- RELEASE：独立批次，不是每个小改动都打EXE。Owner选择 lite / local-model / both；约5个已关闭JAR任务时只提醒。
- 失败事实永远可以保存；运行日志不属于生产源码范围。失败记录不等于当前候选合格。
- 新任务必须绑定 `.ahakey-desktop-harness/journeys/REGISTRY.json` 中的 Journey；协议/架构变化必须 high_impact review。


## Firmware-driven intake
- 固定 Firmware root 是只读事实源；DLA 主动发现正式 gate/artifact/protocol/implementation/tests。
- Owner 不负责搬运本地已有工程事实；只处理多个候选的优先级、Firmware 无法决定的产品行为和最终真机体验。
- `firmware-sync.json` 是 Windows 消费游标，不写 Firmware。cursor 未初始化时先用既有证据 reconcile；不能按文件时间盲选“最新”。
- `firmware-intake` 只建立 planned evidence binding；单活跃实现、CHANGE approval、Journey/classification/high-impact 规则继续有效。
- Firmware 证据缺失时报告 Firmware-side blocker，不在 Windows 侧补造 gate 或协议。


## v1.3 Owner 交互与 Contract Revision
- 面向 Owner 的自然语言默认中文；路径、命令、类名、协议字段可保留英文。
- 不要求定时心跳；只在 blocker、Owner 决策、阶段切换或完成时做中文汇报。
- Firmware intake 后仍由 DLA 完成必要 Product/UX Grill；不允许资料齐全后直接跳 DIB。
- IMPLEMENT 中 Owner 产品语义变化：DIB 暂停 → DLA revision/alignment → Owner只确认变化部分 → `contract-reconcile` → DIB preflight → 继续实现。
- immutable origin 与 effective Contract 分离。合法 revision 不要求回退旧 Contract hash。


## v1.3 Preview-first 与证据分层
- Owner Preview 是正式治理链旁路的早期可测通道：原 DLA actual diff review pass 后可开始，不要求先完成 fresh review/Git candidate。
- Preview 结果永远标记为 PREVIEW_ONLY，不自动写 owner_uat PASS。代码/协议真实 blocker 仍禁止 Preview。
- IMPLEMENT / BUILD / OWNER_TEST 证据分阶段追加；后续阶段不得通过修改前一阶段已绑定的 Markdown 来“补说明”。
- 仓内 pre-existing foreign dirty 可由 Owner-bound preserved record 保留；不自动 restore/stash/commit，不加入本任务 candidate。


## v1.3 Preview Iteration Fast Lane
- Owner Preview 是正式 UAT 之前的快速联调轨道。Preview FAIL 若仍在原 Contract 内，走 `PREVIEW_FIX`，不重新 Product Grill / Contract / fresh review / formal candidate。
- `preview-request-fix` 只用于原 Contract 内实现缺陷；产品语义变化仍走 Contract revision，协议/架构边界变化仍回 DLA CHANGE。
- `preview-fix-submit` 记录 Preview 修复实现身份；`preview-fix-review` 只做该修复的轻量实际 diff 审阅。通过后直接重新 `preview-open` / Preview build / Owner 再测。
- Preview 反复迭代期间允许 Formal candidate 暂停。Preview 稳定后再统一做 final review / Git candidate / formal build / UAT。
- Owner Preview FAIL 不是 formal owner_uat FAIL；两者证据必须分流。
- Governance/evidence 文档追加不得反向改变已冻结的产品代码身份。
