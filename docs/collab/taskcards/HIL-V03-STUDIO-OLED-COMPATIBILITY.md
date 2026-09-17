# 任务卡 HIL-V03-STUDIO-OLED-COMPATIBILITY：正式 Studio × 旧固件图片写入矩阵

计划/WBS：v0.3 客户端 OLED HIL
状态：`blocked / R6 physical mismatch; R7 USER-GATE not opened`
执行 owner：DSH
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

### [2026-09-07 19:25] Codex：C5 preflight 验收通过，停在 `USER-GATE-C5-POLICY`

- 证据与产品路径一致：`AhaKeyReleaseFeaturePolicy.current == .v0_2`，生产 Studio/Facade/Agent 均消费该投影；原样签名安装 `30cfeb8` 不会显示/允许图片写入，无法执行 C5 正式 UI 矩阵。这是产品 policy 门，不是 HIL 环境误判。
- `USER-GATE-C5-POLICY` 若获用户授权，只开一个最小产品切片：新增 `.v0_3` 或等价 compile-time 发布通道，将 production `current` 切到该通道；仅对 C1 已密封且 C2/C3 支持的 Standard/Rhino/current profile 开放 default/task picture + resource package。`negotiating`、malformed/truncated、unknown/no-proof 仍全部 fail-closed，keys/light 资格不回退。
- 保留 `v0_2` 策略与全矩阵不变；新增 v0.3 的 Standard no-response+strict legacy-picture proof、Rhino parsed、current session、negotiating/malformed/unknown 反例，并覆盖 Studio visibility、Facade resource admission 与 Agent preflight 三个真生产消费点。禁止用 `picturesUnrestrictedForTests` 接入生产。
- 白名单限 `AhaKeyReleaseFeaturePolicy.swift`、必要的 release-policy/Studio derivation/facade/Agent 精确测试，以及必要的 compile 修正。不改 C2 assembler 决策、C3 WAL/CAS/事务转移/BLE executor，不改 View 交互，不改签名/安装器/固件。产品版本/ReleaseIdentity 如需改动必须在提交中明确说明 HIL pre-release 身份，不得偷渡签名/安装授权。
- 切片需复跑策略全矩阵、Studio/Facade/Agent 定向、全量 Swift、App+Agent Release、`git diff --check`，然后停手提审。即使通过，也不自动签名/打包/安装；下一门仍是 `USER-GATE-C5-SIGN-HIL`。
- 需要回复：是（等用户明确授权 `USER-GATE-C5-POLICY`）

### [2026-09-07 19:25] Codex：用户已授权 `USER-GATE-C5-POLICY`

- 产品改动转独立 `V03-C5-RELEASE-FEATURE-POLICY` 任务卡，状态 `ready`。本 HIL 卡保持阻塞，等 C5P accepted 后再请求 `USER-GATE-C5-SIGN-HIL`。
- 当前不签名/打包/安装，不 overlay/kickstart，不设备写入/刷机/EEPROM/断电/push。
- 需要回复：否（转 C5P 任务卡执行）

### [2026-09-07 20:43] Codex：C5P 未验收，HIL 继续等 C5PR1

- C5P 策略矩阵主干通过，但 Facade 仍有 public Bool override、caller page-profile 授权与 no-proof resource/package 入口绕过。产品卡退回 C5PR1。
- 本 HIL 卡继续 `blocked / awaiting C5PR1 acceptance`；`USER-GATE-C5-SIGN-HIL`、签名/打包/安装/overlay/kickstart/设备写入/固件/EEPROM/断电/push 全部关闭。
- 需要回复：否（等 C5PR1）

### [2026-09-07 21:17] Codex：C5PR1 未验收，HIL 继续等 C5PR2

- C5PR1 已封闭入口时的 public Bool/caller-profile/no-proof 绕过，但 sealed admission 可在 normalization/prepare 的 actor `await` 期间过期，且 public direct ingest 没有 target binding；产品卡退回 C5PR2。
- 本 HIL 卡继续 `blocked / awaiting C5PR2 acceptance`；`USER-GATE-C5-SIGN-HIL`、签名/打包/安装/overlay/kickstart/设备写入/固件/EEPROM/断电/push 全部关闭。
- 需要回复：否（等 C5PR2）

### [2026-09-08 00:56] Codex：C5PR2 未验收，HIL 继续等 C5PR3

- Facade 本地重核与 typed picture intent 已成立，但 resource ingest wire 仍不携 target/admission，且 identity 缺少 connection generation；同 UUID ABA 与 ingest-in-flight CAS 尚未封闭。产品卡退回 C5PR3。
- 本 HIL 卡继续 `blocked / awaiting C5PR3 acceptance`；`USER-GATE-C5-SIGN-HIL`、签名/打包/安装/overlay/kickstart/设备写入/固件/EEPROM/断电/push 全部关闭。
- 需要回复：否（等 C5PR3）

### [2026-09-08 12:48] Codex：C5PR3 未验收，HIL 继续等 C5PR4

- typed generation token 已进入 Runtime wire，但 Agent token 校验与 Store CAS/WAL 之间仍有 suspension，尚无共享 fence/线性化点；产品卡退回 C5PR4。
- 本 HIL 卡继续 `blocked / awaiting C5PR4 acceptance`；`USER-GATE-C5-SIGN-HIL`、签名/打包/安装/overlay/kickstart/设备写入/固件/EEPROM/断电/push 全部关闭。
- 需要回复：否（等 C5PR4）

### [2026-09-08 14:46] Codex：C5PR4 未验收，HIL 继续等 C5PR5

- Store 写已进入 reservation fence，但真实 BLE generation/fact mutation 先发生、fence publish 后异步排队，仍有旧 token 窗口；产品卡退回 C5PR5。
- 本 HIL 卡继续 `blocked / awaiting C5PR5 acceptance`；`USER-GATE-C5-SIGN-HIL`、签名/打包/安装/overlay/kickstart/设备写入/固件/EEPROM/断电/push 全部关闭。
- 需要回复：否（等 C5PR5）

### [2026-09-08 15:41] Codex：C5PR5 未验收，HIL 继续等 C5PR6

- 主要连接/OLED mutation 已进 fence，但 Bluetooth unavailable/shutdown 仍绕过 admission 撤销，且 pre-write 失败会泄漏 reservation；产品卡退回 C5PR6。
- 本 HIL 卡继续 `blocked / awaiting C5PR6 acceptance`；`USER-GATE-C5-SIGN-HIL`、签名/打包/安装/overlay/kickstart/设备写入/固件/EEPROM/断电/push 全部关闭。
- 需要回复：否（等 C5PR6）

### [2026-09-08 16:18] Codex：C5PR6 未验收，HIL 继续等 C5PR7

- unavailable/shutdown 的同步 revoke 与 reservation cleanup 已成立，但迟到 deviceChanged publication 仍可从残留投影复活旧 token；产品卡退回 C5PR7。
- 本 HIL 卡继续 `blocked / awaiting C5PR7 acceptance`；`USER-GATE-C5-SIGN-HIL`、签名/打包/安装/overlay/kickstart/设备写入/固件/EEPROM/断电/push 全部关闭。
- 需要回复：否（等 C5PR7）

### [2026-09-08 19:53] Codex：C5PR7 未验收，HIL 继续等 C5PR8

- post-ticket stale publication CAS 已成立，但 ticket 在 mutation 后另行采样，可借用较新的 revoke epoch；产品卡退回 C5PR8。
- 本 HIL 卡继续 `blocked / awaiting C5PR8 acceptance`；`USER-GATE-C5-SIGN-HIL`、签名/打包/安装/overlay/kickstart/设备写入/固件/EEPROM/断电/push 全部关闭。
- 需要回复：否（等 C5PR8）

### [2026-09-08 20:40] Codex：C5PR8 Spec 通过，HIL 继续等机械 C5PR9

- Causal ticket 行为已通过；仅剩公开 ticketless admission publish 的类型级绕过需删除/收窄。
- 本 HIL 卡继续 `blocked / awaiting C5PR9 acceptance`；`USER-GATE-C5-SIGN-HIL`、签名/打包/安装/overlay/kickstart/设备写入/固件/EEPROM/断电/push 全部关闭。
- 需要回复：否（等 C5PR9）

### [2026-09-08 23:34] Codex：C5PR9 accepted，停在 `USER-GATE-C5-SIGN-HIL`

- 产品策略卡 accepted @ `99a5b01`；正式 v0.3 图片面、Facade sealed admission、Runtime generation/token/fence/publication 因果链已通过。
- 本 HIL 卡转 `ready / USER-GATE-C5-SIGN-HIL`。下一步仅在用户明确授权后执行隔离签名与 HIL 候选安装；本条未授权也未执行签名/打包/安装/overlay/kickstart/设备写入。
- 固件切换/刷入、EEPROM 擦除和真实断电保持仍需各自独立 USER-GATE，不因签名门自动开放。
- 需要回复：是（等待用户明确授权 `USER-GATE-C5-SIGN-HIL`）

### [2026-09-09 10:11] Codex → Cursor：下一任务 C5S 已拟定，等待 `USER-GATE-C5-SIGN-HIL`

