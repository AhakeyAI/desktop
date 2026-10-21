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
- 临时 Custom 全部松开 / Disabled 已完成实体自动位置不放行检查，并已恢复 Factory Auto/Manual、ACK 后读回一致。重启保持性仍待验证。不能将 W03 宣称为发布验收完成。测试没有更改键位、显示资源、待机或 Voice 配置。


### W03 自定义绑定实体自动位置验证

用户切到物理自动位置后，安装目录候选 Agent 审批接口返回 physicalSwitchState=0、effective switchState=1、approvalAutoVerified=false/version1。实际安装 Hook 二进制受控调用：Claude ask、Cursor/Codex 不 allow；Codex on-request、Kimi default_yolo=false。界面仍正确展示实体自动档。用户已切回手动，实时确认 physical=1/effective=1/verified=false。恢复 set `AA BB 97 01 00 00 01 00 CC DD` 收到 ACK，随后 query `AA BB 97 00 01 02 00 00 01 00 CC DD` 与原 Factory Auto/Manual 一致。详细日志已关闭、连接交还 Agent；不能将受控 Hook 调用等同于完整 IDE 会话验收。

收尾复核：Agent 已连蓝牙，界面显示实体手动档、电量 84%；实时审批 physical=1/effective=1/verified=false，安装目录 Codex Hook 不放行，磁盘策略 on-request，Kimi default_yolo=false。临时绑定已撤销。尚未执行断电保持性、长动作边界及真实蓝牙故障注入，不作为最终发布通过。

## 17. W04 普通键差量保存（2026-10-14）

源码及安装候选 `86b12a4`。入口在设备信息的“普通键 · 差量保存”，不导入旧 Studio 草稿、不开放旧全量保存或独立长按。模式与 Key 选择仅决定目标，不改变设备模式。预读真实动作/描述并检查基线，只发变化的 0x73 子命令，然后 0x04、0x87 全字段读回一致才确认；相同值不写不保存。

- 描述变更严格 ASCII、最多 20 字节，按固件读回规则去尾空格；未编辑描述保留原字节。动作按 64 字节读回容量检查（11 + payload + desc），宏必须释放按键；无法完整表示的组合/宏保留原数据，需要显式重新创建，超长/未知读回只读。
- ordinaryKey 独立授权仅开放已知 WS2 的合法 0x73（73/74/75）及 0x04，不开放显示/灯光/模式。事务互斥、连接代次、基线冲突和 BLE 发送长度保护。
- 当前 CP4D 的 0x73 替换单个 user_key_bind，不需要旧客户端双层清除。0x04 持久化固件配置整体，不是原子事务；部分失败可能已改变 RAM，不自动回滚、不继续保存，ACK 不证明 EEPROM。预读后仍可能发生外部并发修改。
- Voice 改动作先读 0x96，仅状态 3/4 可进入普通绑定写入；0/1/2/未知拒绝，不隐式 suppress。仅改描述无需接管。V01/V03 的显式语音移交仍未完成。
- 175 项测试通过，覆盖编码、容量、差量/无改动、冲突、Voice 保护、部分失败、保存失败、读回不一致及交接中断。arm64 Release、Developer ID 深层签名通过。候选已安装，旧包已备份；未公证，仍为测试版。

### W04 CP4D 真机验证与恢复

Mode3/Key4 原 action73/payload2A/description Backspace。仅改描述 CT-W04：只发描述及 04，读回动作仍 2A。再改宏全部松开（74/payload04 00）并恢复描述 Backspace：发动作、描述、04，读回一致。最后仅发 `AA BB 73 73 02 03 2A CC DD` 及 04，87 读回与原基线完全一致。ACK 后独立读回，分片响应正确重组。没有其他键、模式、待机、绑定、Voice 或显示写入；04 仍是全配置持久化，不能断言固件内部仅存该键。

Voice 保护：Mode3/Key1 原 73/E7/Record；尝试本地宏，只发送 catalog/87/96 查询，96=completed_mac2 后拒绝，没有 73/04/suppress。测试草稿已清除。完整只读快照 16 键成功，Voice 仍 E7/Record、待机60、Mac onboarding、Factory Auto/Manual 一致；原保存值不能等同于 Consumer 实际输出。

日志关闭，蓝牙交还 Agent。实时审批 physical1/effective1/verifiedfalse，安装 Codex Hook 无 allow，on-request/Kimi default_yolo=false。最后 UI 检查时 Mac 已锁屏，未获取 Agent 重连界面截图，实时 RPC 证明后台恢复连接。无临时键位遗留。实体 Key4 按下、断电保持、真实故障注入及旧固件回归仍待执行，不宣称最终版验收完成。本地证据和原键备份在候选目录。

