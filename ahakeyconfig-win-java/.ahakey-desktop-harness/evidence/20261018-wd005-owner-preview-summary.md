# WD-005 Owner Preview 阶段汇总

日期：2026-10-18。当前包：preview-20261017T104547091113Z-0e6fcf。

Owner 最新判断：整体功能看起来基本可用，希望汇总问题，并补足灯光右侧三个区域之间的关系提示。本记录不把该判断扩大为正式 UAT/所有验收通过，不改变 Harness 路由或授权实现。

## 已有实际反馈

- 默认屏幕首次上传失败，手动重试后 Owner 报告成功，日志有 Commit 成功 ACK；首次失败仍未解决。
- USB 拔插后灯光恢复正常；这是恢复验证，不是缺陷已修复。
- SINGLE 工作中：上传的自定义图片在任务工作时显示，Owner 实测成功。
- SINGLE 已完成：停止后显示上传的已完成图片，Owner 实测成功。
- SINGLE 等待中：Owner 明确后置，尚未测试。
- MULTI：已有实际快照与灯光/屏幕观察，但会话误匹配和主槽位边界未通过，不能登记整体通过。

## 待处理问题

| 编号 | 问题 | 已知证据/限制 |
| --- | --- | --- |
| UI-01 | OLED 资源框白字浅背景，可读性差 | Owner 截图；尚未修复 |
| LOG-01 | 终端日志中文乱码 | 终端粘贴乱码，应用 UTF-8 文件可正确读取；不能直接认定日志源文本损坏 |
| UP-01 | 默认资源首次 Begin 失败，重试成功 | 0x8A/01 后一轮 0x8A/00、0x8C/00；最初失败根因未定 |
| UP-02 | SINGLE 上传分块中断，运行态状态下发被保护状态暂停 | 63 个 chunk ACK 后超时，本地 FAILED；USB 重连恢复灯光；原始超时责任侧未定 |
| FB-01 | SINGLE 未发送却可能回复已更新 | 冻结代码忽略 sendRuntimeState 的 false；明确静态反馈缺陷 |
| RT-01 | 无可见任务时 SINGLE 反复工作中/结束 | 后台 composer_predictions 与 0x90 变化时间关联；无逐事件身份日志，候选因果待补证 |
| RT-02 | MULTI 槽位 4 无真实任务却变 RUNNING | 0x99 明确下发槽位 4 RUNNING；匹配失败后的 cwd 兜底存在跨会话风险，具体来源链待补证 |
| RT-03 | 主槽位运行态为空时屏幕会跟随其他槽位 | 日志有 foreground=1/valid=0；固件只优先有效主槽，之后回退其他槽；与 Owner 仅跟随主槽预期有边界差异 |
| UI-02 | OLED MULTI 页面缺少切换入口指引 | Owner 要求轻提示：多任务展示开关在灯光页；不是把 OLED 资源标签改成模式开关 |
| UI-03 | 灯光右侧展示模式/亮度/SINGLE 状态灯效三个区域关系不清 | Owner 本轮新增反馈，见下文 |

## 灯光右侧语义与待设计提示

Owner 反馈：上部多任务、中部亮度、下部单任务灯效分别能使用，但用户可能不知道三者关系；第三块 AI 灯效缺少醒目的适用范围提示。

冻结 InspectorPane.createLightGroup 的实际结构是 createAiRuntimeGroup、brightnessBox、statesBox。第三块遍历 IDEState 的九种状态，并按当前 Mode 保存。其末尾已有“Mode N · SINGLE AI 状态灯效”，但位置靠后，顶部范围信息不足；不能把此反馈记成代码完全没有任何提示。

后续设计需要清楚表达以下事实，标题/文案为建议，尚未实施：

1. **AI 展示模式**：SINGLE/MULTI 是全局运行展示选择；MULTI 的槽位绑定与主槽位属于这里。不要与键盘 Mode 1-4 混为一谈。
2. **全局灯光亮度**：不是某个任务槽独有，也不是下方 SINGLE 九状态的单项配置；应表达对 SINGLE/MULTI 的全局亮度范围。
3. **SINGLE 状态灯效 · 当前 Mode**：下方九项只定义该 Mode 下 SINGLE 各细分 AI 状态的灯效，不是 MULTI 四槽颜色的配置入口。
4. MULTI 使用中，第三块仍可作为 SINGLE 配置编辑区，但应在标题附近清楚标注仅 SINGLE 生效。是否折叠/禁用等交互变化未获确认，不自动增加这类改动。
5. OLED 的 SINGLE/MULTI 标签是在选择上传资源类别，不是运行展示开关；MULTI 三份图片是全局状态资源，不是每槽各自一套图片。

建议轻提示内容：“多任务展示开关位于「灯光 → AI 运行展示」。”第三块建议范围标记：“仅 SINGLE 生效 · 当前 Mode”。不以长篇说明或新面板扩大此次边界。

## 后续优先级与授权

先定位 UP-01/02 与 RT-01/02/03，修复时保留事务互斥、未知 ACK 隔离、原 WS001-004 行为和会话级身份约束；不得仅删除保护门禁来恢复灯光。FB-01 与错误可见性需要一起覆盖。

可读性、编码与上述范围提示作为独立小项处理。等待中及尚未完成的验收保留待测。本轮只汇总记录，不修改代码、不构建、不写设备、不更新 Hook、不改固件、不执行 Git 写入。

## 原始记录

- 20261018-wd005-preview-readability-owner-feedback.md
- 20261018-wd005-default-upload-retry-owner-feedback.md
- 20261018-wd005-single-runtime-after-upload-timeout.md
- 20261018-wd005-single-working-pass-and-idle-hooks.md
- 20261018-wd005-multi-slot4-and-primary-selection.md