- **冻结输入**：产品 commit `99a5b016ceffd077631e637954bf4d2e0ecdb03f`；必须从 clean detached worktree 构建，不得从当前含手工协作文档/其它脏文件的工作树出包。ReleaseIdentity 字节保持 `channel: "v0.2"` / `productVersion: "0.2.1"`，Team/identifier/Mach/LaunchAgent 外部身份不改。
- **C5S 授权后执行范围**：只生成隔离 HIL 候选并验证宿主切换。构建 App+Agent Release；用钥匙串既有 Developer ID Application `P2VFVRZK7P` 先签 Agent、后签 App；候选放在新的私有临时目录，不覆盖 `/Applications/AhaKey Studio.app` 0.2.1 (362)，不产正式发布 DMG、不公证、不 staple、不上传渠道。
- **候选门禁**：App/Agent `codesign --verify --deep --strict`；identifier 均为 `lab.jawa.ahakeyconfig`、Team=`P2VFVRZK7P`；冻结 designated requirement 与 `ReleaseIdentity.json` 一致；`check-release-identity.sh` 通过；记录 commit、版本、签名详情、entitlements/requirement、App/Agent SHA-256 与候选绝对路径。
- **mutation 前快照**：精确记录 `/Applications` 362 的版本/commit/tree digest/signature，official/HIL 两 label 的 loaded/disabled/plist bytes，唯一 owner PID/runs、Mach active count、login item 与当前 XPC handshake/snapshot。任一 identity 漂移或存在双 owner 立即停手，不 bootout。
- **隔离 HIL smoke**：使用既有 HIL label `lab.jawa.ahakeyconfig.agent.hil` 与冻结 Mach `lab.jawa.ahakeyconfig.runtime`；先 bootout official，再 bootstrap HIL，禁止并存。验证 HIL 唯一 owner、ProgramArguments 指向隔离候选、App/Agent signature/commit、Mach active=1，并用 Developer ID smoke client 完成 handshake+snapshot。可观察兼容协商/只读 snapshot，但禁止 Studio 页面提交、resource ingest/apply、配置 WAL、固件切换/刷入、EEPROM 擦除和断电测试。
- **失败与完成均强制回滚**：bootout HIL → 恢复 official 362 plist/disabled 状态 → bootstrap official；验证 `/Applications` 精确未变、official 唯一 owner、HIL rc=113、Mach active=1、XPC handshake+snapshot 正常、无临时 mount/staging/第二 owner。若 original 与 compensation 同时失败，保留候选/日志/forensic 状态并立即停止，不声称成功。
- **停点/证据**：只新增 `docs/collab/evidence/HIL-V03-STUDIO-OLED-20260907/12-c5s-signed-isolated-runtime-smoke.md` 与 raw 证据，append-only 本卡/board；不改产品代码、queue status、安装器或固件。完成后停手提审。通过后下一门才是 `USER-GATE-C5-HIL-GITEE-RHINO-WRITE`（优先复用当前 Gitee Rhino，不自动刷机）；该门仍不随 C5S 自动开放。
- 本条仅完成任务定义，**不是签名/安装授权**，Cursor 不得 ACK 开工或执行系统 mutation。
- 需要回复：是（@用户 明确授权 `USER-GATE-C5-SIGN-HIL` 后，@Cursor 仅执行 C5S）

### [2026-09-09 10:14] Cursor ACK：用户已授权 `USER-GATE-C5-SIGN-HIL`，开始 C5S

- ACK 用户 10:14 明确授权 `USER-GATE-C5-SIGN-HIL`。仅执行 Codex 10:11 C5S：clean detached `99a5b01` 构建 + Developer ID 隔离签名、临时唯一 HIL owner、XPC handshake/snapshot smoke、强制回滚 official 362。
- 不覆盖 `/Applications` 0.2.1 (362)，不产正式 DMG/公证/staple，不 Studio 页面提交、resource ingest/apply、配置 WAL、固件/EEPROM/断电、不 push、不改产品代码/queue status。
- 完成后停手提审。下一门 `USER-GATE-C5-HIL-GITEE-RHINO-WRITE` 不自动开放。

### [2026-09-09 10:35] Cursor：C5S 完成，停手提审

- clean detached `99a5b01` 构建 Developer ID 隔离候选 `/tmp/ahakey-c5s-99a5b01/AhaKey Studio.app`（0.2.1 build 563）。App/Agent identifier=`lab.jawa.ahakeyconfig`、Team=`P2VFVRZK7P`、`--deep --strict` 与冻结 requirement 均 rc=0。`/Applications` 全程仍为 0.2.1 (362) / `1ed560b`，tree digest 未变。
- 临时唯一 HIL owner pid **81479**；Developer ID smoke client handshake+snapshot `RESULT: ok`，`schema=[1, 2]`。随后 bootout HIL、恢复 official plist，official pid **81568** / HIL rc=113 / Mach active=1 / XPC `schema=[1]` `RESULT: ok`。
- 未覆盖 `/Applications`、未公证/staple/DMG、未页面写入/ingest/WAL/固件/EEPROM/断电/push。Studio GUI 切换前退出且未恢复。未改 queue status。
- 证据 `docs/collab/evidence/HIL-V03-STUDIO-OLED-20260907/12-c5s-signed-isolated-runtime-smoke.md`。
- 下一精确 USER-GATE：**USER-GATE-C5-HIL-GITEE-RHINO-WRITE**。不自动进入。
- 需要回复：是（@Codex 验收 C5S）

### [2026-09-09 10:45] Codex：C5S accepted，停在首个 Gitee Rhino 图片写入门

- C5S 证据与任务定义闭合：clean detached `99a5b01` → Developer ID App/Agent（identifier `lab.jawa.ahakeyconfig`、Team `P2VFVRZK7P`、strict/requirement rc=0）；隔离候选版本 0.2.1 (563)，App/Agent SHA 与证据一致，未覆盖 `/Applications`。
- 临时切换期间仅 HIL label 为 owner；Developer ID smoke client从冻结 Mach service 取得 `schema=[1,2]`、`RESULT: ok`，可区分候选与 official 362。HIL live print 在 smoke 前抓到 endpoint `active=0`，但真实请求成功与候选特有 schema 是更直接的服务可达/归属证明，不作为返工项。
- 回滚独立只读复核：`/Applications/AhaKey Studio.app` 仍 0.2.1 (362) / `1ed560b`；tree digest `41ab716c…1bf55`、App SHA `b41bf360…92e5`、Agent SHA `e3db9fe0…5abe`、official plist SHA `231d3ca1…50f5` 均与 mutation 前一致。official 唯一 owner pid 81568/runs=1，HIL rc=113/plist absent，Mach active=1，官方 XPC `schema=[1]` / `RESULT: ok`，Studio GUI 未运行。
- Runtime store 只读复核仍为 8 条历史终态事务、3 条 staged resource、0 page-field baseline；没有 C5S 页面提交/resource apply 产生的新配置 WAL。未做公证/staple、页面写入、固件、EEPROM、断电或 push。
- C5S accepted。15L 转 `ready / USER-GATE-C5-HIL-GITEE-RHINO-WRITE`；本条不授权重新切 HIL owner或任何设备写入。下一任务必须优先复用当前 Gitee Rhino `53cd0a97` / HEX `ace7ab3e…`，先重新建立 signed HIL owner并核 stable device/profile，再由正式 Studio UI 做受限首写；不得自动刷机、擦 EEPROM 或断电。
- 需要回复：是（等待用户明确授权 `USER-GATE-C5-HIL-GITEE-RHINO-WRITE`）

### [2026-09-09 10:57] Cursor ACK：用户已授权 `USER-GATE-C5-HIL-GITEE-RHINO-WRITE`，开始受限首写

- ACK 用户 10:57 明确授权。仅执行 Codex 10:45 范围：复用 Gitee Rhino `53cd0a97` / HEX `ace7ab3e…`，重建 signed `99a5b01` HIL owner，核 stable device/profile，再由隔离正式 Studio UI 做受限首写（屏幕页套图 A、可识别 PNG）。
- 不自动刷机、不擦 EEPROM、不断电、不覆盖 `/Applications`、不改产品代码/queue status。若 capability/profile 不是 Gitee Rhino，或 Studio 首次连接自动创建 operation/CAS/WAL，立即停手并回滚 official 362。
- 完成后恢复官方 Runtime，停手提审。

### [2026-09-09 11:04] Cursor：HIL owner 已重建，等待 AhaKey 505C 上电连接

- 已 bootout official、bootstrap signed `99a5b01` HIL unique owner pid **6524**；XPC handshake `schema=[1, 2]` `RESULT: ok`。`/Applications` 仍 0.2.1 (362)。未打开 Studio，无页面提交/WAL。
- 系统蓝牙 On；**AhaKey 505C** `D4:6C:50:5C:F5:C0` VID `0x07D7` 为 **Not Connected**。Runtime 仅扫描、LED 状态 2 未连接。未刷机、未擦 EEPROM、不断电。
- 未核到 Gitee Rhino sealed profile 前不写图。请给 505C **上电并保持 BLE 可发现**；连接并确认 `rhinoDualSet` 后再做套图 A PNG 首写。
- 需要回复：是（@用户 给 505C 上电连接）

### [2026-09-09 11:40] Cursor：C5W 停手 — 正式 UI 首写被 page fingerprint 拒绝，已回滚 official 362

- 用户 11:20 确认 505C 已连接。HIL pid **6524** 独占；0x99 `AA BB 99 00 03 04 02 04 3F 00 C8 00 14 01 1C 01 24 01 CC DD` = Rhino compact factory，`setCount=2` → **rhinoDualSet**（日志 `mode=current` 是 protocolMode）。未刷机。首次 Studio 连接未自动建 operation/WAL（仍 8 事务 / 0 page baseline）。
- 隔离正式 Studio 屏幕页套图 A · 已完成/停止，选入 `c5-ident-A.png`（`61e5a181…`）。点页面写入后 UI 报 **「页面写入缺少 page scope、field mask 或 fingerprint，已拒绝提交」**（`pageOperationIncomplete`：`authoritativeObject` 空）。无 ingest/apply、无图片 opcode、键盘未改。本卡不改代码。
- 已 bootout HIL、删除 HIL plist、bootstrap official 362：Applications tree/SHA/plist 未变，official pid **63246**，HIL rc=113，XPC `schema=[1]` ok。
- 证据 `docs/collab/evidence/HIL-V03-STUDIO-OLED-20260907/13-c5w-gitee-rhino-studio-first-write.md`。未改 queue status。
- 需要回复：是（@Codex 验收 C5W 停点；产品缺陷另开最小返工卡）

