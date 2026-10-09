# 旧版 mac 客户端适配新固件的前置依赖与对接说明

> 2026-10-09 交接注：这是本轮讨论材料。已确认决策和未决事项以 [跨设备交接](../handoff/CONNECT_AND_TALK_HANDOFF.md) 为准。初始计划/WBS 只覆盖 WS1/WS2 阶段，最终用户版还必须保留旧功能并完成 WS3；语音路线仍需最终收口，不能将比较草案直接当作固件实施指令。

日期：2026-10-08
收件方：X1 固件开发与 Windows 上位机开发同事
用途：确认 mac 客户端可以并行启动的范围，以及开放设备写入前必须稳定的协议与行为。

复核说明：本文的依赖清单不等于要求对方重新提供整套资料。Harness 已包含基线、接口设计、生产代码和验收证据；应直接复用仓库内容。真正需要额外答复的事项见第 6 节。

## 1. 对接结论

mac 客户端可以与固件、Windows 上位机并行开发，不需要等待 Windows 客户端全部完成。真正的前置依赖是共同固件的协议契约、可复现的测试固件，以及写入和持久化行为的明确边界。

建议先启动帧解析、固件识别、只读配置、设备状态展示和草稿管理。写入功能逐项开放，不以“能收到 ACK”作为功能已经适配的依据。尚未稳定的命令先保留只读或禁用保存，避免两端依据不同假设写坏设备配置。

本轮基于旧版 mac 客户端及 WS1/WS2 接口，不引入 Runtime 架构迁移。既有 CPU、Hook、电量和灵动岛修复需要保留。当前实体拨杆只展示真实状态；新增的是“配置每个物理位置的绑定”，不是软件模拟切换拨杆。

## 2. 本次讨论的基线

- 固件仓库：<https://github.com/AhakeyAI/AhaKey-X1-hardware-source/tree/Fireware-harness>。
- 2026-10-08 查阅的分支头：`d1b46a14a796790f2ffe0d228e6c5badcfc34d75`。
- 交接说明接受的 WS2 CP4D 基线：`8167ba13049c781da2f975bc803eccfe0e6ea2aa`。
- 对应 HEX：`.ahakey-harness/evidence/builds/ws2-cp4d-ordinary-key-readback/HID_Keyboard_582m_vibe_coding.hex`。
- HEX SHA256：`6F9759EB912EC067564C4E63558589AB9732126344D52C2D2A278383119516BE`。
- 固件目录 key：`x1-c582-hw1-p1-1.0.0-r001`。
- 对接依据：`WS1_WS2_FIRMWARE_AND_HOST_HANDOFF(1).md`，日期 2026-10-08。

该基线用于首次联调，不能代表尚未提交或仍在调整的 Windows/固件实现。每次换测试固件都需要提供提交号、HEX 哈希和差异说明；catalog key 用于识别能力，不足以区分同一个 key 下的不同测试构建。

## 3. 前置依赖及仓库已有资料

### 已有材料的取得方式

以下资料已在 `Fireware-harness` 中，不需要重新整理或重发：

| 资料 | 仓库位置 | 对接处理 |
| --- | --- | --- |
| CP4D 固件基线、HEX、SHA256、接受范围 | `.ahakey-harness/evidence/workstream-closures/WS2-FINAL-REVIEW-20261007.md` 及对应 builds 目录 | 直接锁定并使用；仅确认未提交的小改动是否会替换此基线 |
| `0x9F/0x92/0x96/0x97/0x87` 的设计与产品语义 | `.ahakey-harness/workstreams/X1-INPUT-CONTROL/ARCHITECTURE.md`、CP4D Stage B 修订、`APP/sub_main/command_solve.c` | mac 端自行抽取协议，不要求对方重写 |
| `0x95` 的合法值、自持久化和错误路径 | WS1 CP3A owner decision、`APP/services/standby_config.*`、`command_solve.c`、standby host tests | 直接实现，不额外要求设计说明 |
| BLE `0x9F` 长响应及验收 | CP3 的 `CP3-BLE-9F-LONG-RESPONSE-OWNER-UAT-PASS-20261001.md` 及相关实现 | 直接复用，mac 做自身接收重组测试 |
| side switch binding、物理动作 gate、Disabled 语义 | WS2 Architecture 的 CP4C 及对应测试/UAT | 属于明确的固件契约，不是待补充的新需求 |
| 独立长按配置、Restore Factory 的范围 | WS2 Architecture 的 CP2/CP4D 与 WS2 Final Review | 已明确暂缓；mac 不纳入首版，不要求补一个新协议 |