## 18. V01 显式语音接管候选（2026-10-14）

源码候选 `d42a140`，185 项测试、arm64 Release、Developer ID 深层签名通过。再次核对 Fireware-harness 头仍为 d1b46a14；实际测试键盘仍是既有 CP4D 构建。没有 Runtime 依赖。

设备信息新增独立语音入口，默认“保留键盘当前方案”，读取 catalog/96/四个87不写入。只有用户选择 App 原生转写或 App 转写+AhaType 并确认后才运行接管。提示明确：覆盖四模式 Voice、关闭固件系统听写、App 必须运行、当前96无法由客户端写回 completed_mac，不能一键恢复 Consumer。AhaType 选择明确说明识别文字会发送云端，要求已有 token 配置，实际账号/额度需真实转写验证。

事务为权限/录音及基线检查、四模式完整预读、准备 App F18 原生转写路由、差量写四个 Voice F18、04保存、读回全部绑定一致、最后96 suppress、再读所有权与四绑定。只准备变化的 Voice，不改描述或其他键。typed voiceHandoff 授权仅允许四个 Key1 的73/F18、04和96/3，未知目录不开放。已是四F18+state3时只准备用户选定 App 路由，不重复硬件写入。失败不自动回滚，可能已改变 App 设置、RAM或持久值；不把 ACK 当切换成功。首次接管原 Voice 数据备份到本地 Application Support/AhaKeyConfig/voice-handoff-backups（权限700目录/600文件），不推送 GitHub，不提供恢复 Consumer 的承诺。

测试覆盖正常顺序、已接管无硬件写入、权限不足、基线冲突、部分键/保存失败、阶段读回不一致、所有权变化、suppress ACK而读回失败、断线/代次及缺失模式；App 草稿测试确认只修改四个 Voice 的路由，其他键、显示和灯光保持。

前次候选路径 /Users/heartline/Documents/Codex/local-builds/connect-talk-v01-voice-20261014/AhaKey Studio.app。初次构建后因 Mac 锁屏未安装；后续解锁、安装和真实接管结果见下方记录。本轮没有发送任何 Voice 写入/suppress，没有改变当前 Consumer 听写或云端开关。后续先安装并只读核对、验证取消切换不写入；因为当前不能一键恢复 Consumer，真正切换需用户明确选择方案后再做实际听写。V01 不标记真机或发布验收完成。

### V01 安装、取消与真实接管（2026-10-14 后续）

用户解锁后候选 d42a140 已安装。更新期间用户看到“应用程序已不能再打开”；工具日志为退出旧进程后继续获取窗口造成 procNotFound/-600。安装包深层签名通过，重新绑定并启动安装路径成功，未发现 AhaKey 崩溃报告。后续更新改为退出后用进程检查确认，不对已退出的旧窗口读取 AX，复制后重新获取 App；bbdb778 后续更新启动正常。提示与旧进程读取操作吻合，但不将其推断为 App 源码崩溃修复。

新入口默认保留当前方案，只读返回 Mac Consumer=2，四个 Voice 保存值为 E7/6D/E7/6D。选择 App 原生方案、打开确认、取消、再次读回均不改变这些值；命令流只有00/9F/96 query/四87，没有73/04/suppress。用户随后明确选择“切换到 App 原生转写并继续真机测试”，才执行接管：本地备份成功、准备 App 路由，仅改 Mode1/3 的 Voice E7→6D，04 ACK、四87一致后96/3，最后96=3且四Voice均73/6D。描述保留原字节，其他按键未写。原始备份与流量只保存在本地，不推 GitHub。当前不再是 Consumer，而是已授权的 App 原生转写，需要 App 持续运行。

当前 Mode4 真机短按开始/再次停止，用户确认正常回填、无 Siri/乱码/Dock异常。日志 F18 Mac keyCode79 down/up，录音与 finalize/paste 成功，bypass=true。长按/松手用户确认正常，至少两轮长按事件均完成录音/回填、bypass=true。Command/F18 在 combined/HID 状态均已释放。AhaType 关闭，未做云端整理真机验收。键盘电源未重启，断电保持性未覆盖。

