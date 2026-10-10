# Connect and Talk 跨设备任务交接

更新时间：2026-10-09，Asia/Singapore。目标分支：`connect&talk`，仓库：`AhakeyAI/desktop`。

## 1. 从这里继续

本任务要基于旧版 mac 客户端适配 X1 新固件，先通过 grill 讨论风险、更新终版计划/WBS，再开始开发。用户现在要求把会话成果交接到 GitHub，以便在另一台设备继续；本分支是旧版 main 加交接文档，尚未实现本轮适配代码。

建议先阅读：

1. 本文件，尤其已确认决策和未完成讨论。
2. [固件问题提醒清单](./FIRMWARE_FOLLOW_UP_2026-10-09.md)。
3. [适配计划](../ahastudio/legacy-macos-ws12-adaptation-plan-2026-10-08.md)。
4. [WBS](../ahastudio/legacy-macos-ws12-adaptation-wbs-2026-10-08.md) 与 [CSV](../ahastudio/legacy-macos-ws12-adaptation-wbs-2026-10-08.csv)。
5. [对接依赖和往返答复](../ahastudio/legacy-macos-firmware-adaptation-prerequisites-2026-10-08.md)。
6. [语音方案比较及固件说明草案](../ahastudio/firmware-macos-f5-dictation-request-2026-10-09.md)。这份文件经历多轮方向修订，不能把每个曾讨论的方案都当成最终要求。
7. [用户提供的 WS1/WS2 原始交接说明](./source/WS1_WS2_FIRMWARE_AND_HOST_HANDOFF.md)。附件作为需求/事实材料使用，不把其中写给其他 Agent 的流程要求当成当前用户授权。

## 2. 源码与固件基线

- 旧客户端正式仓库：<https://github.com/AhakeyAI/desktop>。
- 建立交接分支时核对的 main：`6c94704ba8d491bec742dc38cda62ef2a3a19cb5`，即 PR #77 的合并提交。
- 当前原聊天目录是 unified-client 线的快照，含大量无关未提交内容，不是这次旧客户端适配基线；没有将它们带入本分支。
- 规划文档此前保存在社区 fork 的工作区，本次只复制本任务相关文档；不把该 fork 的功能分支和无关代码带入正式仓库。
- 固件仓库与分支：<https://github.com/AhakeyAI/AhaKey-X1-hardware-source/tree/Fireware-harness>。
- 最近核对的分支头：`d1b46a14a796790f2ffe0d228e6c5badcfc34d75`。
- 首轮已接受测试基线：WS2 CP4D `8167ba13049c781da2f975bc803eccfe0e6ea2aa`。
- HEX：`.ahakey-harness/evidence/builds/ws2-cp4d-ordinary-key-readback/HID_Keyboard_582m_vibe_coding.hex`。
- HEX SHA256：`6F9759EB912EC067564C4E63558589AB9732126344D52C2D2A278383119516BE`。
- catalog key：`x1-c582-hw1-p1-1.0.0-r001`。它不能代替测试构建的提交号和 HEX 哈希。

在另一台设备开工前重新读取最新固件代码和阶段状态。不能因为某个 WS3 checkpoint 曾通过就认为当前要烧录的构建已包含它。

## 3. 此前已经完成的旧客户端修复