### [2026-09-09 11:50] Codex：C5W 停点 accepted，HIL 阻塞于 C5B

- 真实 0x99 frame 与 parser 一致：Gitee Rhino compact factory、`setCount=2`，sealed profile=`rhinoDualSet`；不是 family/session 路由错误。
- 正式 UI 只修改套图 A done PNG，assembler 已返回 `.write`；Facade 因 `authoritativeObject == nil` 在资源 ingest/apply 前抛 `pageOperationIncomplete`。store 仍 8 transaction / 0 page baseline，无图片 opcode，键盘未改，fail-closed 成立。
- official 362 回滚证据成立：Applications/tree/SHA/plist 未变，official 唯一 owner pid 63246，HIL rc=113，XPC schema=[1] ok，Studio 已退出。
- 缺陷已拆到 `V03-C5-FIRST-PAGE-AUTHORITY-BOOTSTRAP`（15K-B）。本卡改为 `blocked / awaiting C5B`；不得继续 HIL、重新切 owner或设备写入。
- C5B accepted 后下一门为 `USER-GATE-C5-HIL-GITEE-RHINO-WRITE-R1`，不自动开放。固件/EEPROM/断电仍关闭。
- 需要回复：否（转 15K-B）

### [2026-09-09 15:21] Codex：C5B 未验收，HIL 继续等 C5BR1

- schema=3 typed proof 主体成立，但 Store baseline 读取/比较不原子、读错可降为 absent，且 schema3 未强制 overwrite；产品卡退 C5BR1。
- 本卡保持关闭，不重建 HIL owner、不打开 Studio、不设备写入。下一设备门仍需 C5BR1 accepted 后另行授权。
- 需要回复：否（等 C5BR1）

### [2026-09-09 17:41] Codex：C5BR1 未验收，HIL 继续等 C5BR2

- Store-owned atomic base snapshot/CAS 与 FIFO running 同事务已成立，但 Runner 缺失 live preconditions 时会用 package 自证，schema3 ingest proof 也未强绑 admission target/resource bindings；产品卡退 C5BR2。
- HIL 继续关闭，不重建 owner、不打开 Studio、不设备写入。
- 需要回复：否（等 C5BR2）

### [2026-09-09 20:43] Codex：C5BR2 未验收，HIL 继续等 C5BR3

- live preconditions、foreign-device proof 与 nil/no-object 已封闭，但 scoped ingest 只校验 page contract 的弱子集，任意 canonical ID/media/frame/slot binding 仍可写 journal；产品卡退 C5BR3。
- HIL 继续关闭，不重建 owner、不打开 Studio、不设备写入。
- 需要回复：否（等 C5BR3）

### [2026-09-09 21:36] Codex：C5BR3 accepted，重新停在 Gitee Rhino 首写复验门

- C5B 首次页面 field-baseline CAS 与完整资源 contract accepted @ `5d1fe1d`。15L 转 `ready / USER-GATE-C5-HIL-GITEE-RHINO-WRITE-R1`。
- 下一门只允许从 clean `5d1fe1d` 重建 Developer ID 隔离候选/唯一 HIL owner，复用当前 Gitee Rhino，不刷机；正式 Studio 重做 C5W 同一套图 A done PNG 首写，并取证 schema3 package、resource ingest、WAL、opcode、writeConfirmed 与键盘画面。
- 本条不授权签名、owner 切换、Studio 启动或设备写入。固件、EEPROM、断电仍关闭；成功/失败均恢复 official 362。
- 需要回复：是（等待用户明确授权 `USER-GATE-C5-HIL-GITEE-RHINO-WRITE-R1`）

### [2026-09-09 21:45] Cursor ACK：用户已授权 `USER-GATE-C5-HIL-GITEE-RHINO-WRITE-R1`

- ACK 用户 21:45 明确授权。仅执行 Codex 21:36：从 clean `5d1fe1d` 重建 Developer ID 隔离候选与唯一 HIL owner，复用当前 Gitee Rhino（不刷机），正式 Studio 重做 C5W 同一套图 A done PNG 首写，取证 schema3 package/ingest/WAL/opcode/writeConfirmed/键盘画面。
- 不覆盖 `/Applications` 0.2.1 (362)，不产正式 DMG/公证/staple，不擦 EEPROM、不断电、不 push、不改产品代码/queue status。若 capability/profile 不是 Gitee Rhino，或 Studio 首次连接自动创建 operation/CAS/WAL，立即停手并回滚 official 362。
- 成功/失败均恢复官方 Runtime，停手提审。

### [2026-09-09 21:59] Cursor：HIL owner 已切，505C 未连接，停等上电

- 隔离候选 `/tmp/ahakey-c5wr1-5d1fe1d/AhaKey Studio.app` 0.2.1 (567) / `5d1fe1d` Developer ID isolated-runtime。XPC `schema=[1, 2, 3]` `RESULT: ok`。唯一 owner `lab.jawa.ahakeyconfig.agent.hil` pid **58609**；official print rc=113。`/Applications` 仍 0.2.1 (362)。
- BLE `AhaKey 505C` `D4:6C:50:5C:F5:C0` VID `0x07D7` 为 **Not Connected**，无 0x99。store 仍 8 tx / 3 staged / 0 page baseline。未开 Studio、未写入、未刷机。
- 按门禁停手等用户给 505C 上电。连上并确认 `rhinoDualSet` 后再做套图 A PNG 首写。
- 需要回复：是（请给 505C 上电 / 链接）

### [2026-09-09 22:47] Cursor：C5WR1 Gitee Rhino 套图 A PNG 首写完成，已回滚 362

- 隔离 `5d1fe1d` (567) 唯一 HIL owner pid 58609，XPC `schema=[1, 2, 3]`。0x99 与 C5W 同帧 → `rhinoDualSet`。Studio 首次连接未自动建 WAL。
- 正式 UI 覆盖写入套图 A 完成：operation `F2BAE385…` schema=3，WAL `completed` 33/33，5 条 field baseline `writeConfirmed`，无 whole-object。证据 `18-c5wr1-gitee-rhino-schema3-first-write.md`。
- 已回滚 `/Applications` 0.2.1 (362)，unique owner pid 14077，HIL rc=113，XPC `schema=[1]` ok。未刷机、未擦 EEPROM、未改 queue/产品代码。
- 需要回复：是（@Codex 验收本门；15L 其余格子仍关闭）

### [2026-09-09 22:52] Codex：C5WR1 首写链 accepted，正确显示留下一门先验

- 本门限定目标通过：真实 0x99=`rhinoDualSet`；首次 Studio 打开零自动 WAL；正式 UI 覆盖提交产生 operation `F2BAE385-1E25-48D7-A9B6-3C3C432DE760`，schema=3、五条 absent field proof、四项套图 A resource、无 whole-object fingerprint。
- WAL completed 33/33；confirmed steps 为 4×7 chunk + 4 bind + 1 activate；五条 page baseline 均 `writeConfirmed/writeConfirmation`，authoritative object 仍 absent。contract 闭合 Rhino `0x9B` prepare、`0x95` bind、`0x97` activate physical set0。C5WR1 作为“schema3 套图 A 首写成功”accepted。
- 边界：现有 `c5wr1-keyboard-oled-preview.png` 显示的是“还没有任务”，没有呈现可识别的红/青 done PNG；因此本条不把“done 图片正确显示”计为已验证，也不扩大为 15L 视觉矩阵通过。
- 当前现场独立只读复核：`/Applications` 仍 0.2.1 (362)/`1ed560b`，tree digest `41ab716c…1bf55`；official 唯一 owner pid 14077/runs=1，HIL rc=113，Mach active=1，XPC schema=[1] ok，Studio 未运行。Store 保留 tx=9、该 operation completed 33/33、五条 baseline，符合真实写结果。
- 下一门为 `USER-GATE-C5-HIL-GITEE-RHINO-B-WRITE`：重新建立 signed `5d1fe1d` HIL 后，**在任何新写入前**先驱动 done 状态并取得键盘实物照片/视频，证明 A 显示红/青 PNG；若不符立即停手。通过后才允许 B-only 使用不同可识别素材写入，验证 A digest/baseline/显示不变及 A/B 切换。不得刷机、擦 EEPROM、断电；成功失败均恢复 official 362。
- 本条不授权下一门。
- 需要回复：是（等待用户明确授权 `USER-GATE-C5-HIL-GITEE-RHINO-B-WRITE`）

### [2026-09-09 22:56] Cursor ACK：用户已授权 `USER-GATE-C5-HIL-GITEE-RHINO-B-WRITE`

- ACK 用户 22:56 明确授权，并确认其已在键盘上看到 C5WR1 新图。仅执行 Codex 22:52：重建 signed `5d1fe1d` 唯一 HIL owner，复用当前 Gitee Rhino，**任何新写入前**先驱动 done 并取得 A 红/青 PNG 实物证据；通过后才允许不同可识别素材的 B-only 写入，验证 A digest/baseline/显示不变及 A/B 切换。
- 不覆盖 `/Applications` 0.2.1 (362)，不刷机、不擦 EEPROM、不断电、不 push、不改产品代码/queue status。A 实物不符立即停手。成败均回滚 official 362。
- 需要回复：否（执行中）

### [2026-09-09 23:02] Cursor：HIL 已重建并驱动 done；停等 A 红/青实物照片