发现主画布仍将成功 Voice 接管列为未同步：bbdb778 在接管读回成功后确认 Voice 路由字段，其他键/描述/显示草稿不冒充已保存；186 测试与签名候选通过并安装。重启后用户明确实体切到 Codex 并确认短按回填正常，但路由日志仍为 mode0：核对 Agent 文件实际 workMode=2，确认 GUI 只监听自身 BLE core模式，未转发 Agent模式。不能把当时 mode0 路由日志称作 Codex 路由已同步。

新增失败测试在真实状态文件读入点复现无模式通知、非法99被接受；1459976 转发新的在线有效 Agent 模式、GUI 跟随 workModeForDisplay、重连也同步缓存，非法模式不回退0。187 测试通过，含稳定去重和离线缓存门控；候选正在准备最终安装/路由核对。以上不宣称新旧设备、所有模式实体按键、AhaType、故障注入或最终发布验收全部通过。

最终候选 1459976 已安装，签名验证通过、GUI 与 Agent 从安装目录运行；启动正常。保持 Agent 持有 BLE、未额外接管配置连接时，Agent 文件 workMode=2、主画布 Mode3/Codex、voice-relay 日志 hardware mode→2/Codex 三者一致，未同步改动0。模式同步失败测试已由失败变通过；全187测试通过。未重新请求重复录音测试：本次模式修正未改录音/识别/回填处理，之前短按/长按及重启后短按已由用户确认正常；完整四模式按键矩阵仍待覆盖。

当前真实状态：固件 onboarding=3，四Voice为F18，用户选择的 App 原生转写已生效，AhaType关闭，不依赖Runtime，需App持续运行；不是原Consumer状态，不能自动恢复。后台重连完成，实体手动档；Codex on-request、Kimi default_yolo=false，Command/F18均已释放。协议详细日志关闭。接管前原Voice备份在本地目录，仅恢复旧E7绑定不能恢复Consumer，可能产生修饰键事件，禁止将备份当作一键恢复系统听写。AhaType云、键盘断电保持、新旧固件、真实故障注入及WS3/最终发布仍未完成。

## 19. U01 主界面与统一设置面板（2026-10-14）

源码 d8ab4cc。190 测试、arm64 Release、Developer ID 深层签名通过；已备份旧包并安装到 Applications，GUI 进程存活，启动成功。新“更多→键盘设置”面板提供按键/工作模式/待机/实体拨杆/语音方案/显示与灯光六标签。主画布新固件保存入口转到该面板，不再只弹旧全量保存拒绝信息。打开和浏览不保存，不自动导入旧草稿；先读真实键，再明确载入冻结的当前画布单键提案，最后应用。提案校验 ASCII、描述长度、宏释放和64字节读回容量，不截断。各设置复用现有确认事务，工作模式与实体拨杆分离，显示/灯光明确未开放。旧设备关闭面板保留配置连接，继续原画布保存流程。

保存回执只有与当前画布该键的编码完全一致才确认其同步，不清除其他键/描述/显示草稿；失败不产生成功回执。新面板关闭通常交还后台，录入期间关闭与标签操作按事务互斥保护。待机组件从设备信息提取复用，设备信息诊断入口保留。新固件描述提示不再承诺自动过滤Unicode，保存前须明确改为ASCII。

测试覆盖提案范围、非ASCII/超长拒绝、宏不截断、单键精确回执及其他草稿保留。现场启动后观察到用户当前为自动档、AhaType已开启、App持有配置连接；本轮保留这些选择，不宣称仍是前轮手动/AhaType关闭。为测试仅浏览画布到Mode3/Key4，未切实体模式。

UI 测试在点击画布“修改”时工具报 Sky Computer Use native pipe closed before response。重试、JS reset后仍失败，getState全局清单又超时；GUI PID仍存活，无新AhaKey崩溃报告。未对工具故障使用其他GUI自动化绕过。尚未填写测试描述或发送临时键位写入；不能宣称统一面板、主画布提案载入/保存/恢复已经真机通过。已请求用户手动打开六标签面板作进一步核对。后续先恢复电脑使用工具或按人工反馈继续，不将190测试替代UI验收。App/语音和实体档位未主动改变，BLE保留为进入本轮时的App编辑所有权。

### U01 并行安装冲突与 AhaType 修复合并

用户说明16:13左右由另一Codex CLI会话安装0.2.3测试包。核对本轮安装前备份的实际元数据：版本0.2.3，提交59e70f370be69ed46627018786fb63fd8d9b4a71（不是1459976）。该提交在codex/fix-ahatype-expiry-v0.2.3，16:08提交，修复AhaType到期时间含fractional seconds时误报过期。16:45本轮d8ab4cc安装覆盖了该包，且d8尚未包含其修复；因此其他会话的验证结果不能混算为U01结果。并行安装覆盖已证实，CUA native pipe故障原因未确定，不将两者直接归因。

