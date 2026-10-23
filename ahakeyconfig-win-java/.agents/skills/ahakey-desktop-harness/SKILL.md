---
name: ahakey-desktop-harness
description: AhaKey Windows v1 engineering workflow — preserve Owner dispatch, immutable scope baseline, DLA actual review, Git candidate, version-paired test and history.
---
# Harness 1.3.0
适用于官网Windows Java接收仓，不安装/执行在eternal或Firmware。版本与STATE以本地为准。
入口：`.ahakey-desktop-harness/RULES.md`、`OPERATING_MODE.md`、`GUARDED_DELIVERY.md`、`STATE.json`、`local.json`。
helpers在本Skill的`scripts/desktop.py`与`guardrails.py`。只写Windows Harness记录；Git只读；不运行产品/固件构建、应用、设备、安装或Git写动作。
`doctor/status/validate`检查结构，不证明实际测试。`guard-status --id`列交付缺口，PENDING不是安装失败。命令参数以--help为准，不编造。
两个阶段、两个长期对话、一个活跃实现；新任务Owner指派；六项收尾与接力Prompt始终保留。
升级后的在途任务先读`prompts/START_V04_DLA.md`，不套用旧版“升级必须无任务”流程。任务原始start和批准不能为升级或恢复重写。
规则/校验问题记录HARNESS_FEEDBACK，不准Agent自行降低标准。正式改进用Owner批准的独立Harness升级。

## v1.0 发行与交测（继承并收紧旧版规则）
必须读取 `.ahakey-desktop-harness/DISTRIBUTION_DELIVERY.md`。主流程为 CHANGE → IMPLEMENT → VERIFY；Owner 控制任务和批次。
单项可以用实际身份的 JAR 联调；结果不代替轻量/带模型 EXE。两安装版为同一应用二选一可切换，不默认长期并存。
不带本地模型不等于没有系统语音。配置/资源/配方/交付形式分别记录，不凭文件名分类。
每次交测直接在对话展示 owner-brief 的完整中文操作和预期、绝对产物/HEX路径、来源、SHA、恢复和反馈；不能仅发链接或PASS列表。
区分“本轮Agent已做检查”和“Owner现在能否测试”。不改原Contract、不把必测改可选。补充验收映射，正式Firmware门不能用READY_FOR_REGATE替代。
已有OWNER_TEST/审阅/候选/JAR不重置：读 START_V05_DLA.md，从补充元数据/正式固件回执/简报接续，不重新实现或批准。
DIB不得为了双EXE自动clean现有target、杀客户端、下载模型、安装驱动或套用eternal语音引擎。批次经Owner授权才独立准备配方并构建。
脚本/模板未知或问题报HARNESS_FEEDBACK，不自改校验和保护印章。六项收尾和可复制Prompt始终保留。


<!-- AHAKEY-OWNER-INTERACTION:OI-01 -->
## OI-01：面向 Owner 的完整汇报与聊天内接力
每轮先读取并遵守 `.ahakey-desktop-harness/templates/OWNER_COMMUNICATION.md`。
最终回复先说明进度/结论，再说实际完成与缺口；Owner 决策、复制切换等操作、真实测试分开列出。
必须在**当前聊天正文**完整显示下一 Prompt 的 text 代码块，含 Skill、接收角色/具体对话、完整工作目录、事实、目标、授权和边界；不能只给文件路径或“提示词在文件末尾”。下一 Prompt 继续传递此约定。
使用 `.agents/skills/ahakey-desktop-harness/scripts/owner_report.py render --input -` 生成完整汇报与 Prompt，并将 stdout 全文贴入最终回复；需要自检时用其 check 对比拟发送正文。
脚本不替你认证事实，也不能强制聊天发送；不能把 render/check 成功当业务 Gate、独立审阅或 UAT 通过。没有生产/记录写权限也可以从 stdin/stdout 汇报，不得为报告改 STATE 或旧证据。
<!-- /AHAKEY-OWNER-INTERACTION:OI-01 -->