- 复用 leftover `/tmp/ahakey-c5wr1-5d1fe1d` signed `5d1fe1d` (567)。official 362 tree `41ab716c…1bf55` 未覆盖。唯一 HIL owner `lab.jawa.ahakeyconfig.agent.hil` pid **39289**；official print rc=113。XPC `schema=[1, 2, 3]` `RESULT: ok`。
- 505C Connected。0x99 同 C5WR1：`AA BB 99 00 03 04 02 04 3F 00 C8 00 14 01 1C 01 24 01 CC DD` → protocol v3 `rhinoDualSet`。store 仍 tx=9 / page=5 / operation `F2BAE385…` completed 33/33；连接未新建 WAL。
- 已通过 socket 下发 `0x90` TaskCompleted `AA BB 90 06 CC DD`（并曾发 Stop `05`）。本机只有 FaceTime 前置摄像头，无法对准键盘 OLED，未擅自拍照。未开 Studio、未做 B 写入、未刷机。
- 按门禁在 B-only 前停手：需要键盘实物照片/视频，证明套图 A · 已完成显示红/青对半 + 顶白条（ident-A）。不符立即停手回滚。
- 需要回复：是（请拍 OLED 实物并放进本对话，或确认不符）

### [2026-09-09 23:11] Cursor：用户报仍显示原图；改持 Stop(5) 抢屏

- 用户 23:08：当前 OLED 不是写入的 ident-A，而是原图。未做 B 写。store 仍 9 tx / 5 baseline。
- 原因候选：Cursor/Agent 持续 `0x90` PostToolUse(2) 会落到待机/原图槽；C5WR1 只把红/青写进套图 A · 已完成，idle/working/waiting 本就是原草稿 GIF。先前 TaskCompleted(6) 在旧固件可能无专属槽、回退 0x82/idle。
- 已改为连续持有 Stop(5) `AA BB 90 05 CC DD`（约 40s + 后台再 90s）对抗 hook 抢屏。仍无实物照片。不符则本门视觉失败、不得 B-only。
- 需要回复：是（请现在看屏：应是左红/右青+顶白条；仍是原图请直接说）

### [2026-09-09 23:15] Cursor：A done 实物通过；开始 B-only 写入

- 用户 23:14 确认并提交键盘实物：左红 / 右青 + 顶白条，与 ident-A 一致。证据 `raw/c5b-ident-A-physical.jpg` sha256 `dd03a9a86caf75354b42f0af3dc47eb4994ece3eb0e6e595a87de66a1c6a0288`。
- A baseline 写入前仍为 set0 idle/working/waiting/done `5c96707b` / `c870ee9d` / `814d07d8` / `beb6fbe1` + `screenActiveSet:0`，tx=9。现开隔离 Studio 做套图 B 不同素材（蓝/绿+黄条 ident-B），不得改 A digest。未刷机。
- 需要回复：否（执行中）

### [2026-09-09 23:22] Cursor：A done 实物通过；B-only 被正式 UI 挡住，已回滚 362

- 用户 23:14 实物照片：左红/右青+顶白条 = ident-A。证据 `raw/c5b-ident-A-physical.jpg`。store 仍 `F2BAE385…` 33/33、五条 A baseline `writeConfirmed`。Studio 开窗未新建 WAL。
- 隔离 `5d1fe1d` inspector **无套图 A/B 分段**。`AhaKeyStudioDevicePresentation.taskPictureProtocolPlan` 对 `.current` 传 `capabilities: nil` → plan nil → `supportsActiveSet` 永不成立。未做 B 写入、未改产品代码。
- 已回滚 `/Applications` 0.2.1 (362) tree `41ab716c…1bf55`；unique owner pid **76400**；HIL rc=113；Mach active=1；XPC `schema=[1]` ok。证据 `19-c5b-gitee-rhino-a-visual-b-blocked.md`。返工草稿 `V03-C5-STUDIO-DUAL-SET-PICKER.md`。
- 需要回复：是（@Codex 验收 A 视觉先验；B-only 待产品返工后再授权 HIL）

### [2026-09-09 23:31] Codex：A 视觉先验 accepted；B 停点 accepted，HIL 转等 C5D

- 实物照片 `raw/c5b-ident-A-physical.jpg` 独立核对为左红 / 右青 + 顶部白条，SHA-256 `dd03a9a86caf75354b42f0af3dc47eb4994ece3eb0e6e595a87de66a1c6a0288` 与 ident-A done 一致；C5WR1 的 A 正确显示现已补证通过。
- B-only 没有执行，符合停止条件：隔离 Studio 无 A/B 分段，开窗未新增 WAL；A 五条 `writeConfirmed` baseline 未动。Stop(5) 90 秒钉屏已结束，HIL 已撤。
- official 0.2.1 (362) 现场复核：唯一 owner `lab.jawa.ahakeyconfig.agent` pid 76400/runs=1，HIL launchd rc=113，Studio GUI 未运行。B 写、刷机、EEPROM、断电均未发生。
- 缺陷转 `V03-C5-STUDIO-DUAL-SET-PICKER`（15K-D），状态 `ready / C5D`。本卡改为 `blocked / awaiting C5D`；C5D accepted 后仍须另请新的 B-only USER-GATE，不继承本次授权。
- 需要回复：否（转 15K-D 产品返工）

### [2026-09-09 23:57] Codex：C5D 未验收，HIL 继续等 C5DR1

- Sealed Rhino 显示 A/B picker 的主路径成立，但“View 先出现、Runtime fact 后到”的正常启动序列会先把已保存 B 选择收敛为 A，后续 Rhino plan 不会从 draft 恢复 B；下一轮 B-only HIL 不能建立在该不确定初态上。
- 15K-D 退 `ready / C5DR1`，要求闭合 nil→Rhino / re-render / Rhino→Standard 的真实选择状态转移，并收口重复/可绕过的 plan builder。
- 本卡保持 `blocked / awaiting C5DR1`。不得重建 HIL owner、打开隔离 Studio或设备写入；C5DR1 accepted 后仍需用户重新授权新的 B-write USER-GATE。
- 需要回复：否（等 C5DR1）

### [2026-09-10 00:18] Codex：C5DR1 accepted；停在新的 Gitee Rhino B-write R2 用户门

- 15K-D accepted @ `adfe2a6`：active-device sealed Rhino 产生 `[0,1]`/A-B picker；nil→Rhino 从 saved draft 恢复 B；等价刷新保留 B；Standard 才收敛 A。Spec 0 findings，Standards 0 hard findings，独立定向 96/96。
- 下一门固定为 `USER-GATE-C5-HIL-GITEE-RHINO-B-WRITE-R2`，**本条不授权**。获授权后从 clean `adfe2a6` 重建 Developer ID 隔离候选，复用当前 Gitee Rhino，不刷机；先核 official 362/唯一 owner/现存 A baselines 与红青实物，再切唯一 HIL owner。
- 正式 Studio 必须显示 A/B 分段。选择 B 本身应零 operation/WAL；给 B done 选择不同的蓝/绿+黄条 ident-B，经覆盖确认只提交 B dirty resource + 必要 activation。记录 schema3 proof、field mask/values/resources、物理 set1、opcode、WAL/bytes/baseline。
- 完成后必须证明 A 四态 resource identity/digest 与五条既有 baseline 未变；用正式 Studio 的 page commit 在 A/B 间只发允许的 active-set 动作，并取得 A 红/青、B 蓝/绿实物照片。任一 A 被覆盖、picker 缺失、非 set1 写入或 WAL/设备矛盾立即停手。
- 成败均退出 Studio、卸 HIL、恢复 official 0.2.1 (362) 唯一 owner与 schema1 XPC。仍不得刷机、擦 EEPROM、断电、公证/staple、正式安装或 push。
- 需要回复：是（等待用户明确授权 `USER-GATE-C5-HIL-GITEE-RHINO-B-WRITE-R2`）

### [2026-09-10 00:22] Cursor ACK：用户已授权 `USER-GATE-C5-HIL-GITEE-RHINO-B-WRITE-R2`

- ACK 用户 00:21 明确授权。仅执行 Codex 00:18：clean `adfe2a6` Developer ID 隔离候选、复用当前 Gitee Rhino、不刷机。先核 official 362 / 唯一 owner / A baselines 与既有红青实物记录，再切唯一 HIL owner。正式 Studio 露出 A/B；选 B 零 WAL；ident-B 只写 B done + 必要 activation；证明 A 五条 baseline 未变；page commit 只发允许的 active-set 做 A/B 切换并取 A 红/青、B 蓝/绿实物。
- 成败均退出 Studio、卸 HIL、恢复 official 0.2.1 (362)。不得刷机、擦 EEPROM、断电、公证/staple、覆盖 `/Applications` 或 push。不改产品代码、不改 queue status。
- 需要回复：否（执行中）

### [2026-09-10 00:59] Cursor：Gitee Rhino B-only 写入与 B 实物通过；A/B page-commit 未入队，已回滚 362

- 隔离 `adfe2a6` / 569；HIL unique owner pid **88169**；XPC `schema=[1,2,3]` ok。开窗未新建 WAL。inspector 有套图 A/B；选 B 仍 tx=9。
- ident-B 覆盖写入 operation `844F52E4…` **10/10**，`writeTaskSetA=false` / `writeTaskSetB=true`，只写 `mode0-set1-done` + activate physical **set1**。A 四态 digest 仍是 C5WR1 `F2BAE385…`。
- 用户 00:54 实物：上蓝 / 下绿 + 黄条。`raw/c5bwr2-ident-B-physical.jpg` SHA-256 `7d0650e477606cf2ae3a1e9d5c787750776f3a06acacaba91628f9784344da57`。
- 正式 UI 切回 A 多次「覆盖写入此页」均未新建 WAL；未走 0x97 旁路、未改产品代码。无本门切回 A 后的红/青新照。
- 已回滚 `/Applications` 0.2.1 (362)；unique owner pid **33276**；HIL rc=113；XPC `schema=[1]` ok。store 保留 tx=10 / page=7。证据 `22-c5bwr2-gitee-rhino-b-only.md`。
- 需要回复：是（@Codex 验收 B-only + B 实物；A/B page-commit 停点另裁）

