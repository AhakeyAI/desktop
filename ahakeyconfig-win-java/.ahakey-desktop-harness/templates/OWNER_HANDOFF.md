# 本轮收尾

1. 当前：角色 / Phase / Mode / Task / Checkpoint。
2. 实际完成及证据；未完成/未知。
3. Owner 当前介入 YES/NO：只给一个必要行动。
4. 当前需要 Owner 测试 YES/NO：YES 给构建/固件/前置/步骤/预期/恢复；另列已执行机器检查。
5. NEXT ACTION：角色/模式/动作；无指派则等待，不挑下一项。
6. 可复制 Prompt：显式 Skill、工作目录、当前记录、权限及任务。


## v1.0 交付约束
遵循GUARDED_DELIVERY：原始起点不可重置；实际diff审阅；候选Git与产物绑定；结果与遗留存档。模板不代表通过，不自动Git写。

## v1.0 必须直接呈现给Owner
本轮功能/交付形式/发行配置；Windows主产物+依赖+Java完整路径；Firmware生产方+原完整路径+候选+SHA；前置；编号动作/预期；停止恢复；反馈。正文从OWNER_BRIEF_INPUT生成，使用handoff-publish/owner-brief，不能只给链接。合同要求逐条映射，JAR不代表双安装版。


<!-- AHAKEY-OWNER-INTERACTION:OI-01 -->
## OI-01：面向 Owner 的完整汇报与聊天内接力
每轮先读取并遵守 `.ahakey-desktop-harness/templates/OWNER_COMMUNICATION.md`。
最终回复先说明进度/结论，再说实际完成与缺口；Owner 决策、复制切换等操作、真实测试分开列出。
必须在**当前聊天正文**完整显示下一 Prompt 的 text 代码块，含 Skill、接收角色/具体对话、完整工作目录、事实、目标、授权和边界；不能只给文件路径或“提示词在文件末尾”。下一 Prompt 继续传递此约定。
使用 `.agents/skills/ahakey-desktop-harness/scripts/owner_report.py render --input -` 生成完整汇报与 Prompt，并将 stdout 全文贴入最终回复；需要自检时用其 check 对比拟发送正文。
脚本不替你认证事实，也不能强制聊天发送；不能把 render/check 成功当业务 Gate、独立审阅或 UAT 通过。没有生产/记录写权限也可以从 stdin/stdout 汇报，不得为报告改 STATE 或旧证据。
<!-- /AHAKEY-OWNER-INTERACTION:OI-01 -->