`macos_latest_firmware_sync_handoff.md` 日期为 2026-06-08，包含当时的 Windows 能力和 USB transport 建议，可作历史参考；它不能证明 2026-10-08 的 Windows 客户端已经适配 WS1/WS2 新接口。

`tests/protocol-golden/` 当前列出的内容只有 README，给出了 fixture 组织方式；这不等于仓库没有协议说明或测试。共同字节样例可由 mac/Windows 从现有代码与契约整理，不应作为要求固件方补交整套文档的开工阻碍。

### mac 开发依赖总表

下表多数是仓库现有材料的使用依赖。D1 只需补充未提交变更，D4/D6 只需确认具体行为边界，D8 才涉及最新 Windows 上位机实现；其余条目由 mac 端直接查阅已有内容。

优先级含义：P0 为首次真机联调所需；P1 为开放相应写入功能所需；P2 为候选安装包验收所需。模拟器、界面草稿和单元测试不必等待所有条目完成。

| 编号 | 优先级 | 所需内容 | 负责方 | 对 mac 开发的影响 |
| --- | --- | --- | --- | --- |
| D1 | P0 | 本轮测试固件提交、HEX、SHA256、硬件型号/修订、已知问题，以及尚未完成的小改动列表 | 固件 | 固定测试对象，避免同一问题在不同构建上反复变化 |
| D2 | P0 | `0x00/0x87/0x95/0x96/0x97/0x9F` 的字段、枚举、请求与响应样例、错误码；说明它们是已接受还是待定 | 固件牵头，Windows/mac 共同核对 | 两端据此实现同一编解码和错误处理 |
| D3 | P0 | BLE 分包样例、完整帧边界、USB report 长度/填充规则、最大响应长度；特别说明 `0x87/0x97` 的 BLE 行为 | 固件 | 单个 USB report 不等于单个 BLE notify；必须验证重组与边界处理 |
| D4 | P1 | 各写入命令何时 ACK、是否自持久化、失败码、何时可读回；`0x92` 重启保持和 `0x97` 保存失败的定义 | 固件 | 决定 UI 能否显示成功，以及是否需要追加保存命令 |
| D5 | P1 | 旧 `0x73 + 0x04` 普通键写入在新固件中的支持范围，是否影响 Voice、短/长按及其他配置；长按配置协议是否已有 | 固件 | 未明确前不开放独立长按配置或四模式全量覆盖 |
| D6 | P1 | Mac Consumer Voice 与 `0x96 suppress` 的关系；Suppress 是否只隐藏引导、是否终止已有 Voice preset | 固件与产品，Windows 同步知情 | 避免配置流程使已经可用的 K1 Voice 失效 |
| D7 | P1 | `0x97` 两档绑定类型、Custom 的动作编码/长度、另一档默认值，以及 Factory/Custom/Disabled 对 AI 工作流的含义 | 固件与两端上位机 | 防止把物理上档但绑定 Custom 的位置误判成自动批准 |
| D8 | P2 | Windows 已实现的协议样例或抓包、跨端交替配置流程，以及双方约定的变更通知方式 | Windows 牵头，固件/mac 配合 | 复用共同测试数据，确认 Windows 写入的配置可被 mac 正确读回，反向亦然 |