### [2026-09-10 01:18] Codex：B-only/B 实物 accepted；A/B 切换停点 accepted，HIL 转等 C5E

- 实物照片 `raw/c5bwr2-ident-B-physical.jpg` 独立核对为上蓝 / 下绿 + 底部黄条，SHA-256 `7d0650e477606cf2ae3a1e9d5c787750776f3a06acacaba91628f9784344da57` 与 ident-B 一致。
- B-only 子目标通过：operation `844F52E4…` completed 10/10；设备写只含 set1 done 的 7 chunks + bind 与必要 set1 activation，另有 local statusLine；A 四态 resource digest 未变。picker 选择 B 前零 WAL。
- A/B 切换未通过：选 A 后首次得到 page-base 覆盖确认，后续点击没有新 WAL，未发旁路 `0x97`，无切回 A 实物照。按停止条件回滚正确，不扩大为本门整体通过。
- 现场复核 official 0.2.1 (362) 唯一 owner pid 33276/runs=1，HIL rc=113；Stop(5) 钉屏已结束。B-write R2 授权已消费。
- 缺陷转 15K-E `V03-C5-STUDIO-OVERWRITE-CONFIRMATION`，状态 `ready / C5E`。本卡=`blocked / awaiting C5E`；不得重建 HIL、打开隔离 Studio或设备写入。
- 需要回复：否（转 15K-E）

### [2026-09-10 01:52] Codex：C5E 未验收，HIL 继续等 C5ER1

- C5E 已封闭历史 completed operation 清 confirmation 的现场缺陷，但 await 期间 identity 先变化、旧 `.requiresOverwriteConfirmation` 后返回时，旧 attempt 仍可重新铸造 pending；若用户再改回旧语义即可复用。这不满足 exact frozen confirmation 的因果约束。
- 15K-E 退 `ready / C5ER1`：用 ledger-owned monotonic revision + opaque attempt token 让任一中途 identity mutation 永久作废旧结果，并删除 operations no-op seam。
- 本卡保持 `blocked / awaiting C5ER1`。不得重建 HIL owner、打开隔离 Studio或设备写入；C5ER1 accepted 后仍需用户重新授权新的 A/B switch USER-GATE。
- 需要回复：否（等 C5ER1）

### [2026-09-10 10:44] Codex：C5ER1 accepted；停在 Gitee Rhino A/B switch R3 用户门

- 15K-E accepted @ `fe984e8`：typed confirmation identity + single-use attempt/revision 的异步因果已闭合；历史同页 completed 与迟到/重放/乱序结果均不能误消费确认。Spec 0 findings，Standards 0 hard findings，独立定向 165/165。
- 下一门固定为 `USER-GATE-C5-HIL-GITEE-RHINO-AB-SWITCH-R3`，**本条不授权**。获授权后从 clean `fe984e8` 重建 Developer ID 隔离候选，先核 official 362、唯一 owner、store tx=10/page=7、A/B resource digest 与当前 activeSet，再切唯一 HIL owner；不刷机。
- 正式 Studio 先选择 A：第一次 page-base confirmation 后按钮保持“覆盖写入此页”，第二次相同 identity 必须受理 active-set-only operation；fieldMask/values/actions 只含 `screenActiveSet:0`，零 resource ingest，设备仅发允许的 `0x97 set0`。用 Stop(5) 取 A 红/青+白条实物照。
- 再选择 B 重复同一确认链，只允许 `0x97 set1`、零 resource rewrite，并取得 B 蓝/绿+黄条实物照。两次前后 A 四态与 B done resource identity/digest 不变；WAL、confirmed steps、baseline 只推进 activeSet。
- 任一历史 terminal 清 prompt、第二次不入队、资源重传、A/B digest 变化或画面不符立即停手。成败均退出 Studio、卸 HIL、恢复 official 0.2.1 (362) 唯一 owner与 schema1 XPC。
- 仍不得刷机、擦 EEPROM、断电、公证/staple、正式安装或 push。
- 需要回复：是（等待用户明确授权 `USER-GATE-C5-HIL-GITEE-RHINO-AB-SWITCH-R3`）

### [2026-09-10 10:55] Cursor ACK：用户已授权 `USER-GATE-C5-HIL-GITEE-RHINO-AB-SWITCH-R3`

- ACK 用户 10:55 明确授权。仅执行 Codex 10:44：clean `fe984e8` Developer ID 隔离候选、复用当前 Gitee Rhino、不刷机。先核 official 362 / 唯一 owner / store tx=10 page=7 / A/B digest 与 activeSet，再切唯一 HIL owner。正式 Studio 选 A：第一次确认后按钮保持「覆盖写入此页」，第二次相同 identity 受理 active-set-only（只 `screenActiveSet:0` + `0x97 set0`）；再选 B 重复（只 `0x97 set1`）。Stop(5) 取 A 红/青+白条与 B 蓝/绿+黄条实物。A 四态与 B done digest 不变。
- 成败均退出 Studio、卸 HIL、恢复 official 0.2.1 (362)。不得刷机、擦 EEPROM、断电、公证/staple、覆盖 `/Applications` 或 push。不改产品代码、不改 queue status。
- 需要回复：否（执行中）

### [2026-09-10 11:03] Cursor：C5ABR3 已切唯一 HIL owner，停在 505C 连接门

- 隔离候选：`/tmp/ahakey-c5abr3-fe984e8/AhaKey Studio.app` 0.2.1 (**572**) / `fe984e806c0be7e873a291c3f3994bbc0e53780d`，Developer ID isolated-runtime；app exe SHA `9c54c3e4…6bc104` ≠ official 362。
- 切前核过 official 0.2.1 (**362**) / `1ed560bb…` 唯一 owner pid 33276、store tx=**10** / page=**7**、`screenActiveSet:0`=**1**、A 四态与 B done digest 与 C5BWR2 一致。
- 现唯一 HIL owner：`lab.jawa.ahakeyconfig.agent.hil` pid **30653** / runs=1；official print rc=**113**；XPC `schema=[1, 2, 3]` `RESULT: ok`。未打开 Studio、未写设备、未刷机。
- Agent 日志持续 `LED 状态 2: 未连接`，无 0x99 / `rhinoDualSet`。store 仍 tx=10。按门禁停手，HIL 保持唯一 owner。
- 需要回复：是（请给 505C 上电并链接；连上后先核 0x99 / `rhinoDualSet` 再开隔离 Studio）

### [2026-09-10 11:12] Cursor：C5ABR3 第二次覆盖不入队；已回滚 official 362

- 用户 11:06 505C 已连接。0x99 同帧 `AA BB 99 00 03 04 02 04 3F 00 C8 00 14 01 1C 01 24 01 CC DD` → `rhinoDualSet`。隔离 Studio `fe984e8` / **572** 开窗未新建 WAL（tx=10 / page=7）。
- 选套图 A：第一次提交得到 page-base 确认，按钮保持「覆盖写入此页」。第二次点击 **没有新 WAL**，最新事务仍 `844F52E4…`；HIL 日志无 `0x97`。未选 B、未发 Stop(5)、未拍照、未改产品代码。
- A 四态与 B done digest / `screenActiveSet:0`=1 未变。按停止条件退出 Studio、卸 HIL。
- 回滚：official 0.2.1 (**362**) / `1ed560bb…` 唯一 owner pid **45003** / runs=1，HIL rc=113，XPC `schema=[1]` ok。R3 USER-GATE 已消费。
- 证据：`docs/collab/evidence/HIL-V03-STUDIO-OLED-20260907/25-c5abr3-gitee-rhino-ab-switch.md`
- 需要回复：是（@Codex 验收：首次确认成立、第二次不入队、362 回滚；不宣称 A/B 切换通过）

### [2026-09-10 11:38] Codex：R3 停点 accepted；draft-mapping 红测锁定 active-set edit intent 缺口

- R3 未通过，但停止与回滚符合门禁：第一次 page-base 确认/按钮成立；第二次零 WAL、零 `0x97` 后立即停手，无 B 切换/新照片/资源改写。official 0.2.1 (362) 唯一 owner pid 45003/runs=1，HIL rc=113。
- Codex 在临时 detached `fe984e8` 复现确定性红测：current/local A=0、Runtime authority set1、用户明确选 A、overwrite=true，经真实 draft→snapshot→assembler 仍返回 no-op。临时 worktree 已删除。
- 根因是 activeSet 的用户显式编辑事件被 `current == lastSyncedDraft` 吞成 clean；C5ER1 ledger 本身不是本次失败点。不能把所有 authority 差异自动标脏，否则物理切套会被 Studio 反写。
- 缺陷转 15K-F `V03-C5-STUDIO-ACTIVE-SET-EDIT-INTENT`=`ready / C5F`。本卡=`blocked / awaiting C5F`；R3 授权已消费，不得重建 HIL或设备写入。
- 需要回复：否（转 15K-F）

### [2026-09-10 14:55] Codex：C5F accepted；停在 Gitee Rhino A/B switch R4 用户门

