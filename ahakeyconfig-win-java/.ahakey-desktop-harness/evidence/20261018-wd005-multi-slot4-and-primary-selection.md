# WD-005 MULTI 槽位 4 误运行与主槽位屏幕边界

## Owner 本轮反馈

2026-10-18，Owner 要求记录：OLED 多任务区域增加轻提示，说明多任务展示开关在灯光页。建议文案：“多任务展示开关位于「灯光 → AI 运行展示」。”本轮仅登记，不修改 UI 或开启实现。

Owner 同时反馈：槽位 4 没有运行却偶发绿灯；在其亮绿时屏幕也显示已上传图片，担心非主槽位影响屏幕。产品预期仍为屏幕跟随主槽位，不能以现有兜底实现替代 Owner 预期。

本轮只读日志、用户运行绑定元信息、Codex SQLite 元信息及源码。未执行构建、应用、Hook、设备命令、固件操作或 Git 写操作。只追加本记录。

## 核对来源

- 运行包 token：preview-20261017T104547091113Z-0e6fcf。
- 应用日志：.ahakey-desktop-harness/previews/WD-005/preview-20261017T104547091113Z-0e6fcf/runtime-jar-classpath/logs/ahakey-studio.log。
- 对应冻结源码：同 token 的 source/src/main/java/com/example/ahakey/。
- C:\Users\20825\.ahakey\ai-runtime.json，读取时 displayMode=MULTI、primarySlotIndex=0。槽位 4 绑定 Codex 会话 01a1235a-b6ec-7981-881a-7f474c8bde6a，lastIdeState=USER_PROMPT_SUBMIT；槽位 1 已绑定当前 DLA。
- Codex logs_2.sqlite/state_5.sqlite 均使用 mode=ro 查询。槽位 4 会话在 state 表的 name 为 DLA-2、updated_at 为 2026-10-17 17:56:48；15:00 后该 thread_id 的 logs 记录为 0。无日志不是绝对未运行证明，但不支持它在此时真实启动。
- 固件只读 C:\Users\20825\Desktop\vibe-code\APP\services\display_presentation.c 与 APP/sub_main/main.c。当前源码解释不等于新核验了物理刷入字节。

## 0x99 实际快照

协议 version=1，每槽 valid/state/foreground；state 0=空，1=运行，2=等待，3=完成。

| 时间 | 完整发送帧 | 槽位 1 | 槽位 4 |
| --- | --- | --- | --- |
| 15:39:12.557 | AABB9901010301010300000000010300CCDD | valid=1, 完成, foreground=1 | valid=1, 完成, foreground=0 |
| 15:40:39.304 | AABB9901010301010300000000010100CCDD | valid=1, 完成, foreground=1 | valid=1, 运行, foreground=0 |
| 15:40:48.019 | AABB9901000001010300000000010100CCDD | valid=0, 空, foreground=1 | valid=1, 运行, foreground=0 |
| 15:40:52.914 | AABB9901000001010300000000010100CCDD | valid=0, 空, foreground=1 | valid=1, 运行, foreground=0 |
| 15:41:40.724 | AABB9901010101010300000000010100CCDD | valid=1, 运行, foreground=1 | valid=1, 运行, foreground=0 |

各条发送后日志都有 0x99/00 成功 ACK。15:40:39 由 hook-dispatch 下发，15:40:48/52 为 ai-runtime-apply。

确定事实：上位机确实将槽位 4 标成 RUNNING 并发送给固件，不是只观察到灯珠自行异常。此时并未把 foreground 改成槽位 4。

## 槽位误匹配候选原因

冻结 AiRuntimeDisplayService.handleHookEvent 在精确 session_id/transcript 匹配失败后（约 324 行）仍调用 uniqueLocationSlotForPlatform，按 cwd/projectName 唯一目录匹配槽位；即使事件携带不相符的会话 ID 也可能进入此分支。其无身份终态还有另一路兜底。

这是明确存在的跨会话归属风险，不符合此前“槽位对应具体会话，不按项目兜底”的 Owner 要求。不能以只匹配一个目录槽位就认为身份正确。

同一时间 Codex 日志显示：15:40:22 后台会话 01a14df4-5a2a-7b83-8856-8faa311e3e1c 以 composer_predictions 启动，15:40:37/39 有 world_state.build。它与槽位 4 绑定 ID 不同，时间与槽位 4 RUNNING 下发相近。

应用日志没有保存原始 Hook session_id、cwd 与所走匹配分支，且实际 appliedSlots 历史没有完整快照，因此只能判为高置信串槽候选链，不能宣称已逐包证明该后台会话经 cwd 命中了槽位 4。当前诊断自身也触发当前 DLA 的正常 Hook，不混作空闲证据。

另一个延续机制：applyToKeyboard/prepareApply 会带入绑定中保存的 lastIdeState；四槽全量快照在其他槽变化时重复携带槽位 4 RUNNING，能持续保留被污染的运行事实。仅切模式或重新应用不等于重新确认会话是否实际运行。

## 屏幕为何可能跟随槽位 4

固件 display_presentation_select（约 194 行）先找 valid && foreground，找不到时按 WAITING、RUNNING、DONE 兜底选择其他有效槽位。

- 15:40:39：槽位 1 valid=1、foreground=1、DONE。按当前源码应选择主槽位 1 的已完成状态，槽位 4 运行不会抢占。
- 15:40:48/52：槽位 1 foreground=1 但 valid=0。主槽位不参与选择；槽位 4 是唯一运行中槽位，所以按当前源码会回退选择槽位 4。
- 15:41:40：主槽位 1 又 valid=1、RUNNING，屏幕选择回到槽位 1。

因此“主槽位暂时没有运行态时仍绝不跟随别槽”在当前两端实现中不成立。这是主槽位空状态与固件兜底策略的对接边界，不宜直接归为用户看错或仅修改 foreground 就解决。

MULTI 的 OLED 上传资源只有全局运行中/等待中/已完成三项（entry 16/17/18），不是四槽各一套。看到同一张已上传图片不能独立证明当前屏幕来源；应结合该时刻各槽状态和选槽规则判断。尚无精确录像/截图时间，不能保证 Owner 看到的那一帧恰在 15:40:48。

## 状态与后续

- OLED 引导提示：已记录待实现建议。
- 槽位 4 误运行：OPEN；主机发送错误运行事实已确认，事件归属根因待补证。
- 主槽位无有效运行态时屏幕回退：OPEN；当前协议输入与源码行为已对照，未做动态设备复现。
- 不关闭等待中、MULTI 或整体 UAT；不自动改代码、清配置、重新绑定或更新固件。
- 后续修复需保持明确会话身份、排除后台事件污染，并协调“主槽位空状态”的展示语义；不得删掉安全保护或凭历史 lastIdeState 冒称实时运行。
