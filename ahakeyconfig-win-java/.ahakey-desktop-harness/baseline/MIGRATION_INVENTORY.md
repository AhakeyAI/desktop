# 双版本功能差异与迁移清单

状态：DLA 静态调查；不创建 DIB，不修改生产代码。  
采样日期：2026-09-26；固件补充核验：2026-09-27。  
Owner 调整：以官网线上代码作为接收基础，逐项迁入 eternal 版本已实现的新功能，并与 Firmware 联调；精细 UI、完整动线优化、组件库更换和 Windows/macOS 统一后置为独立专项。

## 两仓身份

接收仓 / 官网基础：
- 路径：`C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java`
- Git 顶层：`C:\Users\20825\Desktop\windows软件代码\desktop`
- remote：`https://github.com/AhakeyAI/desktop.git`
- 分支 / HEAD：`main-anpx` / `0da59ce3a058fc19c8abe1de4fa019bae6d1f2b4`
- 工作区：存在 `AGENTS.md` 修改及 Harness 相关未跟踪文件；本轮未发现生产 `src/`、`pom.xml` 脏变更。
- 构建标记：`pom.xml` artifact `ahakey-studio`，version `1.0.0`，Java/JavaFX 17。
- 主要结构：`app 2`、`service 14`、`view 7`、`protocol 3`，无 `firmware/`、`update/` 包，无 `src/test/java`。

功能来源仓 / eternal：
- 路径：`C:\Users\20825\Desktop\windows软件代码-eternal版本\desktop\ahakeyconfig-win-java`
- Git 顶层：`C:\Users\20825\Desktop\windows软件代码-eternal版本\desktop`
- remote：`https://github.com/AhakeyAI/desktop.git`
- 分支 / HEAD：`eternal-dev` / `9d098348f34f9e6f04f1f94bbaa428ff2332115a`
- 工作区：`git status --short --branch` 干净。
- 构建标记：`pom.xml` artifact `ahakey-studio`，version `1.5.4`，Java/JavaFX 17；新增 ZXing、system-scope Sherpa JAR、JUnit 5。
- 主要结构：`app 6`、`service 29`、`view 13`、`firmware 33`、`update 12`，含 `src/test/java` 和 `src/test/resources/protocol-fixtures/ahakey-protocol-3.2.json`。

共同来源判断：两仓 remote 相同，双方 Git 分支均可看到 `origin/main-anpx` 与 `origin/eternal-dev`，可判断为同一 GitHub 仓库的不同分支/工作副本。不能仅凭目录名判断 eternal 更正确；本报告只把 eternal 代码作为候选实现证据。

关键文件指纹：
- 接收 `pom.xml` SHA256 `7F5AB515443BE99CC7631EE4F4A646E2757D5054F078CE50CFFA2A8DCC4BCC2D`
- 接收 `StudioController.java` SHA256 `52F10314C7C2C5B54C614285A66CEC00C6582AFE82E55F3B374FE0DFB9EE1652`
- 接收 `DeviceSyncService.java` SHA256 `5CE5E29FB794822CE6C2F1C6475DC9339C086AE8FEDDF9145453B20762924EB3`
- 接收 `AhaKeyProtocol.java` SHA256 `977A6B05B257F501C936125ABC49B4F4618111F9378B17F0E5B997C0B8725B57`
- 接收 `BleManager.java` SHA256 `30355FC173DE9A5010B35AFD315466FBB80A30430077C5E22BEC3CC458F06790`
- eternal `pom.xml` SHA256 `461C69F5FF7BA81456D0C53FDBD6F98DFA49A029B42600E8A84985F19252B899`
- eternal `DeviceSyncService.java` SHA256 `BDB06542A6CD656E9D0FD7CD61668234A76AD61BD71905AA3F74FD550D2E138C`
- eternal `AhaKeyProtocol.java` SHA256 `2E67DFB34C9ACC3775A40067E9CDBCCD096AF757E4F1CD8682A79F7F2C04241A`
- eternal `BleManager.java` SHA256 `1097D2BFF458BA465B5B98BEFEC8F810B9207C1244AA7814E95BF2CF8EE3682E`
- eternal `StandbySettingsPane.java` SHA256 `294F59BCDD7582FF15BF6094E095D3367681577E04612BD9E6740914C932FFA0`
- eternal `FirmwareCapabilities.java` SHA256 `D0F6444AD3A00FDE205D52BC4EA2FA77A83142E022A84963A679369A103C6CB3`

