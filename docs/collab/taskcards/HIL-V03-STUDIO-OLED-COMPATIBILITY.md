# 任务卡 HIL-V03-STUDIO-OLED-COMPATIBILITY：正式 Studio × 旧固件图片写入矩阵

计划/WBS：v0.3 客户端 OLED HIL
状态：`ready / C5 preflight @ 30cfeb8`
执行 owner：Cursor
只读验证：Zcode；Codex 验收
依赖：`V03-STUDIO-OLED-LEGACY-COMPATIBILITY` accepted
基线：从该卡 accepted 产品提交冻结签名 HIL 候选；不得使用专用 desired-config 驱动替代正式 UI

## 目标

用正式 Studio UI 和正式 Runtime，在所有已登记旧固件上证明图片写入兼容；不刷统一固件。该卡只执行与取证，不在 HIL 现场修改业务代码。

本卡同时是页面级写入模型的 C5 验收：验证“当前页 dirty-only、每页独立 operation、底部设备 FIFO、断连续传、三级 baseline 与严格 no-op”，不得只证明底层 HIL driver 能写图。

## 矩阵

1. **GitHub Standard `3e7f900`**：写入一组可识别图片；确认正确显示、切换（若固件支持）和 5 秒断电保持；日志证明未发送不支持 opcode。
2. **Gitee Rhino `53cd0a97`**：先写 A，再由正式 Studio 只写 B；operation completed、字节进度到 total、A 未覆盖、A/B 可切换；断电后两套均保留；断连后自动恢复。
3. **Local Rhino `00eb7efc`**：重复 A/B scoped 写入、切换、断电保持与自动重连。
4. 每一族至少覆盖 PNG、JPEG、动态 GIF；包含 >2 MiB/120 帧源图的 160×80 规范化路径，以及超限/损坏输入的零写入拒绝。
5. 对未知或畸形 capability fixture 只做 host/模拟负向，不拿真机冒险写入。
6. **页面 scope**：屏幕页分别覆盖 A-only、B-only、A+B 同时 dirty；A+B 都写但只激活当前套。另造按键页或灯条页 dirty，证明屏幕 operation 不读取、不组包、不写入其他页。
7. **严格 no-op**：当前页与 `verified` 或同次 `writeConfirmed` 基线相同时，operation/CAS/WAL/设备命令均为 0；不得仅以 UI 无变化代替计数证据。
8. **队列与页面锁**：至少两个不同页面各建 operation，底部 FIFO 顺序可见；当前页排队即锁、其他页仍可编辑；queued 可移除，running 不显示普通取消。
9. **断连续传**：同一设备/同一语义 fingerprint 在资源中段断连，重连后保持同一 UUID、只续传未确认字节；不同设备或协议语义变化必须停止。另覆盖断连超过 60 秒后的“放弃未完成写入”。
10. **部分成功与旧固件**：制造永久失败，证明 fail-fast、已确认字段入 baseline、剩余字段仍 dirty、重试只发剩余差异。不可读回旧固件显示 `writeConfirmed`；可读回时升级为 `verified`，不一致则冲突。

## 证据要求

- 固件来源 SHA、HEX SHA、刷入前后备份与 EEPROM 初态；每次换固件/擦 EEPROM 都是单独 USER-GATE。
- App/Runtime 版本、产品 commit、签名身份、PID、唯一 owner、XPC handshake 和设备 identity。
- 每次 operation UUID、planner profile、实际 opcode 序列、WAL 终态、steps、completed/total bytes、Studio 截图、键盘目视结果。
- 每次记录 page/object ID、冻结 field mask、stable device ID、语义 compatibility fingerprint、开始前对象 CAS 结果，以及逐字段 baseline 前后状态（verified/writeConfirmed/unknown）。
- A/B 写入前后与断电后的照片/视频或逐项人工记录；自动重连时间线。
- 旧 Rhino 键盘 `0,0` 单列为已知固件显示限制，不得覆盖 Runtime 字节进度证据。
- 每次结束恢复官方 Runtime；临时 label、进程、挂载、候选和日志目录均有清理证明。

## 停止条件