原0.2.3/59e包完整保留在 /Users/heartline/Documents/Codex/local-backups/before-u01-d8ab4cc-20261014/AhaKey Studio.app。当前Applications仍是d8ab4cc；该候选打包未注入APP_VERSION，默认元数据为0.1.0，不能仅凭版本号判断源码。停止继续替换本机安装包，未回滚用户新设置或修改另一会话工作树。

仅cherry-pick59e的两个文件为a086648，保留connect&talk适配内容和hasConfiguredCloudToken。191项测试通过，含future fractional expiry有效、expired expiry拒绝。使用APP_VERSION=0.2.3独立构建、Developer ID深层签名通过，新整合候选在 /Users/heartline/Documents/Codex/local-builds/connect-talk-u01-integrated-20261014/AhaKey Studio.app（source a086648）。未安装、未进行U01 UI/真机完整流程。后续单一候选统一验证；未经用户选择不再覆盖并行会话包。若切换回旧59e包，应成对退出/替换App和Agent，不把打开备份GUI但仍运行新Agent视为旧版回归。原生/Cloud配置保留当前用户选择。


## 20. H02 审批退出收尾（2026-10-16）

停止/卸载 Agent、GUI 接管蓝牙前先持久化全局暂停；单独移除 Claude/Cursor/Codex/Kimi Hooks 则暂停对应客户端。Hook 不再为暂停项生成自动放行，Codex/Kimi 自动策略写入与撤销使用同一文件锁，避免晚到写入覆盖停止结果。恢复 Agent 解除全局暂停，成功重装对应 Hooks 才解除对应暂停；单客户端恢复不能绕过全局暂停。

Codex/Kimi 只有本版本实际改变自动值时才写 value-only lease 旁文件；退出只将有归属记录且仍为自动的顶层值收为 on-request/false。不复制或恢复整份旧配置，不撤回其他用户修改。Kimi 改为词法定位根 default_yolo 布尔，保留注释/换行/字符串/嵌套键；重复、非布尔或词法歧义不写。兼容释放旧 Kimi 的明确 AhaKey inline 标记；历史未标记 Codex never 无法可靠归属，不擅自覆盖。已有无归属自动值维持用户配置，不宣称已恢复安全策略。

Kimi SDK 新请求为 kimi_approval_status；撤销 Kimi 管理时返回无 switchState，让新版补丁走原生逻辑。迁移仅修改 AhaKey loader 函数内的旧请求，保留其他函数请求。旧 Kimi 进程仍可能加载旧 helper；Codex/Kimi 运行会话可能缓存配置，需重开或按各 CLI 支持方式重载。本功能不能撤销已经发出的授权、正在运行的工具，也不承诺强杀/崩溃时执行 GUI 正常停止收尾。

隔离回归：203 项测试通过，新增12项覆盖独立暂停/全局暂停、所有权释放、用户改动保留、Kimi 多行/CRLF/嵌套键/异常拒写、并发晚到自动写、Hook暂停与受限补丁迁移。未执行真实 CLI 安装/移除，未写用户 Codex/Kimi 配置、未切拨杆/Voice。早期测试读取曾创建 approval-control 的空锁文件，后已改为目录不存在时只读不创建；没有写生产暂停标记。本轮开始安装包为0.2.3/source1760a3f，保持原安装，独立候选不自动安装。UI/真实CLI会话、旧固件与WS3最终发布验收仍待完成。

H02 候选源码 d6cffdc；APP_VERSION=0.2.3、arm64 Release 构建和 Developer ID 深层签名验证通过。独立路径 /Users/heartline/Documents/Codex/local-builds/connect-talk-h02-lifecycle-20261016/AhaKey Studio.app，未安装或启动。构建后再次读安装元数据仍为0.2.3/source1760a3f28c6ca2acffe1e8b1df16dfb9d9d8bd84。下一步对这一独立候选进行受控真实CLI生命周期验证，避免与并行安装测试混算。


## 21. 与main 0.2.3整合及检查点PR（2026-10-16）

用户纠正本次PR目标为connect&talk，不是main。独立分支codex/connect-talk-v023-integration通过5f5c070合入main/1b8882a，解决6文件冲突并保留0.2.3功能。详细合并范围、验证边界和下一步完成定义见CONNECT_AND_TALK_PR_CHECKPOINT_2026-10-16.md。未覆盖已安装的1760a3f测试客户端，未操作键盘或生产CLI配置。


