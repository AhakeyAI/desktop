# 语音写入拒绝与写入期间编辑锁定 — 2026-11-02

## 现场与结论

Owner在build529／297B上把Codex Voice由Consumer改为Right Alt：两次黄色未确认、没有成功弹窗，重读仍为Consumer；后来保存成功。写入过程中误改为Left Shift，实际写入仍为提交时的Right Alt。

两件事分开处理：

- 固定提交快照的行为正确，不应把提交后的临时草稿改动悄悄写进设备；但界面和输入必须锁定，避免用户误解。这一客户端缺陷已修复。
- 15:02:44的0x9E/0x22与15:03:49的0x9E/0x21均返回status1，说明设备确实拒绝事务，不能用UI误编辑解释全部失败。无当次完整分包／固件trace，不断言唯一根因。

## 客户端可重复反馈环与修复

将原KeyCaptureOverlay原样抽离到独立文件，使用NSHostingView承载真实控件并施加SwiftUI disabled；直接向该视图发送隔离测试事件，不注入系统键盘。旧代码1测试2失败：禁用后Right Alt草稿仍被改写为A、仍接受第一响应者。修复后同一测试通过。

修复包括：将环境isEnabled传给AppKit视图，拒绝禁用期间的鼠标／键盘／修饰键事件；取消180ms延迟修饰键捕获、退出第一响应者；销毁时撤销回调；禁用后清除录入状态。写入任务创建即计入组件busy，锁定按键编辑、模式／组件切换和重复提交；草稿setter再做busy防护，拦住迟到菜单回调。提交快照和设备确认机制保留。

新增3项测试覆盖禁用控件不改值、排队Left Shift在锁定后不落入草稿、解锁后正常捕获。41项专项与967项完整测试通过；原红例、专项／全量日志私密保存。没有为复现执行新的键位写入。

## 固件的独立确定性复现

固定fe22786的command_link_lost仍在检查live／transitioned之前无条件清除s_k1_route_tx.active；此前K1修复仅把输入capture清理移入transitioned。main.c在没有USB电源时的每秒分支调用command_link_lost(1)及usb_reset_runtime_state，后者再次调用该函数。已离线USB轮询可打断另一通道的BLE路由事务。

[诊断C探针](../validation/connect-talk-hil-2026-10-22/firmware-offline-usb-route-probe.c)包含该实际函数，IRQ／调度函数为stub；BLE live=1、USB live=0、route active=1，调用后active变0，稳定返回预期诊断失败。此处是源码行为证明，不是完整硬件时序复现或已经修复的固件。

复现：用clang编译该C文件并执行，当前候选预期退出1，输出“FAIL: already-offline USB poll cleared active BLE route transaction”。文件不加入正常客户端CI通过项，也不在用户固件工作区修改生产源码。

已追加[固件Issue7／FW-14](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/7#issuecomment-6571464234)：按事务owner transport／generation清理，已离线USB不能清除BLE事务，真实owner断开／空闲超时等仍须正常工作。未自动重试写入、未改或刷入新固件，不能声称该拒绝已被客户端修复。

## 上传取消提醒

前一提交7aafb583已添加写入前说明、进度下方风险提示、取消后弹窗和持续未确认恢复指引；取消先立即停止后续发送，再显示提示。准备文件／普通读取取消不弹上传取消提示，恢复默认不套用上传前警告。中英文生成器同步维护，避免构建时覆盖翻译。本轮不再故障注入取消上传。

## 交付与限制

修复源码58caafc8，签名build531覆盖安装成功，旧529保留；15项用户偏好语义完全一致、4项既有草稿保留。原UI只读显示Codex Voice为Right Alt，未再改写。Agent恢复实时连接；Kimi Code Desktop当前未运行，已有1项授权保留、租约与待恢复0，不声称该端此时已同步。

新提测包及CI见[候选回执](../validation/connect-talk-hil-2026-10-22/local-candidate-build531-2026-11-02.json)。未进行带真实写入的界面锁定HIL；准确的禁用输入回归由NSHostingView测试证明，固件事务修复及真实写入稳定性仍待。