- capability 路由与预期不一致、发送了该固件未登记 opcode、现存图片被意外覆盖、WAL/设备结果矛盾、签名/XPC/唯一 owner 漂移时立即停止。
- 发现产品缺陷时另开最小返工卡；不得在本 HIL 卡内顺手改代码。
- 断电、固件切换、EEPROM 擦除、安装与签名均须用户在对应步骤明确批准。
- 发现 Studio 首次连接自动创建 operation、补写默认值或触发 CAS/WAL 时立即停止；出厂默认由固件负责，不得在客户端 HIL 中补救。

## 完成定义

三类旧固件的正式 UI 矩阵及 C5 页面事务矩阵全绿，兼容清单与已知限制可直接用于公开 v0.3 文档。通过后开放 `HIL-RELEASE-0.3` 客户端候选冻结；`HIL-CONFIG` C1-C6 和统一固件刷机仍为独立后续门禁。

## 执行记录（append-only）

等待客户端实现卡 accepted 与用户逐次开放固件/EEPROM/断电窗口。

### [2026-09-07 19:04] Codex：用户授权开启 C5，先进入非破坏 preflight

- C1–C4 已 accepted @ `30cfeb8`；C5 正式开放，Cursor 为执行 owner，Zcode 只读验证固件事实，Codex 验收。Agent Relay 保持暂停，以本卡/queue/board 手工记录为准。
- 第一段只允许 non-destructive preflight：固定产品 commit `30cfeb8`；复验 App/Agent Release、版本/签名计划、XPC handshake/唯一 owner；准备可识别 PNG/JPEG/动态 GIF、>2 MiB/120 帧、超限/损坏输入与逐项取证模板；只读核对当前设备 identity/固件/已有图片/EEPROM 初态与三族固件来源 SHA/HEX SHA。
- 使用正式 Studio UI + 正式 Runtime，禁止用专用 desired-config/HIL driver 代替。本卡不改业务代码；发现产品缺陷立即停手，另开最小返工切片。
- **仍需逐次用户授权**：签名/打包/安装候选、每次固件切换或刷入、EEPROM 擦除，以及每个真断电保持窗口。未获对应授权前只做上述 preflight，不 overlay `/Applications`，不 kickstart，不刷机，不擦 EEPROM，不 push。
- preflight 完成后停手提交候选 identity、三族执行顺序、风险/回滚点与下一个精确 USER-GATE；不自动进入签名/安装/设备写入。

- 需要回复：是（@Cursor ACK 后仅执行 C5 preflight）

### [2026-09-07 19:12] Cursor ACK：开始 C5 非破坏 preflight

ACK 用户 19:07 确认并开启 C5。C1–C4 accepted @ `30cfeb8`；本卡 `ready / C5 preflight @ 30cfeb8`。执行 owner Cursor。Agent Relay 继续暂停。未伪造 Relay `review_decision`。未改 queue/status。
仅执行 Codex 19:04 列出的非破坏 preflight。不 overlay `/Applications`、不 kickstart、不刷机、不擦 EEPROM、不 push、不签名/打包/安装候选。完成后停手提交候选 identity、三族顺序、风险/回滚与下一精确 USER-GATE。

### [2026-09-07 19:25] Cursor：C5 非破坏 preflight 完成，停手

产品冻结 `30cfeb8`。App+Agent Release 与 `check-release-identity.sh` 通过；本地 Release 仍为 adhoc。现网唯一 owner 正式 `lab.jawa.ahakeyconfig.agent` pid 65466 / runs=1，HIL rc=113；既有 Developer ID smoke client handshake+snapshot `RESULT: ok`，未 kickstart。已安装仍为 0.2.1 (362) / `1ed560b`。AhaKey 505C 未连接。三族 HEX：Gitee `ace7ab3e…`（与 2026-09-02 已刷一致）、Local `7a49f365…`、GitHub `e5a336a6…`。素材与取证模板已准备。
阻塞：生产 `AhaKeyReleaseFeaturePolicy.current` 仍为 `.v0_2`，正式 Studio UI 不开放图片面；本卡不改业务代码。
证据 `docs/collab/evidence/HIL-V03-STUDIO-OLED-20260907/00-c5-preflight.md`。未 overlay `/Applications`、未 kickstart、未刷机、未擦 EEPROM、未 push、未签名/安装。未改 queue/status。未伪造 Relay review_decision。
下一精确 USER-GATE：**USER-GATE-C5-POLICY**（另开最小切片开放 `.v0_3` 发布通道）。其后才是隔离签名/HIL 安装。
需要回复：是（@Codex 验收 preflight 并开放下一 USER-GATE）
