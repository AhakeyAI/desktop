# Codex、Kimi、Cursor、Zcode 最终协作方案

状态：生效
日期：2026-08-23
适用范围：AhaKey 统一固件、Studio、Runtime、AI Hooks 与后续客户端升级

## 1. 权威关系

1. [`unified-firmware-runtime-implementation-plan.md`](unified-firmware-runtime-implementation-plan.md) 是产品范围、依赖、WBS、批次和发布门禁的唯一事实来源。
2. 本文只定义协作、写入权、任务卡、交接和验收流程，不另立产品路线。
3. [`ahakey-runtime-architecture.md`](ahakey-runtime-architecture.md) 约束 Runtime 内部接口、安全与设备所有权。
4. 根目录 `kimi-codex-division-of-labor-proposal.md` 与 `cursor-codex-coordination-proposal.md` 是本方案的输入，不再作为执行依据。

当前批准基线为 `feat/unified-client` 的提交 `52177c2`。该提交已纳入 Hook/XPC wire 与 client seam；WBS 5.2 仍是“部分完成”，待 macOS 12 C libxpc 签名 server 和双签名进程 smoke。执行方不得再按旧草案把这些已提交文件当作未提交基线处理。

## 2. 角色与边界

| 角色 | 负责 | 明确不做 |
|---|---|---|
| 用户 | 产品取舍、范围扩张、实机窗口、发布与高风险外部操作的最终拍板 | 不承担日常 diff 协调 |
| Codex | 高复杂度架构、总计划、WBS 切片、任务卡、验收评审、冲突裁决、进度口径 | 不承担常规编码，不与执行方同时修改同批文件 |
| Kimi | 按任务卡实现、测试、逻辑提交、交付小结；优先承接 Runtime/协议/固件核心包 | 不扩范围，不自行改总计划，不静默修前置缺陷 |
| Cursor | 按任务卡实现、测试、逻辑提交、交付小结；优先承接 Studio/UI/安装升级/客户端 Hook 兼容包 | 不扩范围，不自行改总计划，不在没有路径白名单时开工 |
| Zcode | 按任务卡实现、测试、逻辑提交、交付小结；当前优先承接统一固件、平台动作与拨杆宏 | 不扩范围，不与 Cursor/Kimi 双写同一仓库路径，不越过任务卡状态开工 |

Kimi、Cursor 与 Zcode 均是执行方。“优先承接”只用于减少上下文切换，不形成永久代码领地；每个工作包仍由 Codex 指定唯一 owner。

### 2.2 2026-08-27 Zcode 加入与额度切换裁决

1. Kimi 因当前额度耗尽暂停承接新卡；其已 accepted 历史卡与提交归属不改写。
2. Zcode 立即接管独立固件仓 `/Users/heartline/Documents/Codex/AhaKey-X1-unified-firmware`，从 clean 基线 `9135183` 执行 WBS 1.4；Cursor 同期只执行客户端仓 HIL-CONFIG，两个写入白名单完全隔离。
3. WBS 1.5–1.7、WBS 2、WBS 3 的后续 owner 改为 Zcode，但只有当前置满足且任务卡由 Codex 翻为 `ready` 后才可开工。Zcode 不得因为 owner 已登记而越过依赖。
4. WBS 4、5.8–5.10、6.5–6.7 继续由 Cursor 主责；WBS 5A 与 WBS 6 资格验证预分配给 Zcode，保持 draft/USER-GATE，不在本轮提前启动。
5. Zcode 的完成、阻塞和裁决请求必须写入同一 `docs/collab/board.md`，格式与 Kimi/Cursor 相同；Codex 负责只读验收。

### 2.1 2026-08-24 调度裁决（验证环境分工）

1. Cursor 只承接验证必须发生在 Cursor IDE/CLI 进程内的卡；其余执行卡默认由 Kimi 承接。USER-GATE 仍归用户。`WBS-5.3-C-CURSOR` 不中途换手。
2. 交叉验收不变：Cursor 执行的卡由 Kimi 独立验收；Kimi 执行的卡由 Codex 验收。调度方不得验收自己写的业务实现。
3. Codex 统筹会话计划下线前须在 board 追加离线交接。超过 4 小时无复验时，Kimi 可发表只读复验意见；状态翻转仍须 Codex 上线确认。
4. 并行仍是例外：须用户明确要求或 Codex 证明路径白名单隔离。`5.3-C` accepted 后下一张仍按 queue 单通道晋级 `WBS-5.3-ORCHESTRATOR`，不自动多卡 active。

## 3. 单写者与隔离规则

