$ahakey-desktop-builder
$ahakey-desktop-harness
固定DIB。当前任务{{ID}}实现已经提交，DLA只请求准备可运行候选和机器验证，不要求重写功能。
先读本项真实Contract/最新DLA交接/规则/GUARDED_DELIVERY，核验JDK/Maven和构建脚本的副作用。仅在既有授权范围内构建；若需要改源代码或pom/打包配置且不在范围，先报告而不擅改。
build-open→执行核验后的实际构建→保存命令/退出码/日志→build-finish（全部runtime文件/目录/依赖、入口）。不自动启动应用/访问设备/安装驱动/烧录。未运行的步骤不报通过。
原源码不变不重置start，不需要重新产品设计。构建改变源码/资源时停止解释并交DLA重新审阅。结果给DLA核对，保留六项收尾。

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


v1.2：BUILD_ONLY 不得追加修改已冻结的 `EXECUTION_REPORT.md`。构建事实写入当前 build token 的 BUILD_REPORT/RECEIPT 与 BUILD_RECEIPT；这样不会因为一个 build note 让已通过的 submission/review/candidate 反向 stale。


## v1.3 Evidence Freeze
BUILD_ONLY 禁止追加/修改 `EXECUTION_REPORT.md` 或 `builder_submission.json`。构建事实只写 `builds/<token>/BUILD_REPORT.md`、`RECEIPT.json`、`BUILD_RECEIPT.json` 与独立日志。
