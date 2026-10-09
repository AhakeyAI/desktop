# 旧版 mac 客户端 WS1 WS2 固件适配计划

> 2026-10-09 交接注：这是本轮讨论材料。已确认决策和未决事项以 [跨设备交接](../handoff/CONNECT_AND_TALK_HANDOFF.md) 为准。初始计划/WBS 只覆盖 WS1/WS2 阶段，最终用户版还必须保留旧功能并完成 WS3；语音路线仍需最终收口，不能将比较草案直接当作固件实施指令。

日期：2026-10-08
状态：开发计划，尚未开始客户端实现。
配套：[WBS](./legacy-macos-ws12-adaptation-wbs-2026-10-08.md)、[可导入 CSV](./legacy-macos-ws12-adaptation-wbs-2026-10-08.csv)、[依赖及对接记录](./legacy-macos-firmware-adaptation-prerequisites-2026-10-08.md)。

## 1. 交付目标

基于旧版 SwiftUI mac 客户端，交付一份能安装运行、识别新固件、读取设备真实配置并安全修改 WS1/WS2 已接受设置的适配候选版。配置是否生效由键盘读回决定，本地草稿和未验证缓存不能代替键盘事实。

可以立即启动，不等待 Windows 客户端全部完成。对方已说明剩余小改动集中在 OLED/灯光；本轮以已接受的 WS1/WS2 为功能边界，把后续固件变化作为增量联调，不要求重新提供 Harness 中已有的材料。

本计划与 AhaStudio 完整软件的 06/07 开发计划分开：这里只涉及旧键盘配置客户端，不实施全新任务中枢、Runtime 架构迁移或完整软件产品建设。

## 2. 基线与分支策略

- 开发基线：启动时从 `AhakeyAI/desktop` 的最新旧版 `main` 建独立适配分支，保留 CPU、电量、Codex、灵动岛与实体拨杆只读修复。
- 截至本轮核对，旧版 `main` 为 `6c94704`；Cursor 修复 PR #78 仍开放。开工时复查其合并状态：已合并则直接保留；未合并则记录来源并纳入适配分支，不能遗漏该修复。
- 不以当前 `feat/unified-client` 快照替代旧版客户端基线，不覆盖已有脏工作区。
- 首轮固件基线：WS2 CP4D `8167ba13049c781da2f975bc803eccfe0e6ea2aa`；HEX SHA256 为 `6F9759EB912EC067564C4E63558589AB9732126344D52C2D2A278383119516BE`。
- 查阅的 `Fireware-harness` 分支头为 `d1b46a14`。每次换固件记录提交、HEX 哈希和相关变化；同一 catalog key 不当作同一测试构建。
- 固件升级不是本轮实施动作。首次真机联调前由设备提供方确认键盘已安装约定固件。

## 3. 首版范围

| 功能 | 本轮实现 | 成功标准 |
| --- | --- | --- |
| 固件身份 | `0x9F`、已知能力配置、旧 `0x00` fallback | 正确区分已知新固件、旧固件和未知 profile；身份字段与 App 版本分开 |
| 接收与事务 | BLE 帧重组、长度校验、串行请求、超时和断线清理 | 多 notify 不丢帧；截断/错误/过期回包不改变新连接的配置状态 |
| 设备读回 | `0x00/0x87/0x95/0x96/0x97` | 16 个普通键按真实长度读取，异常字段可单独显示未验证 |
| 配置状态 | 设备快照、本地草稿、last-known 参考、读回差异 | 重连先读；不隐式全量覆盖；草稿不会被失败或冲突静默丢弃 |
| 模式切换 | `0x92` ACK + `0x00` 读回 | 读回目标一致才成功；离线浏览不重放到设备 |
| 待机设置 | `0x95` 读取/设置/读回 | 仅 0/30/60/120 分钟；不追加 `0x04` |
| 侧边开关配置 | `0x97` 两位置 Factory/Custom/Disabled 配置与读回 | 对物理位置不做软件覆盖；Custom 由固件执行；保存后读回确认 |
| 普通键基础编辑 | 经基线验证的旧 `0x73` 映射/宏/描述与 `0x04` 保存 | 仅写实际修改的可表示键；`0x87` 一致后更新已应用状态 |
| Agent/Hook | 同步身份与侧边绑定；Factory Auto/Manual 策略解释 | 只有新鲜且验证过的 Factory Auto 自动放行；Custom/Disabled/未知不误产生批准 |
| Voice | 读取 onboarding、保留可用语音；受条件约束的桌面接管 | 不因连接无条件 suppress；不会同时触发 Consumer Voice 与旧语音桥 |
| 原有显示能力 | 保留确认兼容的旧显示与 `0x90` 状态通路，关闭隐式资源上传 | 连接不会覆盖固件出厂资源；不以旧 ACK 推定新资源系统已适配 |

普通键回读失败/超长/未知动作时，该键保持只读，其他独立可验证设置可继续使用。Power 不进入 K1–K4 编辑。首版不开放独立短/长按 slot 和阈值编辑。

## 4. 明确暂缓的功能

- mac USB HID 配置传输：首版先做 BLE 配置。USB 键盘输入正常使用与 USB 配置通信是不同能力。
- WS3 SINGLE/MULTI 新展示、`0x98/0x99/0x9A`、19 项资源布局、新资源上传事务和显示资源恢复。
- 完整独立长按配置协议、整机 Restore Factory、版本目录、固件升级/回滚/恢复等 WS4/WS5 功能。
- Windows 最新界面/代码完全对齐：后续代码到位再联调，不挡 mac 单端候选版。

旧显示功能若在本轮固件上不能证明兼容，相关写入先禁用并说明原因，不伪装保存成功。Windows 或 USB 后续加入时单独估算和新增任务，不能偷偷扩入当前 WBS。