## 固件核验状态

2026-09-26 首轮双仓调查时，`.ahakey-desktop-harness/local.json` 不存在，固件路径未绑定。  
2026-09-27 Owner 明确目标固件路径为 `C:\Users\20825\Desktop\vibe-code`；已通过 Windows Harness 脚本绑定为只读参考路径，`desktop.py status` 显示 `Firmware read-only root: C:\Users\20825\Desktop\vibe-code`，`active_change: NONE`，产品基线未自动批准。

固件工作区身份：
- 路径：`C:\Users\20825\Desktop\vibe-code`
- Git 顶层：`C:\Users\20825\Desktop\vibe-code`
- 分支 / HEAD：`harness/x1-refactor-main` / `e3df33c393db2a9cf5d1a2d7b7c3843125b6864c`
- 工作区：存在固件侧未提交变化，包含 `.ahakey-harness/project-state.yaml`、`X1-INPUT-CONTROL` 状态/执行记录、`APP/hardware/psk_multi_button.c`、CP1 evidence 和 `tests/host/input_control/`；这些不是 Windows 本轮修改，不可用 HEAD 单独代表实际固件工作区。

固件 Harness 入口与当前状态：
- 入口：`.ahakey-harness/project-state.yaml`
- Harness：固件侧 AGENTS 标记为 `AhaKey Firmware Harness v0.6-alpha4`
- 当前活跃工作流：`WS2 / X1-INPUT-CONTROL / Input & Control`
- 当前阶段：`STATE.yaml` 显示 Stage D、`candidate_prep_contract_sync_required`，活跃 checkpoint 为 `CP1`
- `project-state.yaml` 显示下一角色/模式为 `AIB / WS2_STAGE_D_BUILD_CP1_RESUME_AFTER_EXECUTION_REFINEMENT`
- `STATE.yaml` 的 next actor 为 `AIA / CANDIDATE_RECONCILE / CP1`，说明固件侧记录存在“恢复构建”和“候选同步”表述差异；本报告按状态文件和 evidence 共同判断：CP1 尚未形成 Windows 可宣称联调通过的固件候选。
- 固件 PRD 状态：`prd_status: owner_approved`
- 架构状态：`architecture_status: accepted`
- CP1 设计审查 evidence：`X1-INPUT-CONTROL-20260927-stage-c-design-review-pass.md` 为 PASS，但范围明确禁止 WS2 Desktop 写协议扩展、禁止新增 command、禁止启动 CP2-CP5。

直接继承的用户旅程/决策引用：
- `workstreams/X1-INPUT-CONTROL/PRD.md`：Firmware 作为当前 Input & Control 配置权威；Desktop 启动/重连前读取键盘配置；Save/Apply 写入后立即回读并以键盘数据刷新 UI；失败或回读不一致时保留失败草稿供重试/编辑/丢弃，基本键盘输入继续工作，高级编辑 fail closed。
- `PRD.md`：未知 firmware key 对高级写入 fail closed；已知 release catalog 只启用被 capability metadata 支持的功能。
- `PRD.md` 与 `ARCHITECTURE.md`：4 个模式、每模式 4 个普通键；Mode4 可见、可编辑但默认空/N/A；现有 KEY1-K4 默认表是 source of truth。
- `PRD.md`：Voice 在线 Desktop-present 短按由固件发出 F18，Windows Desktop 拥有在线动作；离线 quick-start 需要单独平台确认。
- `PRD.md`：Restore factory 必须确认、写入、回读，所有目标设置读回默认才算成功。