## 22. Q01 首批：目录失败不得降级为旧固件（2026-10-16）

基线135215b（PR #138已合入connect&talk），开发分支codex/connect-talk-q01-probe-safety。再次读取远端Fireware-harness，HEAD仍为d1b46a14a796790f2ffe0d228e6c5badcfc34d75；project-state仍要求把WS3 CP1重新应用到WS2 CP4D，CP2/3尚未完成，未发现可启用WS3的新构建。不改固件，也不开放显示资源写入。

Q01静态检查发现App readFirmwareCapabilityProfile把任意6字节0x9F错误回包误判legacy；legacy授权会放开旧配置命令，因而不能将设备拒绝当作旧协议证据。新增共享probeResponse，App/Agent统一分类：仅同连接有效状态+精确AA BB 9F 00 CC DD可回退legacy；错误码、超时、畸形、其他命令ACK、缺状态不回退。保留已知目录和未知目录只读行为。App开始刷新时撤回旧profile；失败在同代连接清空能力/快照，身份变化也清空旧快照，不修改画布草稿；旧事务不能清空新连接状态。

新增3项测试覆盖全部255种非零目录错误状态、旧ACK有无状态、畸形/错命令/额外字节、已知目录无状态拒绝，并检查错误目录不产生旧save写入权限或自动批准。全227项通过，既有迟到状态和请求超时回归继续通过。本轮未注入真实键盘故障、未覆盖U01界面/真实CLI生命周期、未安装或启动候选；当前安装仍为1760a3f。本批只完成Q01目录探测失败路径，不将整个Q01或最终发布标为完成。

固件状态来源：https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/d1b46a14a796790f2ffe0d228e6c5badcfc34d75/.ahakey-harness/project-state.yaml 。后续继续Q01配置事务失败/取消覆盖及U01/H02受控真机验收；WS3须新源码与实际HEX就绪再对接。

## 23. Consumer Voice 确认可行，F5 暂缓（2026-10-16）

用户明确反馈 Consumer Voice 已验证可行，不需要测试 F5，F5 事项暂缓。本轮未提交的 F5 类型、事务授权、路由和入口代码已全部撤回，空分支已清理。没有执行键盘切换或系统设置写入。该结果不扩大为所有 macOS/USB/BLE 组合通过，也不代表此前 App/F18 接管的键盘自动恢复 Consumer。保留当前方案，App 原生/AhaType 仍须用户明确选择后接管。V03 不再作为当前交付必做依赖。

PR #139 已合入 connect&talk，合并提交 f43621d。后续分支 codex/connect-talk-settings-localization 完成统一设置六标签、普通键/拨杆/待机/工作模式/语音方案的中英文文案，包括动态状态、确认/失败提示与共享事务错误。新增128条翻译，保留已有翻译，由生成器统一生成资源。227测试通过；界面布局、实际系统错误提示与真机仍待验收，未覆盖当前安装客户端。

## 24. Q01 第二批：取消、队列与迟到回包（2026-10-19）

继续在 PR #140 的分支 codex/connect-talk-settings-localization 上开发，尚未自动合并该PR。此前双语和F5暂缓决定保留，Consumer方案不变。设置页忙碌时新增“取消当前操作”：停止后续请求并使已经发包的连接失效，用户须重连读回；已发出的修改可能已生效，不声称回滚。

CommandTurnQueue统一串行命令所有权。排队任务取消即移除，但不释放其他任务当前占用；交接瞬间取消会退回尚未使用的ticket；旧ticket/重复释放不影响新请求或新连接。队列重置会结束旧等待者。真实BLE请求与DATA分片接入Task取消处理；已发出的请求取消/超时后撤销能力和快照、结束伴随请求、请求断连，旧ACK不能开启新请求。ACK与取消竞争时还会检查ticket/代次/链路状态，避免回调已到但UI取消先发生时仍显示成功。分片发送会随pending失效停止。

模式/待机/普通键/拨杆/Voice事务在关键步骤独立检查Task取消，不依赖调用者是否在checkSession中检查。取消普通键动作后不继续描述/保存；Voice保存后取消不继续96 suppress，未启动的已取消Voice任务不准备App、不改Consumer。只读/保存的本地草稿保留，取消提示接入中英文资源。