## v1.3 Runtime
主流程：CHANGE → IMPLEMENT → VERIFY；可选 RELEASE BATCH 独立运行。
`desktop.py` 对 DIB phase/mode 做运行门禁；失败证据允许保留但不会为漂移代码授予候选资格。
生产指纹排除 logs/target/installer/.m2repo/META-INF 与已知 BLE 运行文件，避免正常运行日志阻塞失败记录。
新任务 schema v3 必须绑定 Journey Registry、change classification、review policy；protocol/architecture 强制 high-impact review。
`delivery.py` 不猜 JAR 启动命令；Owner brief 使用 DLA 核对后的 launch recipe。
Release Batch 支持 Owner 选择 lite、local-model 或 both；两者同时选择时才要求双向切换测试。


## Firmware-driven Intake Runtime（v1.3）
正式入口：`.ahakey-desktop-harness/FIRMWARE_INTAKE.md` 与 `firmware-sync.json`。`firmware-status`/`firmware-discover` 只读 Firmware；`firmware-intake`、`firmware-sync-baseline`、`firmware-mark-consumed` 只写 Windows Harness 记录。
Owner 不承担本地 Firmware 工程事实搬运。只有候选优先级或产品行为存在真实歧义时才请求 Owner 决策。任何发现命令都不是 Firmware PASS、Windows approval 或设备已刷证明。


## v1.3 Contract Revision / Owner Communication
- 当前显示版本以 `.ahakey-desktop-harness/VERSION.json` 与本包 Skill 元数据统一为 1.3；不得显示旧 v0.5/v1.1。
- 所有 Owner-facing 叙述默认中文；最终汇报读取 OWNER_COMMUNICATION，不要求定时心跳。
- 合法 Contract revision 使用 `contract-reconcile`：历史 Contract/approval 追加保存，生成新的 effective approval/dispatch，不要求把 Contract 回退到最初 hash。
- `contract-reconcile` 先校验后写入，失败回滚；旧 helper 的半写 route 行为不得继续使用。
- 仅在 blocker、Owner 决策、阶段切换或完成时主动中文汇报；不要求按时间定期心跳。


## v1.3 Preview-first 联调
- `preview-open`：原 DLA actual diff review 明确 pass 后即可开启 Owner Preview，不要求先完成 high-impact fresh review / Git candidate。
- Preview snapshot 从 Git HEAD 重建并只叠加本任务 allowed_paths；已登记 preserved foreign 的仓内历史 dirty 不进入 Preview。
- `preview-finish` 绑定 snapshot、产物、日志、启动入口；`preview-result` 只记录 OWNER_PREVIEW_PASS/FAIL，不冒充 formal owner_uat。
- formal fresh review / candidate / build 可以与 Owner Preview 并行；Preview FAIL 时优先 defect triage。

## v1.3 Phase-scoped Evidence
- IMPLEMENT 在 submit 时冻结为 `IMPLEMENTATION_RECEIPT.json`；后续 build/test 证据 append 到自己的阶段文件。
- Candidate 创建时验证 record bytes 已进 commit；candidate 成立后，后续阶段追加 evidence 不应反向使 immutable candidate stale。
- BUILD_ONLY 不得改 EXECUTION_REPORT；构建记录独立写 BUILD_REPORT / BUILD_RECEIPT。


## v1.3 Preview Iteration Runtime
- `preview-request-fix`：Owner Preview FAIL 且属于原 Contract 内实现 Bug时，路由 `IMPLEMENT / PREVIEW_FIX / DIB`。
- `preview-fix-submit`：冻结本轮 Preview fix 的 code fingerprint / report / machine evidence，路由 `VERIFY / PREVIEW_FIX_REVIEW / DLA`。
- `preview-fix-review`：DLA 记录轻量 actual review；PASS 后允许直接再次 `preview-open`。
- Preview loop 与 Formal candidate 分离；Preview 稳定后再统一正式 candidate/build/UAT。