协议和实现核验摘要：
- `contracts/x1/protocol-commands.yaml` 把 `0x04` 标为 save_config、`0x73` 标为 set_key_binding_and_name、`0x95` 标为 standby_timeout_official_compat、`0x9D` 标为 persistent_config_chunk_read、`0x9F` 标为 version_model_capability_query。
- `docs/investigation/05_X1_COMMUNICATION_PROTOCOL.md` 记录 `0x04` 保存、`0x73` 写普通键绑定/名称、`0x95` 待机查询/设置、`0x9D` 配置分块读取、`0x9F` 版本/能力查询。
- 当前 `APP/sub_main/command_solve.c` 中，`0x04` 调用 `save_key_bound_data()`，`0x73` 更新 `key_bund.user_key_bind/user_key_desc` 并置 `running_data.have_update_custom_data=1`；这两个分支未看到显式 `command_return(...)`，因此不能把 eternal 的“逐条等待同命令 ACK”直接用于所有保存命令。
- 当前 `command_solve.c` 对 `0x84`、`0x85`、`0x92`、`0x95`、`0x98`、`0x99`、`0x9A` 等存在明确返回；`command_return()` 格式为 `AA BB <id> <code> CC DD`，经 USB EP2 或 BLE notify 返回。
- `APP/sub_main/fram_RC16.c` 中 `save_key_bound_data()` 执行 `EEPROM_ERASE(KEY_BUND_EEPROM_ADDR, sizeof(key_bund))` 后 `EEPROM_WRITE(KEY_BUND_EEPROM_ADDR, &key_bund, sizeof(key_bund))`；未返回写入结果给调用方。
- 当前 `APP/sub_main` 搜索未找到 `0x9D` / `0x9F` 的实现分支，只看到 command range policy 和文档/contract 记录。因此 0x9D/0x9F 在“目标固件源码已实现”层面仍待确认；不能把 eternal 常量、fixture 或固件文档草案视为当前真机协议通过。

结论：固件资料支持 M1 的产品语义方向，但不支持“直接整段迁入 eternal 事务/ACK 保存实现”。首项迁移应缩窄为保存结果语义、失败反馈、草稿保护、能力/读回证据门禁；每条命令的 ACK/读回策略必须按目标固件实际支持分层处理。

## 差异总览

来源仓新增能力：
- 固件能力门禁与协议 3.2：`CMD_QUERY_CAPABILITIES 0x9F`、capability mask `0x7FF`、`firmware-capabilities.properties`。
- 自动待机时间：独立卡片 `StandbySettingsPane`，通过 capability 检查、读取、写入、save、回读校验。
- 更安全的设备事务：`BleManager.DeviceTransaction`、`executeDeviceTransaction`、逐条 `sendCommandExpecting`、响应 token/最小 payload 过滤。
- 固件更新/恢复初始化：`firmware/` 包、WCHISP runtime、HEX 校验、烧录状态机、诊断和后置 0x9F 验证；UI 在 `DeviceMaintenancePane`。
- 应用更新：`update/` 包、stable manifest、下载与 Windows 安装器入口。
- AhaType 云账号：`AhaTypeService`、`AhaTypeConfig`、`CloudAccountManager`、`CloudAccountDialog`、菜单入口。
- 物理 F18 短按/长按路由：`platform/voice/*`、`VoiceKeyPressState`、固件版本门禁 `minimumRawF18DesktopVersion=1.4.8`。
- Hook 审批与拨杆新鲜度：`ApprovalService`、`ApprovalSnapshot`、`PhysicalStatusFreshness`，Hook dispatch fail-closed。
- OLED/GIF 增强：默认 GIF 资源、GIF layout 查询、导入限制、分区布局。
- 支持页/蓝牙配对指引/Russian UI/多语言资源和相应测试。