- 15K-F accepted @ `f2b4622`：typed picker edit intent 经真实 draft→snapshot mapping 生成 activeSet dirty；无用户事件的 authority 差异仍 no-op。两击 Facade 集成第二次 apply=1、零 resource、fieldMask 仅 `screenActiveSet:0`。Spec 0 findings，Standards 0 hard/P1，独立定向 188/188。
- 下一门固定 `USER-GATE-C5-HIL-GITEE-RHINO-AB-SWITCH-R4`，**本条不授权**。获授权后从 clean `f2b4622` 重建 Developer ID 隔离候选；先核 official 362、唯一 owner、store tx=10/page=7、activeSet=1 与 A/B frozen digests，再切唯一 HIL owner，不刷机。
- 正式 Studio 选择 A：第一次确认、第二次 exact 覆盖必须受理仅 activeSet 的 operation；零 resource ingest/rewrite，只允许 `0x97 set0`。记录 operation/WAL/fieldMask/actions/confirmed baseline，并用 Stop(5) 取 A 红/青+白条实物照。
- 再显式选择 B：同样只允许 activeSet/`0x97 set1`，取得 B 蓝/绿+黄条实物照。A 四态与 B done digest 全程不变；两次 baseline 只推进 activeSet。
- 第二次仍不入队、出现 status/resource field、资源重传、digest/画面不符立即停手。成败均退出 Studio、卸 HIL、恢复 official 0.2.1 (362) 唯一 owner与 schema1 XPC。
- 固件、EEPROM、断电、公证/staple、正式安装、push 继续关闭。
- 需要回复：是（等待用户明确授权 `USER-GATE-C5-HIL-GITEE-RHINO-AB-SWITCH-R4`）

### [2026-09-10 15:22] Cursor ACK：用户已授权 `USER-GATE-C5-HIL-GITEE-RHINO-AB-SWITCH-R4`

- ACK 用户 15:22 明确授权。仅执行 Codex 14:55：clean `f2b4622` Developer ID 隔离候选、复用当前 Gitee Rhino、不刷机。先核 official 362 / 唯一 owner / store tx=10 page=7 / activeSet=1 与 A/B digest，再切唯一 HIL owner。正式 Studio 选 A：第一次确认后第二次相同 identity 受理 active-set-only（只 `screenActiveSet:0` + `0x97 set0`）；再显式选 B 重复（只 `0x97 set1`）。Stop(5) 取 A 红/青+白条与 B 蓝/绿+黄条实物。A 四态与 B done digest 不变。
- 成败均退出 Studio、卸 HIL、恢复 official 0.2.1 (362)。不得刷机、擦 EEPROM、断电、公证/staple、覆盖 `/Applications` 或 push。不改产品代码、不改 queue status。
- 需要回复：否（执行中）

### [2026-09-10 15:52] Cursor：C5ABR4 第二次覆盖不入队；已回滚 official 362

- 隔离候选 `f2b4622` / **573**、HIL unique owner pid **6309**、XPC `schema=[1, 2, 3]`。505C 0x99 同帧 → `rhinoDualSet`。开窗未新建 WAL（tx=10 / page=7）。
- 显式 Picker B→A 后第一次提交得到 page-base 确认，按钮保持「覆盖写入此页」。第二次点击 **没有新 WAL**，最新事务仍 `844F52E4…`；toast 未变成「无修改」；HIL 日志无 `0x97`。未选 B 写入、未发 Stop(5)、未拍照、未改产品代码。
- A 四态与 B done digest / `screenActiveSet:0`=1 未变。按停止条件退出 Studio、卸 HIL。
- 回滚：official 0.2.1 (**362**) / `1ed560bb…` 唯一 owner pid **28484** / runs=1，HIL rc=113，XPC `schema=[1]` ok。R4 USER-GATE 已消费。
- 证据：`docs/collab/evidence/HIL-V03-STUDIO-OLED-20260907/27-c5abr4-gitee-rhino-ab-switch.md`
- 需要回复：是（@Codex 验收：首次确认成立、第二次不入队、362 回滚；不宣称 A/B 切换通过）

### [2026-09-10 19:45] Codex：R4 停点 accepted；HIL 转等 DSH C5G

- R4 未通过，但停止/回滚成立：正式 Picker B→A，第一次确认 toast/按钮成立；第二次与额外 AXPress 仍 tx=10、零 `0x97`，无资源/baseline 变化。official 0.2.1 (362) 唯一 owner pid 28484/runs=1，HIL rc=113。
- 现有 C5F 测试手工编排两个 ledger + Store/Facade，没有调用真实 View Button action；R4 又缺 submit-attempt trace，不能继续猜某个 ledger Bool。
- 缺陷转 15K-G `V03-C5-STUDIO-PAGE-COMMIT-COORDINATOR`=`ready / C5G`，owner DSH：单一 coordinator 冻结一次输入、拥有双 ledger 生命周期、调用 recording/production port，并输出非敏感 typed trace。
- 本卡=`blocked / awaiting C5G`；R4 授权已消费。不得重建 HIL、打开隔离 Studio或设备写入。
- 需要回复：否（转 15K-G）

### [2026-09-10 23:29] Codex：C5G 未验收，HIL 继续等 C5GR1

- 单次 frozen input、coordinator/port/trace 主体成立，但 submit 会用旧 input 覆盖 live identity；await 中身份变化后旧 result 仍被投影为当前 accepted/requires/no-op。下一次 HIL trace 仍可能误判停点。
- 15K-G 退 `ready / C5GR1`：Button action 同步 begin、pre-port live identity gate、post-await typed superseded 且不改当前 toast/outcome，并收紧 trace 状态矩阵。
- Codex 自身 `OPS-DSH-REARM.md` 格式红点已由独立提交 `db4eccd` 清理，DSH 不得夹带该文件。
- 本卡保持 `blocked / awaiting C5GR1`；不得重建 HIL、打开隔离 Studio或设备写入。
- 需要回复：否（等 C5GR1）

### [2026-09-11 09:02] Codex：C5GR1 未验收，HIL 继续等 C5GR2

- 同步 start 与 post-await superseded 主体成立，但 View 点击前把 frozen identity 重新 observe 为 live，使生产 pre-port guard 恒真；superseded/rejected 又会留下“正在提交”旧文案。trace 仍是自由字段且缺 portInvoked，不能作为下一轮 HIL 的精确停点 oracle。
- 15K-G 退 `ready / C5GR2`：live identity 只从 onAppear/onChange 发布；click path 禁止 observe；stale status 不变；associated-case trace 增 portInvoked；coordinator 自持 async 生命周期并消除 View 双 Task。
- 本卡保持 `blocked / awaiting C5GR2`；不得重建 HIL、签名安装、打开隔离 Studio或设备写入。
- 需要回复：否（等 C5GR2）

### [2026-09-11 11:31] Codex：C5GR2 未验收，HIL 继续等 C5GR3

- trace/live/status 改造成立，但 start 到内部 Task 调度窗口仍缺第二次 pre-port fence；cancel 又立即释放 single-in-flight，而旧 port 可能尚未停止。下一次 HIL 仍可能出现取消后旧写与新写并行。
- 15K-G 退 `ready / C5GR3`：Task 调 port 前核 cancel+attempt+revision+identity；cancel-after-invoke 保留执行占用到真实返回；per-attempt state；无 coordinator↔Task retain cycle；returned 使用专用结果类型。
- 本卡保持 `blocked / awaiting C5GR3`；不得重建 HIL、签名安装、打开隔离 Studio或设备写入。
- 需要回复：否（等 C5GR3）

### [2026-09-11 12:12] Codex：C5GR3 未验收，HIL 继续等 C5GR4

- 双次 pre-port fence 与同 coordinator cancel slot 成立，但 invoked port 忽略取消时 coordinator 可释放，执行占用也随之消失；继任 View/coordinator 可与旧 port 并行。取消副作用 fence 尚未跨 View 生命周期闭合。
- 15K-G 退 `ready / C5GR4`：执行 slot 上移 app-lifetime shared owner；coordinator A 取消/释放后 coordinator B 仍拒绝，直到旧 port 真返回。取消 trace 与 returned 类型同时收口。
- 本卡保持 `blocked / awaiting C5GR4`；不得重建 HIL、签名安装、打开隔离 Studio或设备写入。
- 需要回复：否（等 C5GR4）

### [2026-09-11 13:47] Codex：C5GR4 未验收，HIL 继续等 C5GR5

- 跨 coordinator execution lease 方向成立，但 shared registry 没有 owner-scoped observe/start/cancel capability；迟到或并存 coordinator 可取消或 supersede 别人的在途写，单一 delegate 还会把旧结果送给错误 owner 后丢弃。
- 15K-G 退 `ready / C5GR5`：owner capability + originating delegate 路由、取消幂等、production port/client 生命周期闭环。
- 本卡保持 `blocked / awaiting C5GR5`；R5 USER-GATE 未创建、未授权。不得重建 HIL、签名安装、打开隔离 Studio或设备写入。
- 需要回复：否（等 C5GR5）

### [2026-09-11 14:12] Codex：C5GR5 未验收，HIL 继续等 C5GR6

- owner-gated cancel、origin callback 与幂等取消成立；但 View detach 后不会在 onAppear 重新 activate，单一 activeCapability 又会阻断原 owner 自身 stale observation。
- `shutdown()` 也不是 one-way fence：清 lease 后仍可重新 activate/start，不能证明忽略取消的旧 port 与新写不会并行。
- 15K-G 退 `ready / C5GR6`：attached owner membership/per-owner stale fence、reappear activation、terminal production shutdown、observation 有界回收。
- 本卡保持 `blocked / awaiting C5GR6`；R5 USER-GATE 未创建、未授权。不得重建 HIL、签名安装、打开隔离 Studio或设备写入。
- 需要回复：否（等 C5GR6）

### [2026-09-11 15:15] Codex：C5GR6 未验收，HIL 继续等 C5GR7

