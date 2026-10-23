$ahakey-desktop-lead
$ahakey-desktop-harness

固定DLA，官网Windows工作目录以当前选择为准。先读适用AGENTS、两个Skill、RULES/OPERATING_MODE/GUARDED_DELIVERY、STATE/local、UPGRADE_RECEIPT，以及当前任务全部已批准记录。
这是v0.4在途升级恢复，不是初始化或重做实现。
若本地活跃{{ID}}且DIB已submit：保留Owner指派、批准、Contract、REFERENCES、verification、EXECUTION_REPORT、builder_submission和原始start-fingerprint；当前应接DLA_REVIEW。若与预期不一致报告实际差异，不清空任务或伪造字段。
运行doctor/status/validate，随后guard-status --id {{ID}}。结构检查通过与交付PENDING分开说明。
然后执行review-pack --id {{ID}} --role DLA，实际阅读累计diff及6文件（若实际数量不同先报告）、相关测试/协议引用、真实入口和旧行为。不要只复述DIB报告，不修改生产代码。
检查0x95的正式当前语义、响应解析、单位/边界、设置后回读、失败/超时/断连、旧固件适配以及More/设备信息入口；以本项批准Contract和当前固件决定为准，不套旧M1a/eternal的set→0x04→readback，不将禁用0x04误推广到所有其他功能，不新增0x86/0x9F或协议。
填写有依据的REVIEW.json并按helper登记。空模板不PASS。普通复用协议不自动要求新审阅窗；若确有协议语义/ownership变化或高风险，说明理由并给新的审阅对话Prompt。
若有实现缺陷：request-fix，给DIB局部修复提示；约定变化才reopen受影响范围。
若审阅通过：candidate-plan，先审清清单，给Owner精确Git暂存/审查/commit步骤。不得自动Git写，不盲目add -A；无需重新批准原需求。
当前仅有compile不等于可运行产物。若缺可运行构建证据，给DIB“仅在现有范围内构建/打包和机器验证”的Prompt，使用build-open/finish，不重写已有功能。审阅通过的源码不变时不重复设计。
候选提交后candidate-check；产物/依赖、真实固件候选、OWNER_TEST.md/JSON齐全后request-test。不猜HEX、不代刷机，不编造Owner通过。暂缺产物/审阅/Git是交付缺口，不是升级失败。
每轮六项收尾，清楚说实际改动/审阅/Git/构建/固件配对完成到哪、Owner当前要做什么或不用做，以及下一角色的可复制Prompt。只停在真正需要Owner或另一个角色操作的地方，不再一轮轮询问已经批准的设计。

当前 v1.2 仍需读取 DISTRIBUTION_DELIVERY.md：发布前补实际发行身份/验收覆盖/正式固件Gate；交测正文直接输出owner-brief。批次只能Owner指定，不能利用本次JAR补证自动打两个EXE或clean当前target。


<!-- AHAKEY-OWNER-INTERACTION:OI-01 -->
## OI-01：面向 Owner 的完整汇报与聊天内接力
每轮先读取并遵守 `.ahakey-desktop-harness/templates/OWNER_COMMUNICATION.md`。
最终回复先说明进度/结论，再说实际完成与缺口；Owner 决策、复制切换等操作、真实测试分开列出。
必须在**当前聊天正文**完整显示下一 Prompt 的 text 代码块，含 Skill、接收角色/具体对话、完整工作目录、事实、目标、授权和边界；不能只给文件路径或“提示词在文件末尾”。下一 Prompt 继续传递此约定。
使用 `.agents/skills/ahakey-desktop-harness/scripts/owner_report.py render --input -` 生成完整汇报与 Prompt，并将 stdout 全文贴入最终回复；需要自检时用其 check 对比拟发送正文。
脚本不替你认证事实，也不能强制聊天发送；不能把 render/check 成功当业务 Gate、独立审阅或 UAT 通过。没有生产/记录写权限也可以从 stdin/stdout 汇报，不得为报告改 STATE 或旧证据。
<!-- /AHAKEY-OWNER-INTERACTION:OI-01 -->


当前若已安装v1.0，以 STATE 和 START_V1_DLA.md 为准；旧版本阶段名称仅作历史接续参考。


v1.2：如果 actual diff review substantive PASS 且是 device-related，优先考虑 `preview-open` 让 Owner 尽早联调；high-impact fresh review / candidate / formal build 可以继续并行，不必让 Owner 等完整治理链收尾后才拿到可测包。
