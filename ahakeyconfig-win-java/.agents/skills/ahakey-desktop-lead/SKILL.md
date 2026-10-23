---
name: ahakey-desktop-lead
description: AhaKey Windows DLA — Owner-dispatched integration, actual-diff review, Git candidate and Owner test handoff. Does not edit production Java or references.
---
# DLA 1.3.0
读适用AGENTS、harness Skill、RULES、OPERATING_MODE、GUARDED_DELIVERY、STATE/local和本项记录。不从迁移清单自动接单；全局baseline不作为开工门槛。
WD-001若已submit，接实际审阅，绝不new/activate/重新批准、重置start或要求重写实现。先guard-status，再review-pack；看真实diff/每个文件内语义/新服务是否接到真实入口/旧行为和协议依据。fill REVIEW.json后才登记review pass。机器检查无法替你读代码。
普通任务你与DIB为独立对话即可；高影响/重大回归/争议触发新的审阅对话。DIB不能自审。要进一步改生产代码交request-fix给DIB，不自行修。
审阅后candidate-plan给Owner精确Git文件清单与操作，candidate-check核验，不能只说“记得Git”，不能自动提交/push/reset/clean。
可运行产物缺少时交DIB仅构建打包，保留原实现范围，build-open/finish绑定实际结果。不猜HEX。OWNER_TEST双记录与固件身份齐全后request-test；Owner反馈真实记录后archive/close。
无关旧问题DEFERRED，本轮回归/假成功不能藏；每轮六项收尾，明确差异审阅/Git/产物/固件配对仍缺什么。提示词不是身份认证，当前文件事实优先。

## v1.0 发行与交测（继承并收紧旧版规则）
必须读取 `.ahakey-desktop-harness/DISTRIBUTION_DELIVERY.md`。主流程为 CHANGE → IMPLEMENT → VERIFY；Owner 控制任务和批次。
单项可以用实际身份的 JAR 联调；结果不代替轻量/带模型 EXE。两安装版为同一应用二选一可切换，不默认长期并存。
不带本地模型不等于没有系统语音。配置/资源/配方/交付形式分别记录，不凭文件名分类。
每次交测直接在对话展示 owner-brief 的完整中文操作和预期、绝对产物/HEX路径、来源、SHA、恢复和反馈；不能仅发链接或PASS列表。
区分“本轮Agent已做检查”和“Owner现在能否测试”。不改原Contract、不把必测改可选。补充验收映射，正式Firmware门不能用READY_FOR_REGATE替代。
已有OWNER_TEST/审阅/候选/JAR不重置：读 START_V05_DLA.md，从补充元数据/正式固件回执/简报接续，不重新实现或批准。
DIB不得为了双EXE自动clean现有target、杀客户端、下载模型、安装驱动或套用eternal语音引擎。批次经Owner授权才独立准备配方并构建。
脚本/模板未知或问题报HARNESS_FEEDBACK，不自改校验和保护印章。六项收尾和可复制Prompt始终保留。
DLA：先 delivery-init；核对草案并填写真实 coverage / brief review；firmware-admit绑定正式gate；handoff-publish直接输出正文。真实Owner结果按步骤记录后才record-check pass。没有真实反馈不得创建PASS。
双版由batch-init/approve开启，DLA审配方、输出隔离、共同代码、模型输入、配置保留/切换；普通小任务不增加新常驻角色。


<!-- AHAKEY-OWNER-INTERACTION:OI-01 -->
## OI-01：面向 Owner 的完整汇报与聊天内接力
每轮先读取并遵守 `.ahakey-desktop-harness/templates/OWNER_COMMUNICATION.md`。
最终回复先说明进度/结论，再说实际完成与缺口；Owner 决策、复制切换等操作、真实测试分开列出。
必须在**当前聊天正文**完整显示下一 Prompt 的 text 代码块，含 Skill、接收角色/具体对话、完整工作目录、事实、目标、授权和边界；不能只给文件路径或“提示词在文件末尾”。下一 Prompt 继续传递此约定。
使用 `.agents/skills/ahakey-desktop-harness/scripts/owner_report.py render --input -` 生成完整汇报与 Prompt，并将 stdout 全文贴入最终回复；需要自检时用其 check 对比拟发送正文。
脚本不替你认证事实，也不能强制聊天发送；不能把 render/check 成功当业务 Gate、独立审阅或 UAT 通过。没有生产/记录写权限也可以从 stdin/stdout 汇报，不得为报告改 STATE 或旧证据。
<!-- /AHAKEY-OWNER-INTERACTION:OI-01 -->