已有能力增强或行为改变：
- 配置保存：接收仓 `DeviceSyncService.writeSequentially()` 逐条 `sendCommand()` 后 sleep；eternal 改为设备事务内逐条 `sendCommandExpecting(frame, frame[2])`，并可选回读语音键配置。
- 协议：接收仓到 `0x92` 和 OLED 写入为主；eternal 新增 `0x95/0x96/0x97/0x98/0x99/0x9A/0x9B/0x9C/0x9D/0x9F`，并把 `0x86` 标为历史冲突。
- 连接/状态：eternal 增加 USB/BLE 会话 token、物理状态恢复、断链后 fallback 与响应隔离。
- TopBar 设备信息弹窗：接收仓已有 More/设备信息；eternal 在同一入口塞入待机、固件维护、蓝牙配对、支持卡片。

仅 UI/样式或低优先级差异：
- Russian UI 和 `legacy_ru.properties`：有国际化价值，但当前任务不是多语言专项。
- 支持 QR、蓝牙配对说明、About 检查更新：可后置，除非 Owner 明确当前商业优先级。
- 屏幕动画入口和若干菜单项文本调整：需避免与“暂缓精细 UI”冲突。

可能修复/删除/待证实差异：
- eternal 的 `commandsForModes()` 默认跳过 `KEY1`，注释称 K1 是 Desktop action；接收仓同步 `KEY1-K4`。这是行为改变，不可直接迁，必须先确认商品机 K1/F17/F18 语义和固件映射。
- eternal 的普通配置保存等待 ACK，看似修复“假成功”，但如果旧固件不会给完整 ACK，可能导致官网版稳定路径被破坏；必须做兼容门禁或降级策略。
- eternal 的固件更新体系测试多、边界多，但涉及 WCHISP、UAC、HEX、发布 manifest 和真机重连，不能作为第一迁移项。

## 候选迁移清单

### M1 配置保存可靠性：保存语义、失败反馈与回读门禁

用户作用：保存键盘配置时，桌面不应在设备未接受、未应用或未持久化时误报成功；失败要提示清楚，并保留可重试/编辑/丢弃的草稿。

官网版现状：`DeviceSyncService.writeSequentially()` 对每条命令调用 `ble.sendCommand()` 后 sleep 50ms，最后 sleep 250ms 后回调完成；现有 `BleManager` 已有 `sendCommandExpecting()` 和 `waitForResponse()`，但普通配置保存没有使用。`StudioController.handleSave()` 的成功提示更接近“命令已发出/本地已存”，不等于设备已应用或持久化。

eternal 证据：`DeviceSyncService.writeSequentially()` 在同一 `ble.executeDeviceTransaction()` 中逐条 `ble.sendCommandExpecting(frame, frame[2])`；`BleManager` 新增 `DeviceTransaction`、transaction lock、响应 token、最小 payload 过滤；`DeviceSyncService` 可选语音键回读。关键引用：`DeviceSyncService.java:150-188`、`BleManager.java:120`、`BleManager.java:420`、`BleManager.java:950`、`BleManager.java:1339`。

固件依赖与核验程度：Firmware Harness 已批准产品语义方向：Desktop 启动/重连读键盘配置，Save/Apply 写入后立即回读，回读一致才刷新 UI；失败或不一致保留失败草稿。当前目标源码显示 `0x04` 保存调用 `save_key_bound_data()`，`0x73` 更新 `key_bund` 并置 dirty；两者未见显式 `command_return(...)`。`save_key_bound_data()` 擦写 `KEY_BUND_EEPROM_ADDR` 后写入 `key_bund`，但不把写入结果返回命令层。`0x84/0x85/0x92/0x95/0x98/0x99/0x9A` 等有明确 ACK。`0x9D/0x9F` 当前在 contracts/docs 中存在，但 `APP/sub_main` 未找到实现分支，需 Firmware CP3/WS4 或等价 evidence 锁定。