## 5. 实现结构与关键规则

沿用 SwiftUI、CoreBluetooth 和旧 Agent/socket，补齐几个边界清楚的模块；建议命名可在实现时调整：

1. `FirmwareProfile`：catalog key、协议 profile、已核验能力；不靠亮度字段或旧版本号盲目开放所有新写入。
2. `DeviceFrameDecoder`：GUI 与 Agent 共用的解帧代码；按命令格式/长度处理二进制载荷，不能仅寻找第一个 `CC DD` 就截帧。
3. `DeviceCommandSession`：串行命令、模式/键等请求参数对应、连接代次、超时和取消；迟到 ACK 不能提交新事务。
4. `DeviceConfigurationSnapshot` 与草稿：读回值和草稿分开；缺失字段保留未知，不用本地默认值补全后写回。
5. `ApplyCoordinator`：写前复查受影响字段，写入、ACK、读回对比、保存结果与重试。协议没有跨端 revision/CAS，因此不声称跨主机原子保存或完整事务回滚。
6. `WorkflowPolicy`：物理位置、位置绑定类型、状态有效性分别建模；Agent 自己读到必要事实，不能只依赖 GUI 的缓存。退出 Factory Auto 时还要处理 AhaKey 已施加的审批配置恢复。

同一设备配置写入保持单一拥有者。App/Agent 交接和重连会使旧配置快照失效；mac/Windows 交替使用后重新读取基线。失败后保留草稿，明确哪些变更已验证、哪些未验证，避免整个批次被标为成功。

## 6. 三次交付与验收门

### G0 开发准备

完成 M01/M02：干净旧版基线、已存在修复核对、Harness 契约摘要和测试 fixture。无需 Windows 新代码；模拟开发无需先连真机。

### G1 只读预览版

完成协议/能力、App/Agent 交接、所有只读接口和设备快照/草稿分离。产物是可运行的本地预览 App。

验收：新固件身份、电量、当前模式、拨杆及配置可读；分片和异常响应不崩溃；连接/重连不写键位、不上传 OLED、不修改侧边绑定。旧固件可降级使用，未知高级配置保持只读。

### G2 写入候选版

完成模式、待机、侧边开关、可回读普通键编辑、审批语义、Voice 保护及 UI。每一功能在自身读回条件满足后开放，不必等待所有设置一起完成。

验收：ACK + 匹配读回才报成功；失败保留草稿；离线点击不重放；物理 Custom/Disabled 与 unknown 状态不会误自动批准；Mac Voice 不重复触发或因无条件 suppress 失效。

### G3 mac 真机验证与安装候选

完成错误注入、重启/断连/交接、长宏边界、语音、原功能回归、CPU 与安装升级测试，随后出签名候选包与 PR。公证分发按正式发布要求执行。

Windows 跨端联调是可选工作包：代码/设备到位后执行。它不挡仅供 mac 验证的候选版，但在对外宣称跨端配置兼容前必须通过，未完成时在验收记录明确标注。

## 7. 并行路线与估算

- 协议/Agent 路线：解帧、命令队列、只读接口、侧边绑定与审批。
- 客户端路线：设备快照/草稿、取消自动覆盖、设置界面、保存状态与 Voice。
- 验证路线：fixture、错误模拟、真机脚本和构建证据；读取接口完成后尽早进入真机检查。

WBS 人日含实现、必要测试和说明，是计划估算，不是已完成状态或日历工期。先完成接口基础，再安排 UI 与 Agent 分支并行；实际排期取决于人员数量、键盘与固件可用性。不把模型/Agent 的墙钟运行时间等同工程人日。

每个工作包验收时记录源码 SHA、固件 SHA/HEX 哈希、测试结果和已知限制；只有具体检查通过才更新完成状态。若 OLED/灯光变更影响原假设，仅重新核验受影响能力。

## 8. 验收重点

- 分包、合包、截断、未知响应、载荷包含帧尾字节、超时、迟到 ACK 和断线后的代次清理。
- 16 键完整/部分读回、`0x87 03`、未知动作、label 长度和二进制原始数据保留。
- 模式/待机/侧边绑定/普通键的成功、拒绝、超时、读回不一致和重启后保持。
- Factory Auto/Manual、Custom/Disabled 和 `sw_state=2`；涉及 Claude/Cursor/Codex/Kimi 的实际策略和既有配置恢复。
- 初始已完成 Mac onboarding、未完成 onboarding、桌面接管，以及连接/重连不自动发送 suppress。
- App/Agent BLE 交接、普通 HID 输入、Power 行为、现有电量/语音/灵动岛/CPU 修复。

存储失败按对方答复应有上位机提示，列为联调预期；没有可注入的 EEPROM 故障时，明确记录未覆盖该物理故障，不以超时测试替代真实存储故障证明。

## 9. 依据

- [固件 WS2 已接受范围](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/d1b46a14a796790f2ffe0d228e6c5badcfc34d75/.ahakey-harness/evidence/workstream-closures/WS2-FINAL-REVIEW-20261007.md)
- [固件命令实现](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/d1b46a14a796790f2ffe0d228e6c5badcfc34d75/APP/sub_main/command_solve.c)
- [WS3 范围](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/d1b46a14a796790f2ffe0d228e6c5badcfc34d75/.ahakey-harness/workstreams/X1-AI-WORKFLOW-PRESENTATION/PRD.md)
- [WS4/WS5 范围](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/d1b46a14a796790f2ffe0d228e6c5badcfc34d75/.ahakey-harness/workstreams/X1-PLATFORMIZATION-RELEASE-COMPOSITION/PRD.md)