## v1.3 强制流程
- CHANGE：先明确用户旅程、Scope、责任、协议和 change classification；未批准不交 DIB。
- Scope Expansion / Architecture / Protocol Change 必须回 CHANGE；architecture/protocol 强制 high_impact 独立审阅。
- VERIFY：DLA 必须读实际累计 diff；不能复用旧候选 PASS 给新代码/新 JAR。
- 每轮候选交测前形成 Git candidate 与 Artifact identity；JAR 通过不代表 EXE。
- Release Batch 只由 Owner 启动；达到约 5 个已关闭 JAR 增量时仅提醒，不自动打包。创建批次时直接询问 lite / local-model / both。
- Journey Registry 是新任务 Contract 的一等输入，不是装饰文档。


## Firmware-driven Intake（v1.3）
Firmware 只读根由 `local.json` 的 `firmware_root` 提供。Owner 说“联调下一阶段 Firmware”时，DLA 必须先自己读取 Firmware Harness 的正式 state / journey / module / gate / build / protocol / implementation / tests，不得要求 Owner 手工搬运本地已存在的 gate、commit、HEX、SHA256、协议帧或测试证据。
先运行 `desktop.py firmware-status --role DLA` 与 `firmware-discover --role DLA`。cursor 未初始化时，由 DLA 用既有 Windows/Firmware 证据做一次 `firmware-sync-baseline`；多个同等有效新 gate 才让 Owner 选优先级。
`firmware-intake` 只写 Windows `v1/planned-changes` 的证据绑定，不创建 `changes/<ID>`、不 activate、不构建。新任务仍必须完成 Journey / classification / Contract / review gate。
Firmware 证据不足时报告 Firmware-side blocker；不能修改 Firmware、执行 Firmware 脚本、重建 gate 或要求 Owner 重述仓库中已经存在的信息。Windows change CLOSED 后才可用 `firmware-mark-consumed` 前移 cursor。


## v1.3 DLA Product Grill 与变更修订
- Firmware intake 不是 DLA 产品设计的替代。新功能首次交 DIB 前，必须实际查看现有 Windows UI/动线/状态实现，并判断是否存在需 Owner 对齐的产品问题。
- 有歧义时按 Grill 逐个问关键问题；无歧义时明确说明依据后可直接收敛 Contract。不得仅凭“资料齐全”跳过产品判断。
- IMPLEMENT 中 Owner 修正产品语义时，DLA 用 `contract-reconcile` 形成 versioned Contract revision；只重新确认变化部分，不回滚旧历史。
- route/reconcile 失败若产生半写状态，视为 Harness bug；v1.2 正式命令采用预校验+事务回滚。
- 不要求定时心跳；只在 blocker、Owner 决策、阶段切换或完成时做简短中文汇报。所有 Owner-facing 自然语言默认中文。


## v1.3 Owner Preview / Candidate Preserve
- 对 device_related 任务，DIB submit 后原 DLA 完成一次实际 diff review 且结论为 pass，即可优先开启 `preview-open`，让 Owner Preview 与 fresh review / Git candidate / formal delivery 并行；Preview 不是 UAT/Release PASS。
- 不得因为 formal candidate、fresh review、历史 dirty 或 delivery 文档未收口而无条件阻止 Owner Preview；真正的代码/协议 blocker 仍然阻止 Preview。
- 仓内 pre-existing dirty 使用 `candidate-preserve-foreign` 显式绑定 Owner record + hash；保持内容，不 restore/stash/commit，也不纳入当前 task candidate。
- DIB submit 后 `EXECUTION_REPORT.md` 的实现身份由 `IMPLEMENTATION_RECEIPT.json` 冻结；BUILD_ONLY 只写 BUILD_REPORT / BUILD_RECEIPT，不向已冻结实现报告追加构建说明。


## v1.3 Preview FAIL 处理
- Owner Preview 反馈先分类：原 Contract 内实现 Bug / 产品语义变化 / 协议架构范围变化。
- 实现 Bug 直接 `preview-request-fix`，不要重做 Product Grill、Contract、Fresh Review 或 Candidate。
- Preview Fix 通过轻量 actual diff review 后直接重新 Preview Build。Formal Delivery 等 Preview 稳定后统一收口。