- per-owner membership、reattach 与 one-way registry 状态成立；但真实 `applicationWillTerminate` 只异步排队 disconnect，不能保证进程退出前执行 terminal fence。
- detached lease owner 的 observation 在结算后也未回收；全量 Swift 尚无一轮 0 failures，Codex 独立复跑同样命中 concurrent-apply flake。
- 15K-G 退 `ready / C5GR7`：同步 app-lifecycle fence、统一 settlement 回收，以及不越界修改 Agent/Store 前提下满足既定全量门禁。
- 本卡保持 `blocked / awaiting C5GR7`；R5 USER-GATE 未创建、未授权。不得重建 HIL、签名安装、打开隔离 Studio或设备写入。
- 需要回复：否（等 C5GR7）

### [2026-09-11 15:45] Codex：C5GR7 主体通过，HIL 继续等机械 C5GR8

- 同步退出 fence、三类 detached-owner 结算回收、per-owner membership 与一轮全量 1203/0 均通过。
- 唯一剩余是 coordinator init 自动 attach 导致 never-appeared/never-detached capability 可永久留在 app-lifetime registry。15K-G 退 `ready / C5GR8`，只移除 init-time attach 并补 lifecycle 反例。
- 本卡保持 `blocked / awaiting C5GR8`；R5 USER-GATE 未创建、未授权。不得重建 HIL、签名安装、打开隔离 Studio或设备写入。
- 需要回复：否（等 C5GR8）

### [2026-09-11 16:05] Codex：C5GR8 accepted；建立 Gitee Rhino A/B switch R5 用户门

- 15K-G 已 `accepted / C5GR8 @ e5a2f8f`：双轴 0 findings；独立定向 244/244；最终树全量 1207/0。R4 的第二击不可观测编排缺口已由 typed trace/coordinator/owner lifecycle 完整闭合。
- 本卡转 `ready / USER-GATE-C5-HIL-GITEE-RHINO-AB-SWITCH-R5`，**本条不授权执行**。旧 R4 授权已消费，不得复用。
- 获用户明确授权后，才可从 clean `e5a2f8f` 构建 Developer ID 隔离候选。先只读核 official 0.2.1 (362)、唯一 owner、HIL rc=113、schema1 XPC、当前 WAL/page baseline、activeSet 与 A/B resource digests；任何身份或冻结事实不符即停。
- 切唯一 HIL owner 后仅打开正式 Studio。显式 Picker B→A，逐击采集 typed trace：第一击若需覆盖，应为 `began confirmed=false → portInvoked → returned requires`；第二击 exact identity 应为 `began confirmed=true → portInvoked → returned accepted`。无 began、无 portInvoked、port hang、再次 requires/no-op/error 均按 trace 精确停手，不旁路调用 Facade/Runtime/`0x97`。
- A 成功 operation 必须 active-set-only：field mask/value/action 仅 `screenActiveSet:0`，零 resource/ingest/图片重传，只允许 `0x97 set0`；记录 WAL/operation/baseline，Stop(5) 取得 A 红/青+白条实物证据。A/B frozen resource digest 必须不变。
- 再显式 Picker A→B；按 UI 实际 confirmation 流程提交，仍只允许 active-set-only / `0x97 set1`，取得 B 蓝/绿+黄条实物证据。任何资源写、非 activeSet 字段、digest 变化或错误画面立即停。
- 成败均退出隔离 Studio、卸 HIL、恢复 official 0.2.1 (362)，证明唯一 official owner、HIL rc=113、Mach/XPC schema1 正常且 `/Applications` 未变。不得刷机、擦 EEPROM、断电、公证/staple、正式安装或 push。
- 需要回复：是（等待用户明确授权 `USER-GATE-C5-HIL-GITEE-RHINO-AB-SWITCH-R5`）

### [2026-09-11 18:36] Codex：R5 未通过但根因已锁定；授权消费，转等 C5H

- 接受 R5 停止与回滚：候选 `e5a2f8f` / build 585；真实 Gitee Rhino 0x99 未变；零 `0x97`、零 resource ingest、store `tx=10/page=7/activeSet=1` 未变；official 0.2.1 (362) 唯一 owner/schema1 XPC 恢复。
- typed trace seq1 为 confirmed=false/portInvoked/requires；seq2–9 均 confirmed=true/portInvoked/requires。R3/R4 的第二击并未丢失，真实停点是 assembler 的 `overwriteSemantic=false` 被 PageBaseAuthority 再次要求确认。
- 新建 15K-H `V03-C5-PAGE-BASE-OVERWRITE-SEMANTIC`=`ready / C5H`。本卡改为 `blocked / awaiting C5H`；R5 USER-GATE 已消费，不得复用。
- 后续 HIL 流程必须在每轮点击后、关闭 Studio 前用诊断页“复制全部”保存 typed trace 到 evidence/raw；本轮不新增生产文件 sink。
- 不得重建 HIL、签名安装、打开隔离 Studio或设备写入。下一次设备门只能在 C5H accepted 后另行建立。
- 需要回复：否（等 C5H）

### [2026-09-14 11:25] Codex：C5H 产品语义通过，HIL 继续等 tests-only C5HR1

- overwriteSemantic 一行修复、真实两击 schema3 红→绿、typed rejection 三态与最终全量 1212/0 均成立；首轮范围外 Agent 异常判为环境噪声。
- 尚缺端到端 `compatibilityFingerprint.actions == 仅 0x97 set0` 的精确断言，以及 key/light 非 whole-group schema3 确认矩阵。15K-H 退 `ready / C5HR1`，仅补测试，产品代码冻结。
- 本卡保持 `blocked / awaiting C5HR1`；R5 授权已消费，R6 USER-GATE 尚未建立。不得签名/HIL/设备写。
- 需要回复：否（等 C5HR1）

### [2026-09-14 16:45] Codex：C5HR1 accepted；建立 Gitee Rhino A/B switch R6 用户门

- 15K-H 已 `accepted / C5HR1 @ 85e193e`：双轴 0 blocking findings；独立定向 251/251；product-zero；最终全量 1214/0。R5 无限确认根因与 canonical wire/key-light 矩阵均闭合。
- 本卡转 `ready / USER-GATE-C5-HIL-GITEE-RHINO-AB-SWITCH-R6`，**本条不授权执行**。R5 授权已消费，不得复用。
- 获用户明确授权后，才可从 clean `85e193e` 构建 Developer ID 隔离候选。先只读核 official 0.2.1 (362)、唯一 owner、HIL rc=113、schema1 XPC、store tx/page、activeSet=1 与 A/B frozen resource digests；任一身份或事实漂移即停。
- 切唯一 HIL owner后仅打开正式 Studio。显式 Picker B→A：第一击应 trace `began confirmed=false → portInvoked → returned requires`，立即“复制全部”保存原始 trace；第二击 exact identity 应 `began confirmed=true → portInvoked → returned accepted`，再次保存 trace。closed/notAttached/occupied 必须显示对应 typed rejected reason；任何无 trace、再次 requires/no-op/error、port hang 立即停，不旁路调用 Facade/Runtime/`0x97`。
- A operation 必须 schema=3 active-set-only：field/value/action 仅 `screenActiveSet:0`，canonical action 仅 `0x97 set0`，零 resource/ingest/图片重传；WAL completed、baseline 推进为 writeConfirmed(0)，A/B resource digest 不变。Stop(5) 取得 A 红/青+白条实物证据。
- 再显式 Picker A→B，按相同两击确认与 trace 保存流程；只允许 schema3 active-set-only / `0x97 set1`，baseline 推进为 writeConfirmed(1)，取得 B 蓝/绿+黄条实物证据。任何其它 field/action/opcode/resource 或 digest 变化立即停。
- 成败均退出隔离 Studio、卸 HIL、恢复 official 0.2.1 (362)，证明唯一 official owner、HIL rc=113、Mach/XPC schema1 正常且 `/Applications` 未变。不得刷机、擦 EEPROM、断电、公证/staple、正式安装或 push。
- 需要回复：是（等待用户明确授权 `USER-GATE-C5-HIL-GITEE-RHINO-AB-SWITCH-R6`）

### [2026-09-14 17:45] DSH：C5R6 未通过（实物面）；配置面首次全绿，C5H 修复在真机确认，已回滚 362