1. 一个工作包、一个 owner、一个分支或 worktree、一个验收门禁。
2. 非 owner 对该工作包只有只读评审权；Codex 验收期间不直接修代码，而是退回具体 finding。
3. 两个执行方可以并行的前提是路径白名单不重叠、接口已冻结且没有同一测试夹具或同一文档写入冲突。
4. `docs/unified-firmware-runtime-implementation-plan.md` 和本文默认只由 Codex 更新。执行方只有在任务卡精确点名段落时才能修改。
5. 执行方不得把未提交改动留在共享分支后直接交给另一方。交接前必须提交到任务分支，或明确列出 stash/未跟踪文件及其归属。
6. 发现工作区与任务卡基线不一致时立即停手并回传，不自行 rebase、回退或覆盖他人改动。

## 4. 调度生命周期

```text
Codex 拆分并落任务卡
  -> 唯一 owner 在指定基线上执行
  -> owner 自验并提交交付包
  -> Codex 只读审查：接受 / 返工 / 阻塞 / 重新切片
  -> 接受后由 Codex 更新总计划与下一张任务卡
```

任务状态固定为：`draft -> ready -> active -> review -> accepted`，异常出口为 `blocked` 或 `superseded`。同一时刻只允许一张会触碰同一文件集的任务卡处于 `active`。

三方异步沟通统一使用 `docs/collab/`：

- `docs/collab/board.md` 是 append-only 消息板，承载进展、问题、决定、回复与交接；更正旧信息只能追加新条目，不能改写历史。
- `docs/collab/taskcards/<ID>.md` 保存正式任务卡。没有状态为 `ready` 的任务卡，不视为开工许可。
- 每一方开始工作前先读取 board 自己上次游标之后的内容和相关任务卡；结束或遇到阻塞前必须写回，不依赖用户在会话间传话。
- 被 `@` 且标记“需要回复”的一方，下一次进入仓库时应先回复再开工。Codex 负责把影响范围/WBS的决定同步回总计划。

## 5. 任务卡必填字段

```text
任务卡 ID：
计划/WBS 引用：
状态：draft | ready | active | review | accepted | blocked | superseded
执行 owner：Kimi | Cursor | Zcode
基线分支与提交：
目标切片（一句话）：
允许修改路径（白名单）：
禁止修改路径与禁止集成：
前置条件：
完成定义：
  - 针对性测试：
  - 全量测试/构建：
  - 无设备 smoke / 实机 HIL：
  - 文档更新责任：
中途检查点：
提交纪律：
回传要求：
```

任务卡必须把“能否改配置、能否改用户目录、能否安装/签名、是否需要真机”写清楚，不能用“按需处理”代替授权边界。

## 6. 执行回传包

```text
任务卡 ID：
结果：完成 | 部分完成 | 阻塞
基线与最终提交：
改动路径：
测试命令、环境与结果：
未执行的门禁及原因：
已知风险/兼容性：
前置缺陷或范围偏差：
工作区是否干净：
建议下一步（仅供 Codex 裁剪）：
```

Codex 的验收必须逐条映射任务卡完成定义，输出可定位到文件/测试/日志的 finding。没有证据的“看起来完成”不能更新 WBS 状态。

## 7. 开放问题的最终裁决

1. **checkpoint 时机**：旧 5.2 静态 seam 已在 `52177c2` checkpoint 提交；后续一律先在任务分支测试，通过任务卡的最小门禁后再提交，不接受共享分支上的大块未提交交接。
2. **签名 XPC 环境**：WBS 5.2 必须使用本机真实签名 Runtime/Studio 双进程 smoke；fake/in-memory 只能覆盖单测，不能替代 Team/Signing ID 正反向验证。证书内容不得写入日志或交付文档。
3. **前置缺陷处置权**：默认停下上报。只有任务卡预先授予“阻断缺陷预算”时，owner 才能在独立提交中修复直接导致本任务无法编译/测试的缺陷；产品语义、公共契约和数据迁移问题仍必须由 Codex 重新发卡。
4. **WBS 0.2 余项**：由 Codex 保留在总计划 backlog。Flash 地址/大小/占用静态调查可另发只读任务；HIL 由用户确认硬件窗口后发卡，不能混入 Runtime 工作包。
5. **当前下一刀**：按用户 2026-08-23 最新优先级，先由 Kimi 执行 `OPS-CURSOR-001`，只清理当前用户 Cursor 配置中的 AhaKey 阻塞 Hook，使 Cursor 恢复协作；完成后才由 Kimi 承接 WBS 5.2 libxpc 签名 server/smoke，随后由 Cursor 承接永久 WBS 5.3-C。临时环境修复不等于产品缺陷关闭。

## 8. 测试与实机责任