建议把 D2/D3 的字节样例整理成共同的 JSON fixture：包含命令、请求十六进制、分片数组、预期解析结果和错误结果。C、Swift 和 Windows 实现分别消费这些样例，无须共享平台通信代码。

## 4. 已发现的接口风险与待确认事项

### 4.1 旧客户端连接后可能覆盖设备配置

旧客户端存在四模式批量写入、待连接成功后自动同步，以及 ACK 后把本地草稿标为已应用的流程。新适配版需要先读回键盘配置，再处理草稿冲突；只写明确变更的字段，并在写入后读回比较。连接、重连和退出编辑不应触发默认草稿覆盖。

如果某个键无法读回，该键保持未验证/只读，不能用本地默认值补齐后参与全量保存。`0x87` 返回超长错误时也不能截断后显示为有效配置。

### 4.2 Voice suppress 可能改变有效动作

查阅基线源码时，Mac Consumer Voice 路径依赖 `voice_onboarding_state == completed_mac`；`0x96 suppress` 会改为 `suppressed_by_desktop`。这意味着无条件 suppress 可能使 Consumer Voice 路径失效，且 `0x87` 的旧绑定读回不能单独描述这个有效行为。

请明确“关闭初学者引导”和“改变 Voice 行为”是否应分离。确认前，mac 端先只读 onboarding 状态，不在连接或进入配置时无条件 suppress。

### 4.3 普通键回读并不覆盖完整长按能力

当前 `0x87` 读取 `user_key_bind/user_key_desc`。固件内部已有短/长按安全基础，但本轮交接未提供独立 short/long slot、阈值和执行方式的完整桌面配置协议。不能因为内部逻辑存在，就开放一个无法验证保存结果的长按编辑器。

普通键响应受 64 字节限制：完整帧包含 11 字节固定开销，因此 action 与 description 的合计长度必须受限。mac 与 Windows 需要使用同一错误处理，不以旧客户端允许的动作长度推断新固件可回读长度。

### 4.4 ACK 和永久保存不是同一项证明

`0x95` 是自持久化命令，并做了 EEPROM 校验，不应再追加 `0x04`。查阅的 `0x97` 代码调用保存后返回 ACK，没有与 `0x95` 同等的显式持久化校验。

写后读回一致可以证明当前配置一致；重启后仍一致才覆盖持久化验收。请固件方确认保存失败是否可被上位机识别。`0x92` 的持久化也需要使用约定测试固件做重启验证。

### 4.5 物理拨杆与审批策略不能只按位置对应

`sw_state=0/1` 是物理位置，`0x97` binding type 是该位置的配置。只有有效读回的 Factory Auto/Manual 才能作为 AhaKey 的工作流策略输入；Custom、Disabled 和 `sw_state=2` 不能产生新的自动批准决定。

mac 端要一并检查退出 Factory Auto 时的既有审批配置恢复，避免 Hook 已中性返回但旧的自动批准配置仍生效。软件切档和软件覆盖不会重新引入。

### 4.6 两端并行开发不等于同一设备可以并发写入

当前接口没有配置 revision/CAS，无法保证两个上位机同时写入不互相覆盖。联调阶段同一设备只保留一个配置写入方；切换 mac/Windows 或发生重连后，先重新读回基线，再处理本地草稿。

状态展示也以实际字段为限。现有 `0x00` 不包含完整生命周期 phase 或充电状态，客户端不能仅凭“配置通道连接成功”推断 HID 已可输入、正在充电或已经进入某个固件 phase。

## 5. 可以立即启动和需要等待的工作