新增13项回归，全240项通过。覆盖FIFO、排队/交接前后取消、失效/重置、旧owner释放、新连接，以及实际Task取消下的模式/待机/键位/拨杆/Voice事务。资源语法检查通过。尚未真实触发CoreBluetooth取消/迟到通知或OLED分片故障，未验证UI布局；这些仍须同源GUI/Agent候选真机验收，不把unit测试等同于HIL。当前安装仍为1760a3f，未替换、未改用户CLI配置或键盘。

固件新进展：Fireware-harness HEAD变为70ca334f65d73b6a2f20a0598e55c6da59f26526；project-state记录CP1接受源f2092f7516b4296cd015733085a8bf2af8b3d62c，下一步为WS3 CP2资源/显示配置BUILD（0x88..0x8E，19项资源设计）。这是已读取的状态记录，不等于当前键盘HEX或CP2实现验收；后续D01应核对具体源码与实际HEX，不能继续沿用“CP1未集成”的旧结论，也不据此开放WS3资源写入。

双路复核中发现并修正一处P2：队列已交接但等待者尚未恢复时发生invalidate/reset，旧ticket可能返回后继续等超时。新增回归在修复前两种分支均失败；acquire恢复及BLE登记前再次验证ticket/断连状态后通过。后续以最终全240项与重新构建结果为准，早期a1d1ed2候选已被后续修复取代。

## 25. WS3当前源码/HEX核对与只读显示入口（2026-10-19）

继续查实际STATE及生产代码后纠正第24节仅依据project-state的“CP2待BUILD”判断：HEAD70ca334已有CP2 0x88–0x8E实现，STATE为ready_for_regate。已下载并校验内存修复HEX，SHA256 ffb9208f79084aa24a832ad2562a14dbbea5df4d114a135cb5b2eb98d4e05539，加载458492字节。归档尚要求候选fresh REGATE，当前键盘未烧录；不宣称最终验收通过。

新增WS3DisplayReadback模型、固定长度0x88解帧/回包匹配、已知WS2目录下严格只读授权。设置页显示与灯光支持显式读取亮度及19项资源元数据；旧CP4D通用成功ACK视为不支持，不误开资源写入。全部读取和代次确认后才发布新快照，任何取消/交接/失败不使用默认值补齐。元数据CRC不等于图像字节验证。读取与旧OLED上传互斥，支持前一批的取消入口。没有添加保存、上传、清空或CP1模式切换。

新增8测试，全248项通过，范围含19项边界、二进制CC DD、容量/帧数字节关系、torn metadata、错项回包及写权限仍关闭。新增中英文文案。本轮仍未安装候选、修改真实键盘/系统听写、操作生产CLI配置；F5保持暂缓。当前安装仍由并行会话管理。

具体字节契约、候选证据与下一步D02/D03/D04见 docs/ahastudio/ws3-display-readback-contract-2026-10-19.md。不要继续把“CP2尚未实现”作为等待理由；可以推进mac接口，实机写入和最终发布仍需锁定固件及联调。当前只读UI、实际旧固件兼容、CoreBluetooth取消仍待真机。

只读接口双路复核无阻塞项；按复核建议，旧OLED上传入口也检查配置忙碌，避免反向并发。全部248测试继续通过。最终候选需以本批最新源码重建，前一批22ddb7b仅含取消、不含新只读显示入口；不要混算两批真机结果。


## 26. 同源候选真机只读与审批生命周期（2026-10-19）

用户确认并行旧包测试结束后安装6094a27，发现英文更多菜单“键盘设置…”漏译；99b0c20补齐一个资源键，重建0.2.3/arm64 Developer ID签名候选并安装成功。最终GUI/Agent同在Applications，后台接管BLE，中文系统语言，画布未同步0。候选与原包、私有配置均已在本机隔离备份；没有推送用户配置或原始宏。

六标签和中英文主要布局可用；待机60分钟、Claude模式、出厂两档绑定、Mode1/Key1 F18/Record、四Voice/onboarding3读回正常。显式载入画布提案不写入。既有CP4D设备的0x88通用ACK被正确提示不支持，没有伪造WS3值或开放写入。GUI编辑/Agent日常所有权交接成功，交接清除旧快照。

实体手动/自动往返和Codex/Cursor Hook进程通过：手动Codex on-request且无allow、Cursor Shell ask；自动never且有归属lease、两者allow。自动时正常停止后台，all.paused持久化、socket关闭，有归属Codex值收回on-request；再启动恢复。原先无归属never保留的路径单独记录，不把它算恢复手动成功。Codex Hook真实UI移除/重装通过：仅暂停Codex，清除其6入口/归属自动值，Cursor仍自动；重装恢复6入口与客户端管理。原配置除目标审批字段外文本一致。直接Hook进程验证不能替代已经运行CLI/IDE缓存重载。