- 执行方负责跑任务卡内的可自动化测试并保留命令、版本与结果。
- Codex 负责定义门禁、审查证据和决定是否进入下一阶段，不代替执行方补跑遗漏测试。
- 用户负责提供或确认真实键盘、USB/BLE 组合与签名/安装环境的使用窗口。
- 环境或硬件不可用时状态只能是 `blocked` 或“部分完成”，不能用 mock 结果宣称 HIL 通过。
- 第一次真实键盘测试仍按总计划执行：WBS 5.2 签名 smoke 通过、WBS 5.3 接入现有 Agent 路径后、5.3 完成前。

### 8.1 Codex 事件驱动调度

- Codex 的主触发改为 `docs/collab/board.md` 文件事件监听，不再用固定 30 分钟模型心跳。监听器使用 macOS kqueue 阻塞等待文件变化，空闲时不轮询、不调用模型。
- Kimi 完成、阻塞或请求裁决时，必须在 board 末尾追加 `需要回复：是（@Codex）`。监听器捕获该 durable 事件后立即唤醒当前 Cursor 统筹会话；board 仍是事实来源，通知丢失时可以从历史恢复。
- 当前实现位于 `docs/collab/tools/watch_board_events.py`。它只读 board、在本地保存读取游标并输出唤醒 sentinel；不开放网络端口、不修改 Cursor Hook/权限配置。
- 监听器与当前 Cursor 会话同生命周期；Cursor 重启或会话结束后必须重新 arm。若监听器不可用，应在 board 明确记录并临时恢复低频心跳，不得同时运行重复 watcher/heartbeat。
- 发现交付或阻塞后，先在 board 末尾追加 ACK，再只读检查任务卡基线、提交、diff 和测试证据；不得代执行方修改业务代码。
- 每次验收记录 `lastReviewedCommit`，避免同一交付被重复处理。涉及产品取舍、实机窗口、签名/发布或高风险外部操作时升级给用户。
- 事件监听只消费 board 事件，不负责推导或创建下一张任务卡。一个连续实施序列已经得到用户授权时，Codex 将当前卡置为 `accepted` 的同一次调度中，必须二选一：创建下一张依赖已满足的 `ready` 卡；或在 board 明确写出暂停原因、恢复条件和责任方。禁止留下“已验收、无下一卡、无显式暂停原因”的隐性空档。
- 执行方的条件脚本返回 `false` 只表示当前没有属于它的可执行卡或待回复消息，不等于调度器故障。排障顺序固定为：先查任务卡状态与 owner，再查条件脚本真实返回值，最后才查定时器进程。

### 8.2 顺序执行队列

- `docs/collab/queue.md` 是任务卡的唯一顺序索引；产品范围和依赖仍以总计划为准。队列条目必须指向正式任务卡，不允许只在 board 口头排期。
- 默认单通道执行：同一时刻只放行一张 `ready/active/review` 卡，其余预建卡保持 `draft`。当前卡 `accepted` 后，Codex 在同一次调度中检查下一卡依赖并晋级为 `ready`。
- 标记 `USER-GATE` 的卡需要真实硬件、签名/安装、Beta/灰度或正式发布授权。它可以预建为 `draft`，但不得自动晋级；Codex 必须先取得用户对具体窗口和风险操作的确认。
- 若当前卡被 `blocked`，后续卡默认不越过依赖执行；只有 Codex 证明路径、接口和验收夹具完全隔离后，才可将另一张卡晋级为 `ready`，并在 board 记录原因。
- Kimi/Cursor 只执行 `ready` 或已由自己 ACK 的 `active` 卡；`draft` 是完整待办定义，不是开工许可。

## 9. 冲突与紧急处理

- 同一文件出现双写：双方立即停手，Codex 指定保留基线和唯一 owner。
- 任务卡与架构冲突：架构/总计划优先，执行方回传差异，Codex 修订后重新发卡。
- 测试红但疑似前置问题：保留最小复现和原始输出，不为了“常绿”删除测试或降低断言。
- Hook/Runtime 导致 AI 客户端无法读写：允许用户通过 Studio 的卸载/禁用入口恢复原生权限流；执行方不得直接静默改用户全局配置。
- 任何回滚都必须是可审计的迁移或反向提交，不使用破坏性 Git 命令处理共享工作区。

## 10. 生效与草案清理

本文落盘后即作为协作规范生效。根目录 Kimi/Cursor 两份草案保留为未跟踪输入，待各自 owner 确认最终方案已读取后再删除；在此之前不得提交为第二份权威方案。后续若修改角色或流程，由 Codex 更新本文并在总计划第 0 节记录，不复制出第二份“最终方案”。