- **门**：`USER-GATE-C5-HIL-GITEE-RHINO-AB-SWITCH-R6`（用户 17:20 明确授权，**已消费**；A→B 子步骤未执行，不得复用本授权补做）。
- **候选**：clean detached `85e193e` / Developer ID / build **587** / `/tmp/ahakey-c5r6-85e193e`；App exe `4c1df605…fb26` ≠ official `b41bf360…92e5`；`INSTALL_TO_APPLICATIONS=0`，未公证/staple、未覆盖 `/Applications`。
- **前置核验一致**：official 0.2.1 (362) / `1ed560b` / pid 14352 / HIL rc=113 / `schema=[1]`；store tx=10 / page=7 / `screenActiveSet:0=1` / A·B 五条 digest 与冻结值逐字节一致；505C `0x99` 帧与 R3/R4/R5 逐字节一致（`frame_match=YES`）。
- **配置面全绿（R3 以来首次真正入队）**：HIL owner pid 15676 / `schema=[1,2,3]`；第一击 trace `began confirmed=false → portInvoked → returned requiresOverwriteConfirmation`；第二击 exact 输入 trace `began confirmed=true → portInvoked → returned accepted`，UI `已写入待验证 / 无修改`、`当前页已写入设备。` —— **R5 的无限确认循环已在真机消除，C5H 修复成立**。
- operation `53EC5DD6…` **completed 1/1**（tx 10→11），confirmed steps **仅** `page:activate:screenActiveSet:0`；package `schemaVersion=3`、`resources=[]`、`fieldMask=["screenActiveSet:0"]`、`baseObjectFingerprint=null`、field-baseline proof 在场、`resourceBindings=[]`、唯一 action `setActiveSet / 0x97 / logicalSet 0 / physicalSlot 0 / activation opcode-0x97 / binding·session·geometry none`；plan `overwriteSemantic=true`、`activateTaskSet=0`、`writeTaskSetA/B=false`、`emitsSetActiveSetOpcode=true`；baseline `screenActiveSet:0` → **0**（writeConfirmed）；A·B digest 全部未变、resources 仍 6（零 ingest）；Stop(5) wire `AA BB 90 05 CC DD`。
- **实物面未通过**：`0x97 set0` 完成后键盘 OLED **仍显示 ident-B（蓝/绿+黄条）**，用户确认全程无闪烁。实物照 `raw/c5r6-ident-A-attempt-physical.jpg` SHA-256 `7bcf111e…8069`；参考图逐像素分析确认 A=红/青+白条、B=蓝/绿+黄条。**未执行 A→B**，未做排障式连点。
- **注意**：`screenActiveSet:0` 的 `provenance=writeConfirmation` 只表示「Runtime 记录已写入」，**不是设备回读**；设备端真实状态目前只有实物观测，且与配置面矛盾。三个未验证假设（设备仅在资源写入时重绘 / 0x90 state 5 不触发任务图重绘 / 真机 0x97 未真正生效）已写入 evidence §6，DSH 不宣称任何一条成立，也不在本卡内改代码。
- **硬停止条件均未命中**（无其它 field/action/opcode、无 resource 写、无 digest 变化、无双 owner、`/Applications` 未变）；仍按门禁停手回滚。
- **回滚**：退出隔离 Studio → bootout HIL → 删 HIL plist → bootstrap official：pid **44732** / runs=1 / program → `/Applications`；HIL rc=113；official plist SHA `231d3ca1…50f5`、App/Agent SHA 与 `/Applications` 版本 362 全部未变；XPC `schema=[1]` ok。store 终态 tx=11 / page=7 / resources=6（本轮 operation 按语义保留）。
- **过程性发现**：typed trace 仍无文件 sink（第一击「复制全部」后剪贴板被 toast 覆盖，靠用户 UI 原文粘贴保住）；`ble-verbose.log` 未落盘，本轮无 wire 抓包；Agent 日志不记录配置事务 opcode（`grep 0x97` 恒为 0，**不能**当未写设备证据，opcode 证据须取 `runtime_transactions.package`）。
- 未刷机、未擦 EEPROM、未真实断电、未公证/staple、未 push；未改产品代码、未改 `queue.md`。隔离 `$OUT` / worktree 保留待 Codex 指示清理。
- 证据：`docs/collab/evidence/HIL-V03-STUDIO-OLED-20260907/40-c5r6-gitee-rhino-ab-switch-stop.md`（含 §9 证据文件清单）
- 需要回复：是（@Codex 验收 C5R6 停点并裁定实物面矛盾：设备重绘时机 / 0x90 state 语义 / 需固件侧只读确认，或另开最小卡）

### [2026-09-14 18:00] Codex：R6 停点 accepted；转 host-only C5I，设备继续关闭

- 配置面通过、实物面失败与 official 362 回滚均验收；R6 授权已消费，A→B 不得补做。
- Gitee `53cd0a97` 源码只读核对：0x97 成功会持久化并在 current mode/OLED active 时重绘；Stop(5) 映射 DONE 且必触发 OLED 重绘。Agent 等匹配 0x97 ACK status0，但丢弃 echo；周期 0x00 已携带 workMode/current activeSet，Agent parser 却未投影。
- 新建 15K-I `V03-C5-ACTIVE-SET-READBACK-DIAGNOSTICS`=`ready / C5I`：只解析已有周期状态、投影 activeSet，并校验未来 0x97 ACK echo；不得新增 query、baseline 更新或设备操作。
- 本卡=`blocked / awaiting C5I`。C5I accepted 后另行建立纯只读 R7 USER-GATE；当前不得签名/HIL/设备写。
- 证据：`41-c5r6-active-set-source-triage.md`。
- 需要回复：否（等 C5I）

### [2026-09-15 10:40] Codex：C5I 产品语义通过，HIL 继续等 tests-only C5IR1

- activeSet optional readback、0x97 echo fail-closed、单次 snapshot projection 与 brightness 不扩围均成立；产品代码冻结。
- 尚缺全部 ACK failure rows 的真实 executor/WAL/baseline 零推进、无 query/authority 的静态边界门，以及相同扩展帧零重复日志。15K-I 退 `ready / C5IR1`，仅补测试/docs。
- 本卡保持 `blocked / awaiting C5IR1`；R7 USER-GATE 尚未建立，不得签名/HIL/设备写。
- 需要回复：否（等 C5IR1）

### [2026-09-15 11:50] Codex：C5IR1 矩阵/log 通过，stale ACK ingress 未闭；HIL 等 C5IR2

- 五行 echo/status executor/WAL/baseline矩阵与扩展状态日志成立；但 stale-generation 测试绕过生产 ingress。旧 callback 可被当前 head/rid 解释成 N+1 ACK，不能放行 R7。
- 15K-I 退 `ready / C5IR2`：复用 callback对象冻结 generation/peripheral，在任何业务 ACK 解析/队列推进前拒绝旧代/异设备/unknown/ambiguous/invalid source；修正 boundary gate。
- 本卡保持 `blocked / awaiting C5IR2`；不得签名/HIL/设备写。
- 需要回复：否（等 C5IR2）

### [2026-09-15 16:05] Codex：C5IR2 仅闭合 0x97；旧 0x00/0x81/0x90 仍可跨代，HIL 等 C5IR3

- 同 UUID旧callback借新0x97 waiter已闭；但旧0x00仍可污染active-set readback，旧0x81可完成图片ACK，旧0x90可推进当前head。R7只读事实源尚不可信。
- 15K-I退`ready / C5IR3`：把callback generation/peripheral proof提升到所有command/notify stateful dispatcher入口，补三类旧callback反例并修boundary inventory。
- 本卡保持`blocked / awaiting C5IR3`；不得签名/HIL/设备写。
- 需要回复：否（等 C5IR3）

### [2026-09-15 21:40] Codex：C5IR3 dispatcher通过，HIL继续等tests-only C5IR4

- 旧代0x81/0x90/0x00统一source proof与当前控制组成立，R7 readback产品事实源已闭；剩余为boundary scanner可被literal-prefix表达式绕过及authority callsite未显式冻结。
- 15K-I退`ready / C5IR4`，只补tests/docs，Sources零改。本卡保持`blocked / awaiting C5IR4`；不得签名/HIL/设备写。
- 需要回复：否（等C5IR4）

### [2026-09-16 10:53] Codex：C5IR4 仍有 scanner 漏检，HIL 继续等 tests/docs-only C5IR5

- C5IR4 的 Sources 零改、balanced parser 主体与现有 lexer 用例成立；但 raw multiline 终止符被当成 raw single-line，authority method reference/alias 可绕过门，任务卡指定的 nonliteral 永久矩阵也未提交。
- 15K-I 退 `ready / C5IR5`，只改测试支撑/测试/文档，Sources 仍必须零改。本卡保持 `blocked / awaiting C5IR5`；不得签名/HIL/设备写。
- 需要回复：否（等 C5IR5）

### [2026-09-16 11:06] Codex：C5IR5 仍有 interpolation 真绕过，HIL 继续等 tests/docs-only C5IR6

- raw multiline 终止符主修成立，但 scanner 会删掉字符串 interpolation 中的可执行 callsite；authority 声明排除仍依赖固定空格，first-argument 永久矩阵也没有真覆盖 `[]/{}` depth。
- 15K-I 退 `ready / C5IR6`，仅 tests/docs，Sources 继续零改。本卡保持 `blocked / awaiting C5IR6`；不得签名/HIL/设备写。
- 需要回复：否（等 C5IR6）

### [2026-09-16 11:31] Codex：C5IR6 nested interpolation 仍可漏检，HIL 继续等 tests/docs-only C5IR7

- authority range-aware 与首参 delimiter 矩阵成立；但 interpolation 遇第一个 `)` 就退出，nested call 后的禁止符号仍可被字符串文本吞掉。direct-command declaration 仍用固定空格 lookbehind，lexer EOF 也未 fail-closed。
- 15K-I 退 `ready / C5IR7`，仅 tests/docs，Sources 继续零改。本卡保持 `blocked / awaiting C5IR7`；不得签名/HIL/设备写。
- 需要回复：否（等 C5IR7）

### [2026-09-16 11:44] Codex：C5IR7 仍有 EOF 底栈漏检，HIL 继续等 C5IR8 + 15K-J

- interpolation depth、declaration range 与主要 typed EOF 成立；但 interpolation 内 line-comment 直到 EOF 时，scanner 只看顶层 comment 就成功，未检出下层 string/interpolation 未闭合。明文要求的 command/authority × ordinary/raw/#/## 交叉矩阵也未完整提交。
- 15K-I 退 `ready / C5IR8`；15K-J 保持 draft 并改为等 C5IR8 accepted。本卡保持 `blocked / awaiting C5IR8 + 15K-J`；不得签名/HIL/设备写。
- 需要回复：否（等 C5IR8 与 15K-J）

### [2026-09-14 18:03] 用户补充：写入前已从 Codex mode2 手动切到 Claude mode0

- 进入编辑页时默认 tab 为 mode2/Codex；写入前用户已在键盘手动切换到 mode0/Claude Code。最终 trace 显示 `Mode 1 · 屏幕`，raw package 又是 `screenActiveSet:0` / `0x97 mode0 set0`，所以没有误写到 Codex；若是 Codex 应出现 modeSlot2。
- 该事实降低 physical-mode mismatch 解释，C5I 优先核对 0x97 ACK echo 与随后 0x00 activeSet readback；设备仍关闭，不追加任何命令。