迁入边界、关键依赖和风险：首项不应直接整搬 eternal 的“所有命令同 id ACK”事务策略，而应拆为 M1a：保存结果语义、失败反馈、失败草稿保留、按命令能力选择 ACK/回读/UNKNOWN。接收仓已有 `sendCommandExpecting()` 可局部复用，但不能把 `0x04/0x73` 强制等待 ACK 当作默认路径。需要保留旧固件/未知固件下的基本输入和现有本地保存体验；高级设备写入必须在能力/读回证据不足时 fail closed 或显示“无法确认已应用”。

现有入口是否足够：足够，仍使用 TopBar 的编辑/保存按钮，不需要新增 UI。

最小验收结果与保护旧行为：无设备时本地草稿仍可保存；连接设备保存时不能把“已发送”显示为“设备已保存”；固件返回明确失败或回读不一致时保留失败草稿并允许重试/编辑/丢弃；旧固件或当前目标固件缺少 0x9D/0x9F 实现证据时，不发送未经门禁的新写命令，不静默宣称持久化成功。必须保护 `KEY1-K4` 当前配置路径，不能顺手采用 eternal 跳过 K1 的行为。

### M2 自动待机时间设置

用户作用：用户可设置设备无操作后的自动待机时间，包含“保存并回读确认”的反馈。

官网版现状：未发现 `StandbySettingsPane`、`CMD_STANDBY_TIMEOUT` 或待机设置入口。

eternal 证据：`StandbySettingsPane` 从 TopBar 设备信息弹窗进入，连接后先 `queryDeviceCapabilities()`，要求 protocol major >= 2 且支持 `CAP_STANDBY_TIMEOUT_V2`；读取 `readStandbyTimeoutMinutes()`，保存时 `setSaveAndVerifyStandbyTimeoutMinutes()`。关键引用：`TopBar.java:801`、`StandbySettingsPane.java:135-145`、`StandbySettingsPane.java:180-200`、`AhaKeyProtocol.java:26`、`AhaKeyProtocol.java:166-184`、`BleManager.java:547`、`BleManager.java:602`。

固件依赖与核验程度：`0x95` 在目标固件 `command_solve.c` 有实现并返回，`docs/investigation/03_X1_FEATURE_INVENTORY.md` 记录支持 0/5/10/15/30；但 capability gate `0x9F` 在当前 `APP/sub_main` 未找到实现分支，仅有 contracts/docs 记录。因此待机本身比 M3 更接近可联调，但正式 UI 写入仍需能力门禁或固件版本白名单，不能依赖 eternal 的 properties。

迁入边界、关键依赖和风险：适合作为首个“新功能”而非 UI 重设计；但必须先引入最小 capability 查询/解析，不能把整个 firmware/update 体系带进来。风险是旧固件不支持时误发写命令；操作层也要 fail closed。

现有入口是否足够：现有 More / 设备信息弹窗足够，可加一个小卡片作为最小联调入口；不需要重做导航。

最小验收结果与保护旧行为：未连接显示请连接；未知/不支持固件不发写命令；支持固件读取当前值，保存后执行 set -> saveConfig -> readback，UI 只在回读一致后显示已保存。保护现有设备信息/Hook/BLE driver 入口不被挤压。

### M3 固件能力门禁与 0x9F 解析

用户作用：让桌面知道设备是否支持新功能，避免对未知设备发送危险或无效命令。

官网版现状：`AhaKeyProtocol` 未定义 `CMD_QUERY_CAPABILITIES 0x9F`；`AhaKeyResponseParser` 未形成 capability contract；`PRODUCT_BASELINE.md` 已标旧 `0x9F` 结论 stale/unknown。

eternal 证据：`AhaKeyProtocol` 定义 `CMD_QUERY_CAPABILITIES`、cap bits、required mask；`FirmwareCapabilities` 读取 `firmware-capabilities.properties`：minimum stabilized `1.4.7`、raw F18 `1.4.8`、protocol `3.2`、mask `0x7FF`、model `AhaKey-X1`。测试 fixture `ahakey-protocol-3.2.json` 也声明 protocol 3.2 / firmware 1.4.7 / mask 0x7FF。

