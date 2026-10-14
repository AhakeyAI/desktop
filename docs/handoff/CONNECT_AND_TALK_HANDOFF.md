# Connect and Talk 跨设备任务交接

## 2026-10-11 本机预检和 OLED 隐式写入修复

- `4211c5b` 在目标 Mac 上通过 136 项自动测试、arm64 Release App/Agent 构建、签名检查与 GUI 离线启动。键盘暂未准备好，真机验收未执行。
- 移除连接/图片状态变化触发的默认 OLED 自动上传，以及对应标记和函数。空槽读回不再自动写入资源；用户明确保存时的上传入口保留。修复后 136 项测试、App 编译、arm64 Release 打包和签名检查均通过；真机验证仍待键盘准备。
- 此项仅完成 S02 中的 OLED 隐式写入保护。旧全量保存、直接模式/灯效写入、新固件资源布局和保存 ACK + 读回仍需按 WBS 完成。真机只读阶段不要点击保存、同步或切换模式。
- 先前的 `local-builds/connect-talk-4211c5b-20261011` 包不包含本次修复；不得用该包验证连接后无 OLED 写入。本机修复候选位于 `local-builds/connect-talk-oled-guard-local-20261011`，包含本次改动；嵌入提交号仍指向构建时的基线，需结合随包说明和补丁识别。

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
- R01–R04 后端开始：提交 `a01dba7` 增加手动只读 catalog 探测和能力显示，已知 WS2 catalog 才开放普通键、待机、语音引导和拨杆绑定的只读查询接口；未知 catalog 不开放这些查询，更不开放写入。旧固件仅在同一连接有有效 `0x00` 状态回包且 `0x9F` 返回通用 ACK 时识别为 legacy。当前尚未将这些读回值接到统一配置快照或编辑界面，真机读回也未验证。
- 当前执行设备是 Windows，没有 Swift/macOS 工具链和目标键盘。提交 `787aca9` 的 [macOS CI](https://github.com/AhakeyAI/desktop/actions/runs/38038536887) 已通过全目标编译、CP4D 定向测试、完整 `swift test`、Release 打包及产物上传；这证明编译与自动测试通过，不代替目标 Mac 与键盘的 BLE 真机验收。

- T03 交接推进（efe00e）：App 让出 BLE 时立即使在途命令、固件能力和连接相关缓存失效，等待 CoreBluetooth 断线回调后才允许新连接；旧外设的服务/特征/RSSI/写入回调需匹配当前外设。AgentManager 的延时启动和回退按交接代次过滤；Agent 重连后旧状态查询超时不会结束新查询，断线清除拨杆/灯效缓存和延时灯态。跨进程 lock 仍负责单一连接拥有者。该提交的 macOS CI（编译、测试、打包）已通过：https://github.com/AhakeyAI/desktop/actions/runs/38043948769 。目标 Mac 与键盘上的 App↔Agent 往返交接、断线和 Hook 行为尚未真机验收。


## 12. 2026-10-13 G1 只读快照接入

- 新增独立设备配置快照：16 个普通键、待机、语音引导、两位置侧边绑定。设备读回与 Studio 本地草稿分离，未知/过长动作保留原始结果，只读展示；逐项失败不补默认值。快照绑定连接代次，断线/交接清空，迟到结果不能重新填入旧事实。
- 「设备信息」增加明确的只读配置读取入口，自动先探测 catalog，再串行读取 WS2 字段；未识别/旧目录不猜测高级协议。该入口不 suppress、不保存，也不恢复默认。
- 设备信息页与主画布共用当前拥有者状态投影，Agent 未连接时显示未知，不把仍存在的参考缓存显示为实时电量/拨杆/模式。修复先前信息页拨杆旧值问题。
- 取消模式标签浏览的 0x92 隐式发送。新/未知固件的旧全量保存、资源上传及配置命令暂时统一门控；仅保留冻结查询与既有临时 IDE 灯态。确认的 legacy 目录仍可使用旧配置路径。写入事务 W01–W04 与新版资源布局完成后再逐项开放。
- 新增快照/命令门控测试，以及连接状态与参考缓存区分回归。140 项自动测试通过，App Debug 编译通过。真机批量读回、legacy 写入回归和完整 G1 收口尚待执行；不能将本进度标为最终用户版完成。
- 2026-10-13 Voice/Siri 与 Command 卡住排查记录见固件提醒清单新增项；固件输入可靠性缺口尚未修改。本地诊断日志和配置备份不入库。


### G1 只读快照真机补充（2026-10-13）

- 候选源码 `4c1ac57`（功能提交 `c4bc461`），签名 arm64 包位于本机 `local-builds/connect-talk-readonly-snapshot-20261013`。目标设备保持 WS2 CP4D，新固件烧录后保留历史 DataFlash，非恢复出厂样本。
- 经界面明确触发读取：`0x9F` 成功；`0x95` 返回 60 分钟；`0x96` 为已选 Mac；`0x97` 两位置为 Factory Auto/Manual；16 次 `0x87` 全部成功，含单键动作和旧宏。未修改本地 Studio 草稿。捕获 TX 仅有 00/9F/95/96/97/87，无保存、模式切换或资源写入。
- 部分模式的保存 Voice 动作为单键 `E7`，另外为 `6D`。这里只记录原始保存值；平台预设为 Mac 时可由 Consumer Voice 覆盖，不能把保存值直接等同于实际输出。后续 V01/V03 显式切换不得复用未经验证的旧 Voice 草稿。
- App→Agent 交接后，整份高级配置和能力显示立即清空；Agent 实际连接时设备信息显示实时电量/模式/拨杆，未连接窗口显示未知。浏览 Mode 4 后共享设备 workMode 仍为 2（用户界面 Mode 3），无 0x92 写入。详细日志已关闭。
- 局限：旧固件写入回归、批量中断/超时 HIL、空槽资源 HIL 尚未执行；W01–W04、H01/H02、V01、WS3 和最终发布均未完成。当前可用只读阶段不等于最终版。


## 13. W01 明确模式切换与读回确认

新增主界面明确的「切换键盘到所浏览模式」按钮，与浏览 Mode 标签分离。App 配置链路连接后，先识别已知 WS2/legacy，再读当前模式；已经处于目标模式则不写入，否则等待 0x92 ACK 后重新查询 0x00。只有读回目标一致才返回成功；设备拒绝、超时、错误模式或连接代次变化均失败，界面显示最新可知设备模式，不改键位草稿、不发送 0x04。

WS2 的 0x92 授权仅由确认事务显式传递，普通 raw write 路径不开放。其他 WS2 保存和资源写入继续禁用；未知固件不开放此操作。并发模式切换和快照读取互斥。真实物理拨杆不受软件模式选择控制。

自动测试覆盖 ACK+读回顺序、ACK 后不一致、丢失 ACK、读前/ACK 后交接、相同目标免写及授权不扩大到其他设置。完整自动测试与真机结果在后续 checkpoint 记录，不用模拟结果替代真机确认。


### W01 验证 checkpoint（2026-10-13）

- 功能源码 `5fbd343`；147 项自动测试通过；arm64 Release 与 Developer ID 签名通过。候选位于本机 `local-builds/connect-talk-w01-mode-confirmed-20261013`。
- WS2 CP4D 真机受控往返：16:33:25–26 发送 0x92 mode=3，收到成功 ACK，0x00 读回 workMode=3（界面 Mode 4）；16:34:17 发送 mode=2，成功 ACK 后读回 workMode=2（界面 Mode 3/Codex）。原模式已恢复。未发送 0x04、键位或资源写入；本地草稿未改。
- 第一次恢复期间用户操作过实体模式键，出现额外模式变化；这段不作为受控往返证据。对本已处于目标模式的那次请求，读回一致后跳过写入，未谎称额外 0x92 发送。
- 已返回 Agent 日常连接。详细日志自动关闭。真实拒绝/ACK 丢失/读回不一致/中途交接故障路径仍仅有自动测试证据，旧固件真机模式切换回归待执行。W01 主路径实现并通过新固件真机，不能据此宣布整个写入阶段完成。
- 用户新增反馈：停止系统听写、删字后短按无法再次唤起，长按 Siri 仍有效。作为 Voice 连续使用故障待单独抓取；不混入 W01 通过结果，也不认为之前的单次听写已覆盖连续使用。


## 14. W02 待机设置确认流程

设备信息新增独立的待机编辑器，当前设备值与待应用选项分离。只允许 0/30/60/120 分钟；先读取已知 WS2 固件的真实值，再明确点击应用。预读相同值免写；否则使用 0x95 little-endian set，等待 ACK 后重新 0x95 query，读回一致才确认。该命令自持久化，不追加 0x04。失败保留用户选项、将设备设置标为未确认；断线/交接后旧结果不可提交。

命令授权改为 mode/standby 两种独立类型，不能相互开放，不能扩大到全量保存或其他设置。模式、待机编辑和配置快照读取互斥。未知或 legacy 目录不开放 WS2 待机设置。

154 项自动测试通过：合法编码/非法值、ACK+读回、免写、拒绝/丢失确认、读回不一致、ACK 后交接及授权边界。真机和重启保持验证另记 checkpoint。

连续听写补充：用户在停止、删字后不额外等待也可再次启动。该轮抓取到 12 个完整 Consumer CF 按下/释放，约 0.0887–0.1802 秒，无原始 Command 事件或后测残留。不能据此宣布原始偶发问题已修复，也不要求固定等待 5 秒；临时监测已停止，输入链路未改。


### W02 写后读回真机 checkpoint（2026-10-13）

- 功能源码 `6b96013`；154 项测试、arm64 Release 和 Developer ID 签名通过。候选位于本机 `local-builds/connect-talk-w02-standby-20261013`。
- CP4D 真机原待机值 60；选择 30 时设备值保持 60，未自动写入。19:10:32 明确应用：0x95/1E00 返回 ACK，再 query 读回 30。19:21:26 恢复：0x95/3C00 返回 ACK，再 query 读回 60。没有 0x04，也没有键位/资源/模式写入。
- 原设置已恢复，不把临时 30 留给用户。未收到重启确认，保持性测试不标通过；已告知用户此前重启步骤暂缓，之后单独安排真实重新上电回归。拒绝/超时/读回不一致/中途交接故障路径仅有自动测试证据。
- 收尾时 Mac 锁屏，CUA 无法关闭详细日志和交还 Agent，已请求手动解锁。当前 App 配置链路仍可能占用 BLE，不能宣称 Agent 交接完成；详细日志有既有 15 分钟自动关闭保护。下一次先核对现场再收尾。


### W02 重启后复核与收尾（2026-10-14）

用户确认正常重启键盘并解锁 Mac。App 曾收到断线后自动重连，能力和设备快照已清空；重新明确点击读取待机，经 catalog 探测后读回 60 分钟。此前 2026-10-13 已将临时 30 恢复为原 60，故这次只记录“重启后恢复值仍一致”，不宣称临时 30 或真实完全断电 EEPROM 保持性已验证。

详细日志开关已为关闭；通过设备信息把配置连接交还 Agent，socket 实时读回 switchState=1，界面确认 Agent 已连蓝牙、Codex 模式和手动批准。锁屏造成的收尾待办已完成。后续继续 W03/H01 时保留未知/Custom/Disabled 不自动放行的要求。


## 15. H01 审批绑定验证（2026-10-14）

- Agent 审批查询不再用缓存兜底：实时状态为自动时，读取 0x9F 已知目录、WS2 的 0x97 绑定，再复查状态。仅物理自动位置 0、两个读回位置一致、Factory Auto 且无自定义动作时放行。Custom/Disabled/Factory Manual、未知、超时和断线均保持原生审批。已验证 legacy 通用成功 ACK 路径兼容；错误 ACK 不推断为 legacy。手动位置直接保持手动，不做无用高级查询。
- 审批请求合并同一轮读取；高级读取超时使审批通道失效并重连，防迟到回复被新请求复用。断线清理所有审批等待，状态查询超时绑定代次与轮次。仍须真实故障和旧固件回归，不称此为完全原子跨端配置。
- wire v1：status 的 switchState 保留原始实体事实，仅展示；permission/approval_status 的 switchState 是保守审批结果（0=允许自动，否则 1），physicalSwitchState 单独携带真实位置或 null，并有 approvalAutoVerified/approvalPolicyVersion。这样旧 Kimi SDK 等只读取审批接口 switchState 的调用方也不会把 Custom 位置误放行。旧的外部 Codex SessionStart 若还读取原始 status 不能混用；本候选的 Hooks 已改用审批接口，必须配套安装。
- 四类 Hook 共用验证规则，无新 Agent 证明不放行；Codex SessionStart 改查 approval_status，离线/未验证时写回 on-request，不延续之前的 never。该全局文件改写保留原有类型/语法保护；已有运行会话的重读行为不作保证。
- UI 仅展示自动档/手动档，避免将物理位置标签冒充已批准决定；不增加软件拨档或配置绑定写入。W03 仍未开放，H02 其他退出/CLI 版本回归后续执行。
- 160 项自动测试通过；其中已覆盖 policy 与实际 wire JSON，Agent 状态读取/超时在真实 BLE 上的路径还待 HIL。本批不修改固件或已保存键盘绑定。


### H01 新固件主路径 HIL（2026-10-14）

候选源码 `832eb9c`，160 测试、arm64 Release 和签名检查通过。实体手动时审批接口 physicalSwitchState=1/approvalAutoVerified=false，Claude ask、Cursor/Codex 未放行，Codex on-request、Kimi default_yolo=false。用户切到自动后，原始 status 仍仅提供位置 0（无审批证明）；审批接口完成目录/绑定/位置复查后返回 physical=0、effective=0、verified=true，约 0.247 秒。Claude/Cursor/Codex allow，Codex never，Kimi default_yolo=true（其 Hook 仍按既有协议不输出 stdout）。

上述为受控 {} 输入驱动真实 Hook 二进制和真实 Agent/BLE，不代替实际 CLI 会话全流程，也不保证已运行会话重新读取磁盘策略。Custom/Disabled/未知/错误 wire 均有自动测试，未在真机改绑定；legacy 和注入断连/超时仍待回归。用户已切回实体手动档，实时读回 physical=1/effective=1/verified=false，Codex 恢复 on-request，Kimi default_yolo=false；本批没有固件、键位或绑定写入。W03 仍未开放。


### H01 本地安装与实际 Hook 路径收尾

已备份旧安装包并将源码 `832eb9c` 候选更新至 `/Applications/AhaKey Studio.app`。深层签名验证通过，App 与 LaunchAgent 均从该路径运行，界面重新连接并显示 85% 电量、实体手动档。Codex/Cursor/Claude 的已配置 AhaKey Hook 引用安装目录；直接执行安装目录 Hook 复核 Claude ask、Cursor/Codex 无 allow、Kimi 无 stdout，实时审批接口保持手动，磁盘 Codex on-request/Kimi default_yolo=false。本地包未公证，仍为测试版；上述受控 Hook 调用不等于完整 IDE 会话验收。


## 16. W03 实体拨杆绑定编辑（2026-10-14）

源码 `74c5b27`，蓝牙发送长度保护 `49681eb`。已核对 Fireware-harness 头仍为 `d1b46a14`；缓存 command_solve.c blob 与该头树一致 (`33677648d671a2207c41ce52d97bf3ebfbb069bc`)，并读取 main.h blob `945d3e850a191f14a30e3c3a743dd5392d470be1`。0x97 set 请求为 `AA BB 97 01 [bind_type action_len action]×2 CC DD`，两档动作合计最多 52 字节；Custom 动作为 `73 len HID…` 或 `74 len (action,param)…`。不追加 0x04。固件 save_key_bound_data() 后 ACK 不能证明 EEPROM 断电保持。

- 设备信息增加独立两位置编辑器，当前设备值与待应用草稿分别展示；支持 Factory Auto/Manual、Disabled、Shortcut/Macro；不写 GPIO、不软件切档。只自定义一边时，未明确设置的另一边默认 Disabled；“保留当前位置绑定”提供明确保留。空快捷键、非法长度、超长合计和未释放宏不可应用。
- 保存流程为同代次 catalog → 最新绑定预读 → 基线冲突检查 → set ACK → query 全部读回一致。外部已改绑定、拒绝、读回不一致、断线/迟到结果均不报成功；失败保留草稿。设置互斥，授权仅开放已知 WS2 的合法 0x97 set，不能扩大 mode/standby/0x04 或其他写入。超过当前 BLE 单次发送长度时拒绝。
- 167 项测试通过，arm64 Release、Developer ID 深层签名通过。本地候选/安装源码 `49681eb`，旧包已备份。UI 实测读取原 Factory Auto/Manual，选择 Custom 时实际绑定不变、对侧草稿自动 Disabled、空动作不能应用。选择仅“全部松开”宏后显式应用：set `AA BB 97 01 03 04 74 02 04 00 02 00 CC DD` 收到六字节 ACK，再读回 `AA BB 97 00 01 02 03 04 74 02 04 00 02 00 CC DD`。
- 当前临时绑定为 Custom 全部松开 / Disabled，已交还 Agent，详细日志已关闭。已请求实体自动位置验证 Custom 不自动批准；该检查、恢复 Factory Auto/Manual 和重启保持性尚待完成。不能将 W03 宣称为发布验收完成。测试没有更改键位、显示资源、待机或 Voice 配置。