短时30秒11点待机采样：GUI CPU累计+0.32秒，Agent+0.09秒，未见持续高占用；不覆盖长时/灯条/GIF/灵动岛矩阵。电量状态到85%，没有持续0，不代表全电量校准验收。没有改Voice/onboarding、写入显示资源或刷固件；当前仍App/F18，不把此前Consumer可行结论当作本轮Consumer实测。

完整记录：docs/validation/connect-talk-hil-2026-10-19/README.md。剩余：真实在途取消/迟到帧/DATA故障与断电保持、其他三客户端移除重装/运行会话重载、新WS3固件完整快照及D02–D05、长时CPU/电量/灵动岛回归。PR#140目标connect&talk，未以本轮只读与部分生命周期测试宣称最终发布通过。

## 27. 合并#140、D03与新固件刷写后连接排查（2026-10-19）

用户要求CI通过后合入connect&talk再继续。#140最终5b764cb全CI成功，已合并89eecab。新分支codex/connect-talk-ws3-display-controls、草稿PR#141继续D03：同代完整0x88后才窄授权89/8E，10秒临时预览/停止、亮度与单模式状态灯效保存，基线冲突保护、ACK后读回、未知灯效只读、取消后不声称回滚。素材/98仍关闭，不改Consumer/F5决定。契约见docs/ahastudio/ws3-display-controls-contract-2026-10-19.md。

完整回归遇到本机all.paused影响既有Hook测试的7个断言失败，da93952注入临时控制目录并保留生产默认；新增fixture暂停优先测试。D03加10项测试，最终260项全通过。89eecab..1b16fec及后续发现流程变更均已做Standards/Spec独立复核，无阻塞项。

用户明确同意刷memory-fix候选；完成16键等私有备份、旧CP4D恢复HEX与原包保留。换数据线/扩展坞端口后识别CH582，刷入SHA256 ffb9208f79084aa24a832ad2562a14dbbea5df4d114a135cb5b2eb98d4e05539，Verify OK；未主动擦除Data EEPROM或改CFG。用户随后报告重连中、无线失败、USB有连接提示。系统蓝牙附近设备出现AhaKey505C（原515C），还未确认配对/配置连接。刷写成功不等于新固件UAT成功，Voice/原配置是否保留尚未读回。

发现App/Agent扫描只7340，与新固件实际1812/180F广播不符；df6d18b扩扫描及Agent connected lookup，保留设备名和审批验证。0.2.3/arm64源df6d18b已签名安装运行，但连接仍待核实，不能把该补丁称为系统配对根因修复。三条待验证方向为USB/无线状态差异、旧配对/身份变化、固件就绪问题，不以未实现CP1.5直接归因。

最新现场和后续步骤见docs/validation/connect-talk-hil-2026-10-19/WS3_NEW_FIRMWARE.md。当前配置写入暂停；下一步先完成新505C系统配对/蓝牙和完整0x88只读，再做D03临时预览/单项保存/恢复/断电测试。真实取消、D02呈现、D04/D05资源及最终发布仍未完成。

## 28. 505C配对异常与pending连接隔离（2026-10-19）

用户澄清USB OK是屏幕提示，Studio未连接；拔USB正常无线开机后，系统附近设备505C悬停显示断开连接，但尝试连接失败。该组合不等于HID已配对。复查App内存诊断证实df6在12:42及14:34已发现505C，扫描修复通过发现阶段；之前仅凭主界面未连接不能推断仍没发现设备。

只读bluetoothd记录14:55:19–14:58:17同一Studio目标约215次connect及215次encryptionStatusChangedCb status4803/isPairing0，IORegistry无AhaKey HID节点。退出App/Agent后连续120秒新增同类记录均0。原始日志只存本机私有备份；不将4803未经核对就解释成特定协议错误。Apple明确pending connect不会自动超时，故原客户端未设截止的请求可持续触发底层尝试，普通断开回调退避无法约束它。

7a329a8接入App/Agent共享连接attempt guard：15秒deadline显式cancel，一次一请求，取消完成前不重发，迟到connect/旧deadline不得发布状态；新目标超时/早期失败暂停自动重试，由用户恢复，已在本进程建立过BLE连接的目标保留后台重连。该标记不代表HID就绪、不参与审批放行。用户系统配对仍未恢复的根因保持未确定，不宣称已完成HID-first。

