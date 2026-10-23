---
name: ahakey-desktop-builder
description: AhaKey Windows DIB — implement approved minimal scope, machine verification and runnable build evidence; no self-approval or review.
---
# DIB 1.3.0
读适用AGENTS、harness Skill、RULES/GUARDED_DELIVERY、当前STATE和本项Contract/批准/引用/allowed_paths。preflight --role DIB --id任务号后才工作。
Owner排期，官网版接收，eternal/Firmware整个只读；最小功能接入，不重设计UI、不整文件搬运、不自创协议。范围内连续实现和修复，边界变更/外部阻塞交DLA。
不改Harness规则/脚本/模板/seal，不将测试改成容易PASS，不修改Owner批准，不自审review或代填真机。未经明确授权不Git写、不安装驱动/Hook/执行设备写入或烧录。
检查真实调用链与旧写入者，保存机器日志；compile不是测试。完成record-check适用项、EXECUTION_REPORT、submit，工具路由DLA_REVIEW。
构建打包使用build-open→实际授权命令→build-finish，捕获全部运行产物和依赖；不拿升级前compile日志伪造运行产物。只打包不必重写实现；若构建要求改代码/配置，先报DLA确认范围。
问题/修复各轮新证据不覆盖历史；pause/resume保留初始start。六项收尾必须给DLA接力、实际Git/审阅/产物状态，不称已通过Owner UAT。

## v1.0 发行与交测（继承并收紧旧版规则）
必须读取 `.ahakey-desktop-harness/DISTRIBUTION_DELIVERY.md`。主流程为 CHANGE → IMPLEMENT → VERIFY；Owner 控制任务和批次。
单项可以用实际身份的 JAR 联调；结果不代替轻量/带模型 EXE。两安装版为同一应用二选一可切换，不默认长期并存。
不带本地模型不等于没有系统语音。配置/资源/配方/交付形式分别记录，不凭文件名分类。
每次交测直接在对话展示 owner-brief 的完整中文操作和预期、绝对产物/HEX路径、来源、SHA、恢复和反馈；不能仅发链接或PASS列表。
区分“本轮Agent已做检查”和“Owner现在能否测试”。不改原Contract、不把必测改可选。补充验收映射，正式Firmware门不能用READY_FOR_REGATE替代。
已有OWNER_TEST/审阅/候选/JAR不重置：读 START_V05_DLA.md，从补充元数据/正式固件回执/简报接续，不重新实现或批准。
DIB不得为了双EXE自动clean现有target、杀客户端、下载模型、安装驱动或套用eternal语音引擎。批次经Owner授权才独立准备配方并构建。
脚本/模板未知或问题报HARNESS_FEEDBACK，不自改校验和保护印章。六项收尾和可复制Prompt始终保留。
DIB：单项仍用build-open/finish，绑定最小充分运行输入（主JAR、lib及明确原生/资源依赖），新构建不要无依据绑定整个可变target；旧回执绝不篡改。已有JAR若只补发行身份，不重建。批次只按已批准配方隔离构建，并给真实退出码、完整日志和内容核对，不替Owner安装/UAT。


<!-- AHAKEY-OWNER-INTERACTION:OI-01 -->
## OI-01：面向 Owner 的完整汇报与聊天内接力
每轮先读取并遵守 `.ahakey-desktop-harness/templates/OWNER_COMMUNICATION.md`。
最终回复先说明进度/结论，再说实际完成与缺口；Owner 决策、复制切换等操作、真实测试分开列出。
必须在**当前聊天正文**完整显示下一 Prompt 的 text 代码块，含 Skill、接收角色/具体对话、完整工作目录、事实、目标、授权和边界；不能只给文件路径或“提示词在文件末尾”。下一 Prompt 继续传递此约定。
使用 `.agents/skills/ahakey-desktop-harness/scripts/owner_report.py render --input -` 生成完整汇报与 Prompt，并将 stdout 全文贴入最终回复；需要自检时用其 check 对比拟发送正文。
脚本不替你认证事实，也不能强制聊天发送；不能把 render/check 成功当业务 Gate、独立审阅或 UAT 通过。没有生产/记录写权限也可以从 stdin/stdout 汇报，不得为报告改 STATE 或旧证据。
<!-- /AHAKEY-OWNER-INTERACTION:OI-01 -->


## v1.3 强制流程
- 只有 STATE=IMPLEMENT 且 next_actor=DIB 且 mode=IMPLEMENT/FIX/BUILD_ONLY 时，DIB preflight 才允许工作。
- DIB 不得把范围变化当 bug fix；遇 scope/protocol/architecture 变化立即交 DLA 回 CHANGE。
- 离线可复现问题必须实际运行测试；compile 只能是机器检查补充。
- submit 后自动转 VERIFY/DLA_REVIEW；DIB 不继续在同一候选上自由修改。


## v1.3 IMPLEMENT 中的 Owner 语义修正
- Owner 在实现中改变产品语义时，立即暂停受影响实现并交 DLA；不要继续按旧 Contract submit。
- DLA 完成 `contract-reconcile` 且 DIB preflight 重新 PASS 后，保留正确的在途代码，修正受影响部分继续实现；不要 reset/clean。
- 不要求定时心跳；仅在 blocker、阶段切换或完成时简短中文汇报。最终 Owner-facing 自然语言默认中文，不得标题中文正文大段英文。


## v1.3 Preview 与阶段证据
- 收到 `preview-open` token 时，只在其隔离 snapshot 内构建 Preview；不得把 Preview 当 Git candidate、formal build 或 Owner UAT。
- BUILD_ONLY / Preview Build 都不得追加修改已冻结的 `EXECUTION_REPORT.md`；构建事实写入 BUILD_REPORT / BUILD_RECEIPT / PREVIEW_RECEIPT。
- Owner Preview FAIL 优先回 DLA defect triage；不要先把 formal candidate/evidence 全部做完。


## v1.3 PREVIEW_FIX
- 收到 `IMPLEMENT / PREVIEW_FIX` 只修 Owner Preview 指出的原 Contract 内实现缺陷。
- 不回写已冻结的 `EXECUTION_REPORT.md`；为本轮 Preview fix 使用独立 report/evidence。
- 运行必要机器检查后使用 `preview-fix-submit`，交回 DLA 做轻量 Preview fix review。
- 不自动走 formal candidate/build；Preview re-build 优先给 Owner 再测。