| 阶段 | 可以开展的 mac 工作 | 开放条件 |
| --- | --- | --- |
| A 协议与模拟开发 | 帧重组、错误解析、能力模型、设备快照/草稿分离、共同 fixture 测试 | 可立即启动；协议变化时更新 fixture |
| B 只读真机预览 | 固件识别、状态展示、普通键/侧边开关/待机/onboarding 读取 | D1–D3 达到本轮可测试状态 |
| C 设置写入候选 | 模式切换、待机设置、侧边开关配置；经确认的普通键旧写入 | 对应 D4–D7 已确认，ACK 与读回测试通过 |
| D 跨端验收与打包 | mac/Windows 交替配置、断线/重启、Voice、Hook、CPU 和安装升级回归 | D8 就绪；候选固件与客户端版本固定 |

首版建议保留 BLE 配置通信。USB 作为键盘输入连接可正常使用，但 mac 的 USB 配置传输若也需要支持，必须明确增加工作包；Windows 的 USB 实现完成不能直接证明 mac 的 USB 配置能力已经完成。

本轮暂不扩展 Restore Factory、完整独立短/长按配置、固件升级/回滚/恢复，以及未纳入本轮接受范围的 WS3 `0x98/0x99/0x9A` 功能。

## 6. 真正需要额外确认的事项

不需要重新提供 HEX、哈希、完整命令表或重写 Harness。建议仅对以下问题作简短答复；已在仓库说明的，请指出具体路径即可。

```text
1. 【固件进度】提到的“尚未完成的小改动”具体是什么，是否未推到该分支，是否改变上述命令？mac 是否可先按 CP4D 开始联调？
2. 【固件错误语义】0x97 当前保存后返回 OK；存储实际失败时是否有可供上位机识别的错误码或检测路径？若目前没有，确认作为已知限制，mac 采用写后读回及重启验证，不自行假设存在该错误码。
3. 【跨端产品行为】completed_mac 后发送 0x96 suppress 会使 Consumer Voice 的启用条件不再成立。是否预期由桌面语音方案接管，还是希望保留固件 Consumer Voice？协议状态已有定义，这里只确认桌面接管意图，不要求重新设计协议。
4. 【Windows 上位机，可选】若需要行为对标，请提供正在修改的 Windows 客户端仓库/分支或提交，以及已有的 WS1/WS2 适配记录位置；不要求它先完成，也不要求固件仓库包含 Windows 客户端源码。
```

mac 首版是否实现 USB 配置通信、何时安排 mac 真机测试、如何组织共同 fixture，属于 mac/项目自身的范围决策，不应作为让固件方补文档的要求。

建议约定：字段、枚举、长度、命令语义、持久化规则或固件身份能力发生变化时，先更新共同契约与样例，再通知两端。不能把“客户端已经能解析”当成固件接口可以不经通知继续变更的理由。

## 7. 可直接转发的摘要

Harness 已有的固件基线、协议设计、代码和验收证据我们会直接复用，不需要你重新整理。只想确认尚未推送的小改动及是否可先按 CP4D 联调，另外确认 0x97 存储失败的可识别性，以及 completed_mac 后 suppress 是否预期交给桌面语音方案接管。如果需要对标 Windows 客户端，再请 Windows 上位机同事给当前代码分支或适配记录位置；mac 可以先开始只读适配，不等 Windows 全部完成。

## 8. 依据

