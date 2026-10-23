# WD-005 SINGLE 工作中资源成功与空闲亮灭调查

## Owner 实际测试反馈

2026-10-18，Owner 对 SINGLE 工作中图片上传与触发测试反馈：

> 这个是成功的，在工作中的时候，屏幕会显示我选的图片

记录为该单项 Owner Preview 实测成功：SINGLE 工作中资源上传后，任务工作时显示所选图片。不扩大为等待中、已完成、MULTI、上传可靠性或正式 UAT 全部通过。

## 另一个未关闭问题

Owner 报告：没有可见 Codex 任务运行时，键盘仍反复显示工作中，然后熄灭。

本轮只读实际 Preview 应用日志、冻结源码和 Codex SQLite 日志元信息。没有执行 Hook、应用、设备命令或修改生产代码/配置/固件。仅追加本记录。

应用日志来源：.ahakey-desktop-harness/previews/WD-005/preview-20261017T104547091113Z-0e6fcf/runtime-jar-classpath/logs/ahakey-studio.log。
Codex 日志来源：C:\Users\20825\.codex\logs_2.sqlite，使用 sqlite3 URI mode=ro 查询 logs 表。

### 已确认的协议事件

以下均为 2026-10-18 本地时间，发送线程为 hook-dispatch：

| 时间 | 下发 | IDEState |
| --- | --- | --- |
| 15:26:35.015 | AABB9007CCDD | USER_PROMPT_SUBMIT |
| 15:26:56.047 | AABB9005CCDD | STOP |
| 15:27:13.571 | AABB9007CCDD | USER_PROMPT_SUBMIT |
| 15:27:35.271 | AABB9008CCDD | SESSION_END |
| 15:27:49.955 | AABB9007CCDD | USER_PROMPT_SUBMIT |
| 15:28:27.466 | AABB9008CCDD | SESSION_END |
| 15:28:54.129 | AABB9008CCDD | SESSION_END |
| 15:29:04.214 | AABB9008CCDD | SESSION_END |
| 15:30:20.771 | AABB9007CCDD | USER_PROMPT_SUBMIT |

因此观察时段不是只有固件在无输入情况下自行闪动；主机确实下发了多次状态变化。7 映射为工作中，不能把每次亮灯都解释成 PreToolUse（码 3）。

### 后台会话线索

Codex logs 表 target=codex_core::session::handlers 的实际记录包含 turn_trigger=Some("composer_predictions")：

| 时间 | thread_id |
| --- | --- |
| 15:25:22 | 01a14de6-9f58-7601-b50d-b9c8cb47b84d |
| 15:26:17 | 01a14de7-75af-7eb3-8a85-b47381933e95 |
| 15:26:56 | 01a14de8-0f9d-7740-83ad-26c345a1d3b6 |
| 15:27:33 | 01a14de8-9e71-79a3-b91f-aeff2cbfff5f |
| 15:30:03 | 01a14dea-e9cb-75d2-9076-288f6b943dd6 |

15:27:13 和 15:27:50 上述两个后台会话有 world_state.build 记录，与 0x90/07 时间邻近；其 Shutdown/Agent loop exited 在 15:28:27、15:29:04，与 0x90/08 时间吻合。

冻结 source/src/main/java/com/example/ahakey/service/AiRuntimeDisplayService.java:276 起，SINGLE 分支直接发送 state.getCode()，不按 session_id、平台或来源类别过滤/聚合。HookDispatchServer 的事件表将各工具事件映射到相同 IDEState。故后台会话若触发 Hook，将同样驱动全局 SINGLE，其他会话结束也可能覆盖正在工作的会话状态。

固件只读 APP/sub_main/main.c 的 claude_state_to_ai_oled_state 将 UserPromptSubmit/PreToolUse/PostToolUse 映射到工作中，将 Stop/SessionEnd 映射到完成。未据此单独证明每次全灭对应哪个物理灯效配置。

### 结论与限制

- 高置信候选原因：Codex 后台 composer_predictions 会话的 Hook 活动进入了未过滤来源的 SINGLE 全局状态流，造成无可见任务时的工作中/结束交替。
- 确认的是后台会话存在、相近时间主机下发对应状态、SINGLE 不过滤来源。应用日志未保存接收事件的 session_id/平台/turn_id，尚不能逐包唯一归因，不宣称完成动态复现或根因修复。
- 15:31 后当前 DLA 为调查使用工具也可能产生正常 Hook，不能将本轮诊断自身的事件当成空闲误触发证据。重点使用调查前的 15:27-15:30 时间窗。
- Codex 另有 legacy_notify 的 os error 206；配置目标是 codex-computer-use.exe turn-ended，不是 AhaKey Hook。没有证据将该错误认定为本次亮灭主因，不修改该配置。
- 后续修复应先补足来源关联证据，确认可识别的用户会话/后台会话边界，并保护正常真实任务与结束状态，不可直接屏蔽所有 UserPromptSubmit 或 SessionEnd。
- 本问题保持 OPEN。Owner 当前要求先实验，不自动改 Hook、停后台服务或改变 SINGLE 产品语义。

## Owner 后续反馈：SINGLE 已完成图片

2026-10-18，Owner 原文：

> 现在single模式停下来的时候，会显示我上传的已完成的照片。接下来我们测什么呢？

记录为 SINGLE 停止后显示自定义“已完成”图片这一单项 Owner Preview 实测成功。与此前“工作中”图片成功分开记录；未据此宣称所有结束事件、等待中、MULTI 或正式 UAT 通过。后台预测会话干扰和上传异常仍保持 OPEN。本轮仅追加记录，不修改代码或操作设备。