固件依赖与核验程度：这是跨端协议基础。Firmware contracts/docs 已列 `0x9F version_model_capability_query`，WS2 PRD 已批准 unknown firmware key fail closed；但当前目标 `APP/sub_main` 未找到 `0x9F` 实现分支。M3 目前是产品/协议方向已批准、源码实现待确认，不能宣称真机可用。

迁入边界、关键依赖和风险：作为 M2/M4/M5 的前置能力迁入最小解析和 unknown/supported/unsupported 状态，不迁完整固件更新。风险是把 eternal 的 `firmware-capabilities.properties` 当正式协议，需改为引用固件证据后再进入实现。

现有入口是否足够：不需要用户入口；作为后台能力门禁和错误反馈。

最小验收结果与保护旧行为：旧设备无 0x9F 时返回 UNKNOWN，不误称 unsupported；依赖新能力的写命令禁止发送；旧已支持功能继续可用。

### M4 物理 F18 短按/长按语音路由

用户作用：物理语音键由 Desktop 区分短按/长按，可路由到 AhaKey 本地语音、Windows 语音或自定义快捷键。

官网版现状：已有 `VoiceInputManager`、`SpeechService`、`WindowsVoiceRelayService`、`KeyboardInjector`；物理键真实路由仍未实测。

eternal 证据：`platform/voice/VoiceAction*`、`VoiceButtonStateMachine`、`VoiceKeyPressState`；`StudioController` 读取 0x9F 固件版本作为 raw F18 gate；messages 中声明需固件 `1.4.8` 或更高。

固件依赖与核验程度：依赖固件是否发送 raw F18 down/up 事件；待固件确认和真机验证。

迁入边界、关键依赖和风险：不要先改 K1/K2-K4 配置保存语义；建议等 M3 可靠后再做。入口大体已有，重点是失败反馈和保留 Windows Win+H 路径。

现有入口是否足够：现有语音启动/配置入口基本够，可能需最小状态提示。

最小验收结果与保护旧行为：固件未知时不启用 raw F18；用户仍可用现有系统语音/本地语音路径；短按/长按释放异常时不残留按键。

### M5 OLED/GIF 分区与默认动画增强

用户作用：更稳定地上传/预览 OLED GIF/图片，支持默认状态动画库和设备布局查询。

官网版现状：已有 `OledUploadService`、`OLEDFrameEncoder` 和基础 OLED/GIF 能力。

eternal 证据：`default-gifs/`、`BundledGifLibrary`、`GifUploadRules`、`GifSelectionHistory`、`ScreenAnimationDialog`、`CMD_GIF_LAYOUT 0x9C`、分区容量常量。

固件依赖与核验程度：依赖 GIF layout command、设备 Flash 布局、能力位 `CAP_GIF_LAYOUT_V1`；待固件确认。

迁入边界、关键依赖和风险：可拆成“本地预检/导入限制”与“设备 layout 查询/上传协议”两段。后者需要 M3。

现有入口是否足够：Inspector 的 OLED 入口已有，若只加预检足够；完整动画库可能需后续 UI 专项。

最小验收结果与保护旧行为：旧 GIF 上传路径不退化；不支持 layout 时使用既有上限或禁止危险上传；失败原因具体可理解。

### M6 Hook 审批与拨杆状态新鲜度

用户作用：Claude/Cursor/Codex/Kimi 等 Hook 操作根据实体拨杆或人工确认做允许/拒绝，断连/过期时 fail closed。

官网版现状：已有 `HookInstaller`、`HookDispatchServer`、`KimiAhaKeyBridge`、审批弹窗雏形。

eternal 证据：新增 `ApprovalService`、`ApprovalSnapshot`、`PhysicalStatusFreshness`；Hook 输出带 `approvalSource`；多平台回调 fail closed。

固件依赖与核验程度：依赖物理拨杆状态是否可及时读取及 freshness 语义；待固件/真机确认。

