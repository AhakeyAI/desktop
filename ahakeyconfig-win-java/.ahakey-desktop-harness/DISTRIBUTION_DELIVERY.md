# AhaKey Windows v1.0：单项 JAR 联调与 Owner 指定 Release Batch

## 永久边界
Owner排期。DLA与DIB两个固定对话、本地记录交接；单一活跃实现或已批准打包批次。官网接收，eternal/Firmware只读。
两版是同一应用二选一可切换，不默认并存。Lite不带本地模型但保留原有系统语音；不自动迁语音架构。
本文件是机制，不是执行构建、安装、下载模型、关闭进程、烧录或发布的授权。

## 现有WD-001的正确接续
升级只更新Harness运行文件/STATE版本与续接提示。Contract、批准、起点、审阅、候选、构建、原测试包和JAR不重置。
STATE可仍为OWNER_TEST，但新增交测要求尚待DLA核对。缺补充记录不是安装失败；不要重做实现、Git或构建来凑通过。
1. `delivery-init --id WD-001 --role DLA`：只读现有构建/JAR和Contract，创建新补充草案，不替换旧记录。
2. DLA真实检查 `OWNER_BRIEF_INPUT.json` 和 `ACCEPTANCE_COVERAGE.json`，记录review_note和reviewed_by_dla；三个已有机器要求从已有verification/日志取证，不再编译。不能只为过门改true。
3. `firmware-admit --id WD-001 --gate <Firmware根相对正式gate-receipt.json> --role DLA`。只读正式schema6 PASS、候选及HEX字节；未知schema停止，不猜。READY_FOR_REGATE不能当正式准入。
4. `handoff-preview`可查看草稿；`handoff-publish`在现有候选/构建/测试包与新增配置、正式gate和验收映射都有效时，生成DELIVERY_PACKET并在终端完整输出中文简报。旧test_packet原样保留。
5. 对话必须直接展示简报正文，不能仅发路径或PASS表。`owner-brief --id WD-001`重新核对后输出相同正文。
6. Owner返回真实结果后，DLA按模板填写OWNER_RESULTS，原始自然语言/截图仍保存；`results-check`、`record-check ... --evidence <OWNER_RESULTS.json>`分别记录真实覆盖。工具不是身份验证/执行真相证明。
7. 按原流程archive-plan→Owner Git→archive-check→close。JAR scope收口不代表两种安装形态通过；不自动选下一项。

## 补充文件与原记录
DELIVERY_PROFILE记录观察到的配置与运行形式，不给共享JAR假贴lite安装标签。
ACCEPTANCE_COVERAGE逐条引用原Contract验收bullet。disposition为planned_owner、existing_evidence或owner_deferred；没有映射不能正式交测。延期需Owner原话/范围，不自动删必测。
OWNER_BRIEF_INPUT是中文操作输入；不能用一行“见文档”代替步骤。
FORMAL_FIRMWARE_GATE只补正确准入引用，不改旧FIRMWARE_IDENTITY。
DELIVERY_PACKET封存旧测试包和补充记录；修改后必须保留旧版再publish。修复后不能沿用旧PASS。
OWNER_RESULTS必须逐步记pass/fail/not_executed，设备确认来自Owner。失败可随时保留，不能等全部门通过才记录事实；只有PASS需要完整适用证据。
原Contract中“同样测试0/60/120”不得被解释成仅即时读取；DLA核对适用持久化范围。长时间真实睡眠不被快速保存覆盖。缺环境可问一次明确取舍或引用独立适用证据。

## 日常JAR
`build-open/finish`不运行编译器，只记录；DIB另行执行明确授权构建。
新的artifact根用最小充分主JAR、lib、原生文件/资源，不默认整个target；旧BUILD_RECEIPT绝不改hash以缩小范围。
显示Java可执行文件的真实绝对路径；缺Java/环境如实报告，不自动系统安装。

## 双版批次（Owner单独指派）
不在升级或WD-001续接时自动创建批次。
`batch-init --batch WB-001 --task WD-001 [--task WD-002] --owner-record <真实指派> --form installer_exe --role DLA`
生成DRAFT；DLA补included_tasks与累计候选对应、scope_review、两版recipe/input_manifest、安装身份/保留配置/清理权重/恢复/版本支持。
配方/资源缺失必须显示阻塞，不能静默关闭model.enabled。当前接收SenseVoice与eternal Sherpa不等价。
Owner一次确认后 `batch-approve`；没有同时活跃WD任务。只在 `.ahakey-desktop-harness/delivery/batches/WB-001/staging/<variant>` 中准备获准输入，在 `artifacts/<variant>` 保留完整输出。不得clean现有target或覆盖另一版。
DIB `batch-build-open`→另行执行审查过的命令→保存退出码/日志/内容检查→`batch-build-finish --report ...`。无自动脚本执行。现有脚本如果不能隔离/会kill进程，先提出最小适配或征得特定操作授权；升级不修改它们。
每版BUILD要包括实际安装器/启动EXE、完整配套输入、model配置/模型身份/原生依赖及内容提取证据。不能只改文件名形成双版。
两版BUILD齐全后，DLA填写OWNER_TEST_INPUT.json，`batch-request-test`生成并直接输出两版路径/步骤/切换说明；`batch-owner-brief`复核并重新展示。Owner结果必须绑定OWNER_PACKET。
Owner测试clean_install、launch、common_configuration、variant_ui、variant_runtime、本批每项feature；双向lite_to_model和model_to_lite切换保留配置/单应用身份/能力反馈/恢复。用OWNER源证据绑定两个确切build。
`batch-register-result`保存反馈，`batch-status`显示各项缺口，`batch-archive-plan/check`存结果而不提交大模型/EXE，`batch-close`只表示本批安装形态验收，不发布、不推Git/官网。
Owner可以用`batch-pause/resume/cancel --owner-record <原话证据> --reason <原因> --role DLA`暂停/恢复/取消；保留原候选、批准和产物，不改成PASS。恢复时仍核对原输入；如果源代码或模型已变，不重新设起点，需明确新配方/新批次。
包装输入与脚本发生变化需要明确新配方/授权；不会因为源码改动少就跳过安装形态风险。

## 示例schema位置
`templates/DELIVERY_EXAMPLES.json`列出覆盖、结果、批次输入/构建/内容/切换的真实字段；示例不是测试结果，不能原样填PASS。

## 六项交互
位置/本轮完成/Owner当前行动/当前是否可测/下一角色动作/可复制Prompt继续保留。
分开“Agent已执行哪些检查”“Owner当前是否具备测试条件”“尚未验证什么”。安装与记录PASS不等于行为PASS。
路径/指纹/角色是可核对信息，不是安全沙箱、人员认证或证明模型实际执行了审阅。不要自改保护seal。

## v1.0 Release Batch selection
Daily feature increments normally use JAR integration. `release-status` may remind the Owner after the configured threshold (default 5 closed JAR increments), but never creates a batch.
When the Owner starts a batch, DLA must ask which installer scope is wanted: **Lite / Local Model / Both**. `batch-init` records exactly the selected variant(s). When Both is selected, both switch directions are required; for a single-variant batch, no cross-variant switch PASS may be claimed.
The two install variants remain the same application and are mutually exclusive / switchable, not intended for long-term co-installation.