复核各发现一个P2并在ed64166修复：App关蓝牙时若正交接Agent须当场释放retained lock；Agent关蓝牙须清旧事实/特征/代次/waiters。新增真实flock+生产powerOff入口回归修前2断言失败、修后通过，合计267测试通过，复核确认无新增阻塞项。新候选尚须15秒取消、错误计数、用户恢复和旧设备重连真机，App当前保持关闭，避免干扰“App/Agent退出时只做一次系统配对”的待反馈对照。

完整证据及下一步见docs/validation/connect-talk-hil-2026-10-19/BLUETOOTH_CONNECTION_DIAGNOSIS.md。必要的后续仅限目标配对清理，不进行整份EEPROM擦除或盲回放键位。D03与资源测试仍等HID和配置链路恢复，草稿PR#141继续目标connect&talk，不自动合并。

### 第28节后续：Forget后恢复及D03首批真机闭环

用户确认App关闭系统仍失败；当前固件Forget组合（第4大键+模式/电源约2秒）清绑定并重配后恢复。IORegistry确认505C的BLE键盘HID节点，ed64166直接配置连接成功。0x88完整亮度/19资源读回通过，原35%、有效自定义资源0/19；临时50%预览由用户确认约10秒恢复，读回保存值35%。明确保存50%、Claude/通知原effect10改effect5并读回；用户正常重启后自动重连，重新查询确认保持。现已恢复35%/effect10并读回，无待恢复设置。

实际0x88在途取消测试通过，快照/能力撤回并禁写，重连后重新读；四Voice/onboarding3/F18保持。交还同源Agent后fresh approval_status确认实体auto及factory binding，手动档对照已请求用户尚待反馈，不能先标通过。最近连接日志短采样无4803；30秒CPU累计GUI+0.26秒/Agent+0.07秒，不替代长时回归。截图与精确边界见docs/validation/connect-talk-hil-2026-10-19/WS3_ACCEPTANCE_CHECKPOINT.md。原始键位和日志仍仅本机私有备份。PR141保持检查点范围，D02/资源与全故障矩阵仍待完成。

第28节手动档对照已完成：用户切手动后新505C fresh physical=1/approvalAutoVerified=false，界面显示手动批准；Cursor Shell ask，Claude PreToolUse无allow及PermissionRequest ask，Codex PermissionRequest无allow、on-request，Kimi配置false。已请求用户切回自动，尚未收到确认；期间不切换连接归属或更改键位，以保持对照。自动Hook往返和全16键比对仍待。


## 29. 新固件自动档与全键位收尾（2026-10-20）

用户回自动时设备起初离线，fresh physical=null自动验证false，未运行allow Hook。唤醒后first fresh仍physical1；亮屏重拨后fresh0/factory verified true，Cursor/Claude/Codex实际安装Hook均放行、Codex never/有归属lease。与昨日手动对照组成完整往返；未把缓存或口头档位当硬件授权。Kimi当前会话及所有CLI缓存刷新仍未覆盖。

完整只读16键、待机、Voice引导、拨杆绑定与刷写前私有备份一致；使用生产DeviceFrameDecoder处理分片和二进制边界，原始数据未提交，仅无载荷汇总JSON。日志已关，最后交还同源Agent，fresh0/verified true、Codex allow/never恢复，诊断面板关闭，无新设置写入。详见docs/validation/connect-talk-hil-2026-10-20/README.md。

另发现基线已有GUI连接缓存刷新缺口：设备离线时isAgentBLEConnected可能仍保留旧值，主界面显示已连接/旧档位；审批fresh查询仍安全回退。此项单列后续客户端修复，不宣称最终发布验收完整。休眠/唤醒首次物理读回1暂不定性固件问题。D02/资源/全故障矩阵仍按WBS推进。


## 30. 连接心跳候选真机验收（2026-10-21）

源码af7645b/0.2.3候选已安装，270测试及双轴复核通过。5秒只读socket心跳修复基线离线UI残留；停止入口同步撤销旧查询发布权。用户正常关机后主界面自动撤回连接和档位，正常无线开机自动恢复，fresh physical1/manual与UI一致；生产停止入口也立即清除，随后重新启动交还日常后台。没有写键位、Voice或显示设置。短采样无持续高CPU，不替代长时/故障全矩阵。证据见docs/validation/connect-talk-hil-2026-10-21/README.md。PR141目标connect&talk，最终文档CI通过后按用户既有授权合并；D02及D04/D05等后续范围继续按WBS，不宣称发布完成。