迁入边界、关键依赖和风险：涉及安全语义，不能只迁 UI 或脚本输出；需要明确过期、断连、手动确认的产品承诺。

现有入口是否足够：现有 Hook/设备信息入口够。

最小验收结果与保护旧行为：断连默认拒绝；同一时间只允许一个人工确认；不会修改用户 Hook 配置除非 Owner 明确授权。

### M7 固件更新与恢复初始化

用户作用：用户可选择内置/远程/本地 HEX，执行 CH582 WCHISP 更新，支持诊断、取消和后置验证；另有 USB-only 恢复初始化。

官网版现状：未发现 Java 侧 `firmware/` 或 `update/` 包；旧 baseline 已标固件更新非当前主旅程。

eternal 证据：`FirmwareUpdateService`、`WindowsWchIspFlasher`、`WchIspRuntime*`、`DeviceMaintenancePane`、大量 JUnit；`DeviceMaintenancePane` 通过设备信息弹窗进入。

固件依赖与核验程度：强依赖 WCHISP runtime、HEX provenance、UAC、ISP 设备枚举、烧录后重连和 0x9F 验证；待固件/发布链路确认。

迁入边界、关键依赖和风险：高风险，暂缓。可先迁“只读版本显示/能力提示”或“诊断前置检查”，不迁烧录执行。

现有入口是否足够：More / 设备信息弹窗可承载，但 UI 文案和安全门槛必须单独 Contract。

最小验收结果与保护旧行为：不自动运行烧录；不自动下载/执行安装器；取消和失败可恢复；没有正式 HEX/固件门禁时不进入实现。

### M8 AhaType 云账号与付费

用户作用：登录 AhaType 云账号，处理文本、查看额度、充值。

官网版现状：已有语音和 Kimi/AhaKey bridge；未见完整云账号对话框和 ZXing 依赖。

eternal 证据：`AhaTypeService`、`AhaTypeConfig`、`CloudAccountManager`、`CloudAccountDialog`，`pom.xml` 新增 ZXing。

固件依赖与核验程度：主要依赖云 API，不依赖 Firmware；但涉及账号、支付和网络配置，不适合本轮从代码静态认定可发布。

迁入边界、关键依赖和风险：需要 API、隐私、错误反馈、支付合规和离线降级确认。暂缓。

现有入口是否足够：TopBar More 菜单已有云账号占位/刷新 AhaType，可承接。

最小验收结果与保护旧行为：未登录不影响本地语音；登录失败不丢失本地草稿；支付状态不阻塞配置保存。

### M9 应用更新与发布清单

用户作用：检测 ahakey.com 稳定版并下载 Windows 安装器。

官网版现状：无完整 update 包。

eternal 证据：`AppUpdateCoordinator`、`StableReleaseClient`、`WindowsUpdateInstaller`、release manifest 测试。

固件依赖与核验程度：非固件直接依赖；依赖发布服务器、签名/发布者策略和安装器。

迁入边界、关键依赖和风险：涉及网络和安装器执行，暂缓到发布专项。

现有入口是否足够：About / version dialog 可承载。

最小验收结果与保护旧行为：不静默安装；校验发布者和 HTTPS；用户可取消。

## Firmware 当前需求到 Windows 迁移映射