- [WS2 最终接受范围与待完成项](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/d1b46a14a796790f2ffe0d228e6c5badcfc34d75/.ahakey-harness/evidence/workstream-closures/WS2-FINAL-REVIEW-20261007.md)
- [命令解析、状态响应与持久化路径](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/d1b46a14a796790f2ffe0d228e6c5badcfc34d75/APP/sub_main/command_solve.c)
- [Voice onboarding 与 Mac Consumer 路径条件](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/d1b46a14a796790f2ffe0d228e6c5badcfc34d75/APP/sub_main/main.c)
- [普通键策略与 Consumer Voice dispatch](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/d1b46a14a796790f2ffe0d228e6c5badcfc34d75/APP/hardware/psk_multi_button.c)
- [旧版客户端基线 main](https://github.com/AhakeyAI/desktop/tree/6c94704ba8d491bec742dc38cda62ef2a3a19cb5)
- [旧版 Cursor Hook 修复 PR 78](https://github.com/AhakeyAI/desktop/pull/78)

## 9. 对方答复后的启动判断

对方补充：未完成的小改动集中在 OLED/灯光；存储失败按其设计会有上位机提示；Windows 客户端仍在修改，代码可稍后提供；尚未完成的主要阶段为 WS3、WS4/WS5。

据此，mac 的 WS1/WS2 适配可以启动，不再把 Windows 当前代码或额外文档作为开工条件。存储失败提示先列为联调预期：测试确认固件拒绝、超时、读回不一致等情况能显示失败并保留草稿；“目前 Windows 会提示”不能直接证明 mac 已实现相同提示。

### suppress 的含义

这里的 suppress 指“关闭键盘上的初学者语音引导”，不是停止 AI、禁用麦克风或恢复出厂。Harness 的 `0x96` 已定义：查询发送 `AA BB 96 CC DD`；桌面接管引导发送 `AA BB 96 03 CC DD`，将 onboarding 状态记为 `suppressed_by_desktop`。

当前 Mac Consumer Voice 路径依赖 `completed_mac` 状态，切到 `suppressed_by_desktop` 后该条件不再成立。首版默认不因连接就无条件 suppress，先保留已经可用的键盘 Voice；只有桌面语音方案确认可用并决定接管时，才安排这一步及对应测试。这个问题可由 mac 适配方案处理，不作为继续追问固件方的开工门槛。

### 阶段范围及剩余风险

| 阶段 | Harness 定义的范围 | 对本次 mac 适配的处理 |
| --- | --- | --- |
| WS1/WS2 | 连接电源、输入控制、固件识别、模式、待机、onboarding、侧边开关、普通键只读回读 | 作为第一版适配基线，直接开展实现与联调 |
| WS3 CP1 | AI/task SINGLE/MULTI 显示、`0x90` 兼容与 `0x98/0x99/0x9A`、OLED/灯光显示仲裁 | 本轮保留已有安全 `0x90` 路径；不因某次 WS3 验收通过就推定当前 CP4D 构建已集成全部行为 |
| WS3 CP2/CP3 | 灯效/亮度预览、显示配置保存、19 项资源表/布局、上传读回事务、显示资源恢复与验收 | 不纳入第一版新功能承诺；暂缓新的资源布局迁移和显示恢复功能 |
| WS4/WS5 | Host Protocol 与持久化治理、固件身份/版本目录、发布整合、稳定 HEX 与恢复路径；整机恢复出厂后续设计 | 本轮只固定测试固件与能力范围，不承诺最终升级/恢复/整机恢复出厂能力 |

查阅的 `project-state.yaml` 仍记录 WS3 CP1 需要重新应用到 WS2 CP4D 基线上。这说明“之前验收过”和“当前要烧录的候选已包含”需要按实际构建区分；每次换固件都做身份与关键行为回归即可，不要求两端开发停止等待。

剩余风险主要是显示资源功能后续返工、mac 写入与错误提示尚待真机验证、Voice 接管行为变化，以及 mac/Windows 交替配置的差异。它们由固定基线、设备读回、保留草稿和跨端验收处理；目前没有必须等待 Windows 全部完成才能开工的依赖。

阶段依据：

- [WS3 三阶段范围](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/d1b46a14a796790f2ffe0d228e6c5badcfc34d75/.ahakey-harness/workstreams/X1-AI-WORKFLOW-PRESENTATION/PRD.md)
- [当前 Harness 阶段状态](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/d1b46a14a796790f2ffe0d228e6c5badcfc34d75/.ahakey-harness/project-state.yaml)
- [WS4/WS5 发布整合范围](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/d1b46a14a796790f2ffe0d228e6c5badcfc34d75/.ahakey-harness/workstreams/X1-PLATFORMIZATION-RELEASE-COMPOSITION/PRD.md)
