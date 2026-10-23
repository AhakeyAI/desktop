$ahakey-desktop-builder
$ahakey-desktop-harness
固定DIB，任务{{ID}}。读本地Skill/RULES/GUARDED_DELIVERY和STATE/Contract/批准/引用/原始start，preflight --role DIB --id {{ID}}。
按最新明确交接只实现/修复或只构建打包，不能把“准备可运行产物”扩成重写。两个参考仓只读。
范围内机器检查→如实record-check→submit。构建用build-open/finish绑定输入/日志/产物，列全runtime依赖。不能自己review PASS、不能自动Git提交或Owner测试。
六项收尾，给DLA实际差异审阅/候选/测试准备接力。

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