| Firmware Checkpoint / 用户目标 | 固件实现与验证程度 | Windows 需要提供 | 官网版基础 | eternal 可复用实现 | 迁移前证据缺口 | 最小联调验收 |
| --- | --- | --- | --- | --- | --- | --- |
| WS2 CP1 Power 与普通键边界；保护现有默认键表和 Mode4 | Stage C review PASS，但当前状态为 candidate prep / contract sync required；禁止 Desktop 写协议扩展 | Windows 不应迁入会改变 KEY1-K4、Mode4 或 Power 语义的保存行为 | 已有 KEY1-K4 配置保存与现有 UI | 不直接迁 eternal 跳过 K1 的行为 | 固件 CP1 accepted candidate / build / regression evidence | Windows 保存路径不改变 KEY1-K4 默认语义，不把 CP1 当 Windows 联调通过 |
| WS2 PRD 已批准 Desktop Configuration Model | 产品语义已批准；源码读回能力未完全落地 | Save/Apply 的成功/失败/草稿语义必须诚实，写后读回一致才刷新 | 已有保存按钮、本地文件、BLE/USB 发送 | `sendCommandExpecting`、事务概念、部分错误反馈 | `0x73/0x04` 无 ACK；`0x9D/0x9F` 源码实现待确认 | 明确区分已发送、已应用、已持久化；失败保留草稿 |
| WS2 CP3 Desktop readback / firmware key / capability gating | CP3 locked，需 AIA refine 和 WS4 Host Protocol；未开始实现 | 能力门禁、UNKNOWN/fail closed、release catalog 引用 | 设备信息弹窗与协议解析基础 | `FirmwareCapabilities`、0x9F parser、fixture | 目标固件 `0x9F` 实现证据、catalog authority | 未知固件不发高级写命令；支持固件只启用支持项 |
| 待机设置 0x95 | 源码有 `0x95` 分支和 ACK；文档记录 0/5/10/15/30；capability gate 未落地 | 最小设置入口、读/写/保存/回读反馈 | 无待机 UI；已有 More/设备信息入口 | `StandbySettingsPane`、`setSaveAndVerifyStandbyTimeoutMinutes` | 是否允许无 0x9F 时按版本白名单联调；0x95 真机验证 | 支持固件读当前值、保存后回读一致；未知固件不写 |

## 建议迁移顺序

1. M1a 配置保存可靠性：先做保存语义、失败反馈、失败草稿和读回门禁，不整搬 eternal 事务层；它最贴近“连接设备并保存配置”，且保护已有主旅程。
2. M3 固件能力门禁与 0x9F 解析：作为 M2/M4/M5/M7 的共用前置，但当前只能准备 UNKNOWN/fail closed 方向，需等 Firmware CP3/WS4 或等价源码证据。
3. M2 自动待机时间设置：功能边界小，`0x95` 在目标源码中比 `0x9F` 更明确；适合作为首个“新增功能”，但应排在能力/版本门禁策略之后。
4. M4 物理 F18 短按/长按语音路由。
5. M5 OLED/GIF 增强，先本地预检，后设备 layout。
6. M6 Hook 审批新鲜度。
7. M7 固件更新/恢复初始化。
8. M8 AhaType 云账号。
9. M9 应用更新。

前三项深入判断：
- M1a 先做，因为它保护已有主旅程，不需要新入口；必须避免把 `0x73/0x04` 当作有 ACK 的命令，否则会把官网稳定路径变成保存超时。它的 Contract 应写成“成功语义与失败保护”，不是“整套事务层替换”。
- M3 必须尽早准备，因为 Firmware PRD 已批准 unknown firmware key fail closed；但当前 `0x9F` 只有 contracts/docs 和 eternal 证据，目标源码未见实现分支，所以它适合先形成门禁 Contract，不适合宣称可真机通过。
- M2 适合紧随 M3，因为 `0x95` 源码实现和 eternal UI 链路都较清楚；仍应暂缓大 UI，只在 More / 设备信息弹窗放最小联调入口，并以“不支持不写入”为硬规则。

## 本轮不进入的事项

- 不整分支合并、不整文件替换、不迁完整 `firmware/`、`update/` 或 `TopBar`。
- 不运行任一仓构建、应用、安装、设备、烧录、测试脚本。
- 不修改 Java/FXML/CSS/构建配置、系统环境或驱动。
- 不批准产品基线，不创建或激活 DIB。
- 不把静态代码存在写成真机通过。

## 下一步唯一 Owner 决策

请 Owner 决定第一项 Contract 方向：是否批准以 M1a「保存语义、失败反馈、失败草稿与读回门禁」作为首个迁移增量，而不是直接迁入 eternal 的全量事务/ACK 保存实现。