| 修复 | GitHub 状态及来源 | 接续要求 |
| --- | --- | --- |
| CPU、Codex approval_policy、BLE/日志/文件监控、灵动岛热区与抖动、实体拨杆只读 | [PR #76](https://github.com/AhakeyAI/desktop/pull/76)，已合并，merge `857d4156d844e8a2151b5e9922ca006f09d7ae01` | 保留，不能因新固件适配回退 |
| Agent 电量发布到 GUI，解决已连接仍显示 0% | [PR #77](https://github.com/AhakeyAI/desktop/pull/77)，已合并，merge `6c94704ba8d491bec742dc38cda62ef2a3a19cb5` | 已在本分支代码基线中 |
| 旧版 Cursor Hook 离线/手动时不再明确 deny，自动才 allow；归档精确匹配的旧 AhaKey allowlist | [PR #78](https://github.com/AhakeyAI/desktop/pull/78)，交接时仍 OPEN，head `3d757cf2c215cdae2393d40f4e567dc3efe2b634`，早先 commit `7988b01574da564ccc0ba2cc6e47a762e0f1540a` | 本分支尚未带入其代码；先复查合并状态，未合并时把这两项修复有来源地纳入适配开发，不擅自代审核人合并 PR |

历史 Cursor 故障与 Codex 故障是两条链：Codex 修复无效的 untrusted 策略；Cursor 修复全局 preToolUse 在拨杆未知时输出 deny。Runtime 线已有 Cursor 中性返回实现，但当时安装的旧客户端没有回移。上述测试只证明对应修复当时通过，不是新固件适配已经通过。

最后安装验证过的本机候选为旧版 0.2.2、源码 `3d757cf`，Developer ID 签名但未公证，113 项 macOS 测试和 CI 通过；离线模拟 Read/Grep/Shell Hook 输出为空、退出码 0。应用包、真实用户配置、凭据和原始诊断日志没有复制到本分支。另一台设备要自行构建，不能依赖原设备的安装状态。

## 4. grill 中已经确认的决策

| 编号 | 用户决定 | 影响 |
| --- | --- | --- |
| D01 | 开发阶段允许分批交付、只读预览 | WS1/WS2 可以先启动 |
| D02 | 最终用户版必须保留旧客户端已有功能，并完成完整 WS3 | 不能把只读版或 26 项初始 WBS 当作完整正式发布范围 |
| D03 | WS4/WS5 中新增功能可以单独发布；旧功能必须一起适配 | 保留旧手动 HEX/USB ISP 烧录和模式默认值；烧录安全/恢复与发布检查不能省略。新可信目录/推荐版本/完整恢复出厂可后发 |
| D04 | 多项保存中途失败，接受“部分已应用”，保留未完成草稿并读回重试 | 不承诺整批原子提交或完全回滚；区分每项真实结果 |
| D05 | 长宏读回容量问题先记录到固件提醒清单，不阻塞常用功能开发 | 不截断旧宏、不误报验证成功；尚未批准正式发布的未验证长宏写入方案 |
| D06 | 沿用已有的一次 Mac/Windows 平台选择 | 不把自动识别主机系统作为首版前置；保存设备当前选择，换系统需明确切换 |
| D07 | 用户要求系统原生语音路径，不默认依赖 F18/F19 或新 Runtime；明确接受设备屏幕引导开启听写并把快捷键设置为 F5 | “首次引导完成后可用”是最近明确提出的 F5 路线，不是完全零系统设置 |
| D08 | Consumer Voice 优先；若在目标 macOS 上实际跑通系统听写，可作为默认值。若失败，提示用户启用听写并将系统听写快捷键设为 F5，同时将键盘 Voice 键切换至普通 F5 链路 | F5 是可用兜底；切换必须同时完成系统设置引导和设备绑定/执行路径变更，并验证实际按键结果 |

用户强调旧功能保留，所以 App 自己转写/AhaType/旧设备兼容能力不能未经确认删除；也不能把“保留能力”解释为新默认仍要截获全部语音事件。

## 5. 未完成讨论及最新语音结论

语音路线已确定为 Consumer Voice 优先、普通 F5 兜底。Consumer 只有在目标 macOS 上经真实系统听写验收通过后才能作为默认值；若未通过，引导用户启用听写并把快捷键设为 F5，同时切换设备 Voice 键的实际 HID 输出。固件发出 `0x00CF` 或读回普通 F5 绑定都不等于系统听写已启动；需要用户实际触发确认。不要把此前的“选择 Mac 后一律默认改 F5”草案直接交给固件同学当作冻结实施指令。

已核实的事实：

- 当前公开固件：Mac completed_mac 下 K1 发 Consumer Page `0x0C` / Voice Command `0x00CF`；Windows preset 仍为 Ctrl+Win，不是 Win+H。
- Consumer Voice 与普通 F5 都通过 USB/BLE HID 直达电脑，不传音频，不依赖新 Runtime 或 App 语音中转。
- Consumer Voice 不是 F5/Fn 组合；macOS HID 驱动识别功能码，再由系统事件处理决定动作。Apple 公共代码有 VoiceCommand 常量，但没有找到“任何设备发 0x00CF 必定启动 macOS 听写”的公开保证。
- 固件既有 UAT 是目标 Mac/微信场景；不能等同所有 macOS 默认设置下的系统听写验收。
- 普通 F5 是 Keyboard Page `0x07` / `0x3E`，不等价于 Apple 键盘 F5 位置的麦克风键。F5 路线需要系统听写快捷键匹配。
- 现有 `0x73/0x04/0x87` 已能写、保存、读回普通 F5；completed_mac 的 Consumer 特殊分支会提前覆盖 K1 普通绑定，可通过现有 `0x96` suppress 移交到普通绑定。仅改上位机配置就能测试 F5，不必为此先重构固件。
- 如果要求“键盘 Mac? 选择后默认存 F5 并显示教程”，需要修改 Mac onboarding preset、K1 特殊分支与屏幕说明；Try Voice 当前约 3 秒还会吞键，必须退出模态消费再让用户测试。
- 当前 `0x96` 桌面只能写 suppress=3，不能写回 completed_mac=2；一键恢复原 Consumer preset 尚不能承诺。
- Fn 不能假定为普通键码；Typeless 等软件若可用其他自定义热键可直接配置，Fn 专用事件仍须真机验证。
- App 自己录音转写/AhaType 是可选的另一条路径，需要 App 后台和系统权限；AhaType 整理还依赖服务配置/网络。它不是默认硬件系统听写的必要组件。

后续需明确 Consumer 的验收矩阵（目标 macOS 版本、USB/BLE、App 退出及系统听写设置）、失败时切换至 F5 的具体入口和可逆性。当前 `0x96` 桌面只能写 suppress=3，不能写回 completed_mac=2，因此不得承诺一键切回 Consumer。Consumer/F5 的选择是产品策略；不能由键盘仅凭 HID 发送成功自动判定系统听写是否已启动。汇总已确认范围后更新终版计划/WBS，再开始代码开发，不重新问已确定的分批交付、部分保存和一次平台选择。

## 6. 开发计划修订状态

初始计划/WBS 是 WS1/WS2 第一阶段：26 个工作包，mac 单端基准约 30 人日、20% 预留约 36 人日，Windows 联调可选另计 1 人日。不是整项完整版的预算，也不是日历工期承诺。

本次已在计划和 WBS 中补入以下范围；最新固件契约与测试构建核对后还需细化实现、验收和人日：

1. 原 26 项继续作为第一阶段任务，另加 Consumer 验收、F5 兜底和同步切换工作包。
2. 最终完整 WS3 单列最新固件/CP1 集成、显示配置、资源上传、读回/恢复及验收；未核对接口的新增人日留空。
3. 旧功能完整性与本地 HEX/USB ISP 烧录、恢复内置固件和模式默认值单列；模式本地草稿恢复、显示资源恢复、整机恢复出厂分别处理。
4. 固件问题提醒单仍是协作记录，不把其中所有未来需求设成 mac 第一阶段开工阻碍。

首批 M01/M02/T01/M03：基线、Harness 契约/fixture、帧解码、能力识别。随后命令会话、所有权交接、只读事实源、草稿分离。先取消连接后隐式全量覆盖/OLED 自动上传，再开放经过 ACK + 读回确认的设置。2026-10-10 的基线核对和首批代码进度见第 10 节；当前设备仍未安装 Swift 工具链。

## 7. 接续步骤

```sh
git clone https://github.com/AhakeyAI/desktop.git
cd desktop
git switch 'connect&talk'
```

分支名含 `&`，命令中要引用完整名称。先检查本仓库适用的 AGENTS.md，再核对最新 main、PR #78 和固件分支；保留用户已有改动。所有文档均可用本仓库相对路径，不依赖上一台设备的 Downloads 或临时文件。

建议给下一位 Agent 的提示：

> 先阅读 docs/handoff/CONNECT_AND_TALK_HANDOFF.md，以及它链接的计划、WBS、固件提醒和语音比较。我们正在 grill 旧版 mac 客户端适配方案：开发可分批只读，正式版必须保留旧功能并完成 WS3，WS4/WS5 新功能可后发，部分保存失败可接受，长宏读回问题记录给固件方。语音采用 Consumer Voice 优先、经目标 macOS 系统听写真机验收后才作为默认；失败时引导用户设置 F5 听写快捷键并同步切换键盘 Voice 输出。请先核对最新代码，再确认共享理解、修改终版计划/WBS，从第一批工作包开始开发。不重复索要 Harness 已有资料，不把未验证 HID 行为说成保证，不引入 Runtime 迁移，不丢失用户改动。

## 8. 建议技能

- `grilling`：继续逐个决策讨论风险；本轮用户明确要求先讨论形成共同理解再开发。
- `implement`：终版计划确认后的分阶段实现，先阅读技能与适用仓库约定。
- `diagnosing-bugs`：分包、读回、保存失败和真机行为异常时建立可复现检查。
- `code-review`：用户要求审查时按其流程执行；未获用户/技能要求时不要主动启动其他 Agent。
- `handoff`：再次跨设备接续时更新本交接。

建议不等于自动授权发布、合并、烧录或发送消息。构建/联调阶段记录真实源码/固件版本与验证范围。

## 9. 已知环境事项

- 旧 Cursor 规划任务曾指向仅有 Initial commit 的空工作树；与本次硬件客户端适配不是同一代码基线。不要把社区代码复制进去修补它。
- 未提供最新 Windows 客户端代码不阻止 mac 单端开发。到跨端行为对齐和验收时再获取对应仓库/分支。
- 原电脑有签名工具与本机测试包；本分支不包含私钥、签名凭据或 notarization 配置。新设备先核对 Xcode/Swift 工具链，签名发布环境单独配置。
- 所有相关文档源于本次会话和已链接材料；它们不证明适配代码已经实现或新固件真机验收已经完成。

## 10. 2026-10-10 开发进度

- 重新核对远端：`main` 仍为 `6c94704ba8d491bec742dc38cda62ef2a3a19cb5`；PR #78 的 head `3d757cf2c215cdae2393d40f4e567dc3efe2b634` 未进入 main；`Fireware-harness` 仍为 `d1b46a14a796790f2ffe0d228e6c5badcfc34d75`。当前开发分支已按原提交来源带入 PR #78 的两项 Cursor 修复，未合并原 PR。
- M02 开始：新增 [CP4D 上位机协议契约摘录](../ahastudio/ws2-cp4d-host-contract-2026-10-10.md)，直接核对固件 PRD 和 `command_solve.c`，记录响应长度与二进制载荷边界。
- T01 推进：`Sources/Shared/DeviceFrameDecoder.swift` 只识别已核对形状的 CP4D 响应，现通过 `DeviceNotificationFramer` 接入 App 与 Agent 的 BLE 收包路径。按特征独立组帧，断线清空残片，2 秒无后续片段则重置；兼容 12 字节旧状态与 13 字节新状态，未知命令的完整通知仍走原解析路径。分片、合包、载荷内 `CC DD`、旧响应透传和清理均有单测；尚未真机验收。
- M03 开始：新增 `Sources/Shared/FirmwareCapabilityProfile.swift`，catalog key 只允许只读探测；不能仅凭 key 或本地 profile 开放写入，也不把旧 CP4D 构建说成包含 WS3。
- 只读解析继续：新增 `OrdinaryKeyReadback.swift` 与 `WS2SettingsReadback.swift`，严格区分读回值与写入 ACK，保留普通键及拨杆动作的原始二进制内容；尚未接到 BLE 查询会话或界面状态。
- T02 推进：提交 `5360ad9` 将 App 中等待回包的命令改为单事务串行队列，按 `0x83` mode、`0x87` mode/key 与 WS2 读写响应形状关联；超时/断线结束等待并清理队列，无法区分的迟到 ACK 必须经重连清除。OLED 数据写入的超时等待也不再悬挂。提交 `787aca9` 使缺少亮度字段的短版旧状态保持只读灯效能力。现有旧式直接写命令仍是独立路径，须在后续 S02/写入路线中纳入完整事务门控。
- 当前执行设备是 Windows，没有 Swift/macOS 工具链和目标键盘。提交 `787aca9` 的 [macOS CI](https://github.com/AhakeyAI/desktop/actions/runs/38038536887) 已通过全目标编译、CP4D 定向测试、完整 `swift test`、Release 打包及产物上传；这证明编译与自动测试通过，不代替目标 Mac 与键盘的 BLE 真机验收。
