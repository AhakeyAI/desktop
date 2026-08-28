# Windows Stabilization Plan

> 唯一权威文件：`desktop/docs/windows-stabilization-plan.md`
>
> `docs/archive/` 下的同名或历史 stabilization 文档仅用于追溯原始需求，
> 不得作为当前实现状态、待办状态或架构事实源。

> 适用范围：`ahakeyconfig-win-java`
> 实现基线：`eternal-dev`
> 文档性质：长期工程事实源（living document）
> 最后更新：2026-08-26

## 1. 用途和维护规则

本文档记录 Windows Java 客户端的权威运行路径、安全不变式、已知问题和验证状态。
维护者和编码 Agent 在修改 Windows 客户端前必须阅读本文档。

长期规则：

1. 每项能力只保留一个权威生产路径。
2. UI 不得在底层操作失败或未确认时报告成功。
3. 硬件审批不确定性必须 fail-safe，不得变成自动允许。
4. 修复用户可见行为优先于大范围重构。
5. 每个变更应小而可审查，并包含相应测试或手工验证记录。
6. 如果架构、审批语义、Hook 格式、固件能力、支持范围或限制发生变化，必须同时更新本文档。
7. 未完成真机验证的项目不得记为“完全验证”。

## 2. 当前权威架构

Windows 生产客户端：

```text
ahakeyconfig-win-java
```

其他 Windows 实现：

```text
ahakeyconfig-win-python  -> 历史/参考实现
ahakeyconfig-win-rust    -> 实验性实现
```

它们不是与 Java 客户端并列的生产事实源。

### 2.1 设备路径

```text
StudioController
    -> BleManager
    -> USB HID / BLE TCP bridge
    -> AhaKeyProtocol
    -> hardware
```

`DeviceStatus` 是 UI 展示模型，不能单独证明审批状态新鲜。

### 2.2 AI 审批路径

```text
Claude / Cursor / Codex / Kimi hook
    -> HookDispatchServer
    -> ApprovalService
    -> BleManager.queryStatusAndWait()
    -> new physical device response
    -> ApprovalSnapshot
    -> automatic allow or manual flow
```

IDE 适配器不得直接使用缓存 `switchState` 决定自动允许。

Kimi 保留两条兼容入口，但共享同一个审批事实源：Kimi Hook 事件走
`HookDispatchServer`（默认 8765）；有线模式下，旧 `approval.py` 协议可走
`KimiAhaKeyBridge`（9000）。9000 在 BLE 模式由 BLE TCP bridge 持有，USB
连接时才由 Java 兼容桥持有。两条入口都调用同一个 `ApprovalService` 实例，
任何非 fresh + connected + AUTO 结果都映射为手动/拒绝。

### 2.3 Hook 安装路径

```text
HookInstaller
    -> generate ~/.ahakey/hooks/ahakey-*.ps1
    -> parse existing IDE config
    -> remove/replace only AhaKey-owned commands
    -> atomic config replacement
```

AhaKey Hook 的稳定身份是命令路径中的：

```text
/.ahakey/hooks/ahakey-<platform>.ps1
```

### 2.4 固件能力

`src/main/resources/firmware-capabilities.properties` 是 Java 能力判断和
PowerShell 发布构建共同读取的版本事实源；`FirmwareCapabilities` 负责 Java 侧加载。

```text
expected bundled firmware:               1.4.7
minimum GIF firmware:                    1.4.3
minimum stabilized firmware:             1.4.7
required protocol:                       3.2 (query command 0x9D)
required device model:                   AhaKey-X1 (model id 1)
required capability mask:                0x7FF (bits 0-10)
```

安装包不从 Git 源码树中读取 `.hex`；发布构建必须通过 `-FirmwareHex`
提供由固件团队产出的真实 CH582 HEX。声明版本必须显式传入；符合
`AhaKey-X1-firmware-<version>-ch582.hex` 命名的文件，其文件名版本必须与声明一致。
正式发布只接受 `AhaKey-X1-firmware-1.4.7-ch582.hex`，并要求同名 provenance JSON
声明匹配的 firmware/model/protocol/capability 合同，以及格式有效的 source commit、
build command 和 UTC build timestamp。软件端只验证固件团队提供的真实字段，不生成
或猜测 provenance。没有真实 HEX、provenance 和签名有效的最终 EXE 时，正式发布必须阻断。

## 3. 审批安全不变式

唯一可自动允许的状态：

```text
state == AUTO
connected == true
fresh == true
```

以下任何情况都不得自动允许：

- 设备断开；
- 上一次缓存值是 AUTO；
- 查询超时或被中断；
- 未知拨杆值；
- Hook 服务器未启动；
- Hook 脚本收到空或非法响应；
- 内部异常。

`ApprovalState` 当前取值：

```text
AUTO / MANUAL / UNKNOWN / DISCONNECTED / STALE
```

## 4. Phase 1 / P0 状态

| ID | 问题 | 当前状态 | 自动验证 | 仍需手工/真机验证 |
|---|---|---|---|---|
| WIN-001 | 缓存 AUTO 可能被当成当前状态 | 代码完成，真机待验证 | `ApprovalServiceTest` + `PhysicalStatusFreshnessTest` + `BleManagerApprovalPathTest` | 拔线、USB/BLE 超时、并发审批 |
| WIN-002 | Cursor 无服务器响应时 fail-open | 部分完成：无响应会 deny；非法文本仍可被正则误判为 allow | `HookInstallerTest` 仅覆盖生成/语法，缺少畸形响应端到端测试 | 关闭 Desktop、端口冲突、畸形响应 |
| WIN-003 | Claude 未强制刷新硬件状态 | 部分完成：服务端强制刷新；Claude/Codex 脚本仍以正则识别 allow | `ApprovalServiceTest` + `HookDispatchServerTest` | Claude/Codex 真实链路及畸形响应 |
| WIN-004 | 延迟的 mode 状态回滚 UI | 部分完成：旧响应隔离已实现；发送失败仍保留乐观 UI 选择 | `WorkModeSynchronizerTest`（当前测试明确保留发送失败后的乐观 UI） | Mode0→1→2、发送失败、断线重连 |
| WIN-005 | Hook 安装/卸载删除第三方配置 | 代码完成，IDE 重启待验证 | `HookInstallerTest` | 各 IDE 当前版本重启验证 |
| WIN-006 | bundled firmware 与 GIF 能力/发布资产冲突 | 未完成：客户端声明 1.4.3，固件工作区已有未提交 1.4.7，发布脚本允许打包运行时无法发现的版本 | `FirmwareCapabilitiesTest` + `ReleaseFirmwareValidationTest` 未覆盖 expected bundled 与传入版本相等 | 统一版本后刷写、回连、版本/GIF 回读 |

### 4.1 Phase 1 实现摘要

- `BleManager.queryStatus()` 与 `queryStatusAndWait()` 共享同一个串行物理请求事务协调器；
  只有物理写入成功后到达的状态帧才能完成当前事务。查询发送前帧、旧轮询帧、
  `DEVICE_INFO_RESP`、`BLE_STATUS_RESP` 和缓存值均不能满足审批。
- 接收时间戳在生产入口捕获：BLE TCP 在 `handlePacket` 收到包时、USB HID 在
  `ReadFile` 成功后且提取/解析帧前记录 `System.nanoTime()`。时间和接收 session
  显式传入 `onBleNotify` 与 `PhysicalStatusFreshness.recordPhysicalStatus`；
  freshness 层不再生成接收时间。
- 物理写入边界在 USB `WriteFile` 或 BLE TCP write+flush 成功返回后建立。写失败、
  写返回前到达的帧、解析被延迟的查询前帧、session 不同或 connected=false 的帧
  均不能完成查询。
- 当前协议没有 request-id。请求超时后，协调器进入 unresolved 状态并 fail closed，
  随后由 `BleManager` 单实例后台恢复器使旧 receiver/session 失效、清空审批/UI
  状态、关闭并重建 USB/BLE 传输。恢复采用 single-flight 和 2 秒退避；用户主动断开
  或应用 shutdown 后不会自动重连。旧 reader/callback 的帧携带旧 receiver/session，
  不能进入新会话。
- 普通轮询与审批使用公平串行事务锁。审批可等待正在执行的轮询结束，但随后必须发送
  自己的物理查询，不能复用轮询结果。
- 断开或新传输会话建立时会失效上一次拨杆状态。
- Claude、Cursor、Codex、Kimi Hook 和 Kimi 9000 兼容桥均经过共享 `ApprovalService`。
- Cursor 只接受服务器显式 `permission=allow`；无响应或非法响应均 deny。
- Kimi PreToolUse 只接受服务器显式的空对象 allow 响应，其他不确定结果 deny。
- `WorkModeSynchronizer` 区分离线 UI 编辑与真实设备模式事务：离线选择只更新
  `StudioState.selectedMode`；只有命令实际发送成功后才更新设备期望值并建立 pending
  确认窗口。发送失败、断开和传输会话切换会立即取消 pending。
- session 恢复会触发 `WorkModeSynchronizer.invalidateSession()`；恢复期间 UI 清除
  拨杆并显示连接恢复/不可用状态。保存成功后的状态刷新和重复连接刷新均在后台线程
  执行，不在 JavaFX `Platform.runLater` 中等待物理响应。
- Java Kimi 9000 兼容桥只在 USB 且没有活动 BLE bridge TCP session 时启动；恢复会先
  发出断开回调释放端口，再允许 BLE bridge 重连。
- Claude 配置路径已修正为 `~/.claude/settings.json`，不再把生成脚本当配置文件覆盖。
- Claude/Cursor/Codex 安装和卸载均只增删 AhaKey-owned command，采用临时文件安全替换配置。
- 重复安装是幂等的，`isInstalled` 会检查脚本和真实配置命令。
- `firmware-capabilities.properties` 集中定义 bundled/GIF 版本。发布脚本要求显式
  `-FirmwareVersion`，拒绝 `<1.4.3`、版本化文件名不一致和正式构建缺少 `-FirmwareHex`。
- `-PrepareOnly` 可在没有 HEX 时准备/检查其他输入，但输出为
  `RELEASE_INPUT_VALIDATION=PREPARED_WITHOUT_FIRMWARE`，不能视为可发布产物。
- 正式 overlay 编译和 allowlist 已纳入审批、freshness、模式同步和 Kimi bridge 类，
  并写入 `firmware-capabilities.properties`。`Test-ReleaseArtifactContents.ps1` 会检查
  最终 JAR 的真实 ZIP 条目；`mvn package` 和 overlay 脚本都执行该门禁。

## 5. 验证状态

### 5.1 自动验证

2026-08-24：

```text
mvn clean test
Tests run: 132, Failures: 0, Errors: 0, Skipped: 0
```

覆盖物理 freshness 的入口时间戳、解析延迟旧帧、丢帧 session 恢复、恢复 single-flight、
手动断开/shutdown 禁止重连、轮询/审批公平串行，以及经过 `BleManager.handlePacket`
的 BLE 生产接收链路；同时覆盖审批状态、离线/发送失败/快速切换/延迟/重连模式同步、Kimi
fail-safe 与端口切换、Hook 配置保留/幂等/PowerShell 语法，以及发布固件参数和
最终 JAR 条目。

同日发布构建验证：

```text
mvn clean package                         BUILD SUCCESS
local JAR artifact contents              OK
preview-part3-release-overlay.ps1         OVERLAY_VALIDATION=OK
overlay JAR artifact contents             OK
```

overlay 验证使用本机最终 JAR 构造隔离的 `app/lib/models` 基线，完整执行编译、
allowlist、受保护类字节比较和最终 JAR 条目检查。当前机器未安装
`C:\Program Files\AhaKeyStudio`，公开 v0.1.1 Windows Release 是旧版 Python/Inno
安装包，不包含该 Java 基线；因此安装目录基线的再次验证仍属于发布机门禁。

### 5.2 手工软件验证（尚未执行）

- Claude/Cursor/Codex/Kimi 当前发行版实际安装、授权、重启、卸载；
- Desktop 关闭或 Hook 分发端口不可用时的端到端 deny；
- USB/BLE 切换时 9000 端口归属和 Kimi 旧 `approval.py` 兼容；
- 正式安装包 `jpackage`/WiX 完整生成（当前机器仍依赖基线安装目录与 WiX）。
- `build-installer.ps1 -PrepareOnly` 无 `FirmwareHex` 时已通过固件参数校验，随后按预期
  停在缺少 `C:\Program Files\AhaKeyStudio\AhaKeyStudio.ico`；需在发布机基线上完整执行。

### 5.3 Phase 1 发布前必做的真机矩阵（尚未执行）

1. 连接设备，拨杆 AUTO，连续触发 100 次审批，确认正确。
2. 连接设备，拨杆 MANUAL，连续触发 100 次，全部进入手动流程。
3. 缓存 AUTO 后拔掉设备，在 Claude/Cursor/Codex/Kimi 各触发审批，意外自动允许必须为 0。
4. 关闭 AhaKey Desktop 后触发 Cursor/Kimi 权限事件，不得允许。
5. 人工制造查询超时和非法 Hook 响应，不得允许。
6. 快速执行 Mode0→Mode1→Mode2，最终 UI 与设备确认模式一致。
7. 为 Claude/Cursor/Codex 预先配置第三方 Hook，安装、重启、卸载 AhaKey 后第三方 Hook 仍在。
8. 使用真实 1.4.3 HEX 刷写，重连后读取版本，并完成 GIF layout/上传/回读。

## 6. 已知限制和待办

### P0 剩余问题和外部依赖

- Claude/Codex/Cursor 生成脚本必须严格解析完整 JSON 和字段类型；任何空、截断、
  畸形或额外垃圾响应都不得进入 allow。
- 固件工作区已生成真实命名的 1.4.7 HEX，但源码和资产未提交、未真机验证、未发布；
  不得把它直接当作已批准的 bundled firmware。
- `expectedBundledVersion`、Java 运行时查找文件名、发布脚本参数和实际 HEX 必须一致；
  发布脚本必须拒绝声明版本与 expected bundled 不同的正式构建。
- 不得把旧 HEX 重命名成当前声明版本。

### P1 当前状态（2026-08-24）

Phase 2（GIF 和显示）的底层规则大部分已实现：规则集中到 `GifUploadRules`，
超限动画按源时间轴自动采样并保持总时长；文件选择跨入口记忆；窗口初始不选择文件，
批量只写 dirty 项；等待有界且支持请求取消；保存后回读校验 start/count/interval；
运行时灯效失败会上报 UI。但通用 OLED 入口没有列明具体超限原因，FPS 控件仍被保存却
不参与上传；单/多任务按钮仍在顶部栏，AI 状态区域没有屏幕动画入口，动画窗口也不定位
当前 Mode。软件手工验证和 USB 真机 Flash/GIF 回读仍待执行。

Phase 3（Windows 语音）的代码实现和基础自动测试已完成：低级 Hook 只识别并入队，
F18 统一为 `0x81`，长按等待为 3000 ms，显式 pressed-state 过滤重复事件，
ONNX tensor 确定性释放；尚未实现的 AhaType 已从 UI 隐藏。真实键盘、麦克风和模型推理
的手工/真机验证仍待执行。

Phase 4（生命周期和持久化）的主要路径和基础自动测试已完成：正常退出只停止本实例
拥有的 BLE bridge；退出、语言重启和更新重启共用 `ApplicationLifecycle`；第二实例通过
loopback 激活已有窗口；`StudioStore` 使用临时文件、flush 和原子替换；Hook 固定使用
8765，手工审批窗口为 15 秒；保存超时请求真实取消且事务退出前不释放互斥。
但手工审批超时不会关闭已经显示的对话框；普通命令等待没有绑定发送时的 transport
session，可能跨重连接受同命令响应；保存期间的新编辑可能在旧快照成功后被错误清为
已同步。托盘、更新、第二实例和断电写入场景的软件手工验证仍待执行。

Phase 5：清理

- `HookClient` / `SocketServer` 引用审计；
- `AgentManager` Hook placeholder 清理；
- Kimi 9000 兼容桥是否可在生态升级后删除，需先完成真实客户端引用审计；
- 仅进行小型、有测试支持的结构调整。

## 7. 已弃用候选组件

删除前必须完成全局引用、打包和兼容路径审计：

```text
HookClient
SocketServer
AgentManager hook-install placeholder
obsolete Kimi direct config sync
misleading legacy GIF preview/static APIs
```

## 8. 近期工程决策

### Decision 001 — 从 eternal-dev 稳定化

Windows 稳定化以 `eternal-dev` 为基线，不回到 `main` 重建功能。

### Decision 002 — 唯一自动审批条件

只有 fresh + connected + AUTO 可自动允许；其他所有状态进入手动或拒绝。

### Decision 003 — Hook 配置按命令所有权合并

不替换整个 `hooks` 节。安装和卸载只识别 `.ahakey/hooks/ahakey-*.ps1`。

### Decision 004 — 不伪造 bundled firmware

仓库没有可验证的 1.4.3 HEX 时，客户端和发布构建改为 1.4.3 门槛，
但不重命名任何旧二进制文件。

### Decision 005 — 当前稳定化不引入 SHA-256 产品要求

固件和应用更新的 SHA-256 校验不在本轮产品范围内。

### Decision 006 — freshness 与缓存/时间窗解耦

审批新鲜度由一次成功发送的物理查询和其后的物理状态帧配对产生；不得用缓存年龄、
`DEVICE_INFO_RESP`、BLE bridge 连接状态或固定时间窗代替。

### Decision 007 — 无 request-id 的超时事务必须隔离

物理状态协议没有 request-id 时，超时请求的结果未知。后续审批不得复用它的延迟帧；
协调器必须 fail closed，等待该帧被消费，或由断开/重连明确重建传输会话。

### Decision 008 — 模式 pending 代表已发送设备事务

离线选择不是设备事务；只有传输层确认命令已发送后才能建立 pending 窗口。
发送失败、断开和会话切换必须同步取消 pending。

### Decision 009 — 入口时间和 receiver/session 共同定义 freshness

解析完成时间不能代表物理到达时间。每个物理帧必须携带生产接收入口捕获的单调时钟
时间、receiver 世代和传输 session；三者与成功物理写入边界均匹配后才可完成查询。

### Decision 010 — unresolved 通过受控 session 重建恢复

无 request-id 时不能把 unresolved 简单重置后继续发送。超时触发 single-flight、
带退避的后台传输重建；旧 receiver 先失效，审批/UI 缓存清空，重建成功后新 session
才能接受查询。恢复期间所有审批均为 non-fresh。

### Decision 011 — USB reader 资源属于不可变传输 session

每次 USB open 都创建独立 generation，reader 捕获自己的 read/write handle、consumer、
断开回调和 stop 状态。close 先摘除 session，再在锁外 `CancelIoEx`、关闭捕获句柄并有界
等待；旧 reader 的帧、finally 和断开回调均不能访问或影响新 session。

### Decision 012 — 状态查询与设备写入共用生命周期事务门禁

状态查询在物理响应完成前持有公平事务锁；OLED/GIF、配置保存和恢复重建使用同一门禁。
unresolved 会先阻止新事务，恢复仅在已开始事务安全退出后获取门禁并关闭传输，且保持
single-flight 和 2 秒退避。所有等待均有界，手动断开和 shutdown 禁止自动重连。

### Decision 013 — 物理状态查询使用 WRITING 两阶段提交

查询在真实写入前只进入 WRITING；成功边界必须在 USB `WriteFile` 或 BLE write+flush
成功返回后捕获并随 marker 提交。写完成前进入接收路径的帧不缓存、不候选提交；只有
`receivedAtNanos > writeCompletedAtNanos` 才可接受，相等时间戳因无法证明先后而拒绝。
transaction state、receiver generation 和 transport session 仍须同时匹配，时间戳本身
不充当 request-id。同步 write 返回前的真实快速响应也按安全优先拒绝并走超时恢复。

### Decision 014 — 未超限 GIF 保留全部源帧

源帧数小于或等于设备分区上限时，`sourceIndices` 必须是恒等序列，统一 interval 仅用于
近似总时长，不得删除、重复或重排源帧。只有尺寸/文件超限或源帧数超限时才提示优化；
超限时间轴采样输出严格递增的合法索引。

### Decision 015 — 灯效操作只发布一个最终结果

亮度、灯效、AI 模式配置等底层 API 将失败抛给调用者。`LightOperationCoordinator` 在后台
串行执行命名步骤，遇到首个失败立即停止，并向 JavaFX 队列只发布一次带步骤和原因的
最终结果；只有全部步骤成功才生成成功消息。TaskActivityService 失败继续上报 UI。

## 9. 2026-08-24 验证记录

当日记录曾写为“代码完成：WIN-001 至 WIN-024（WIN-025/026 除外）、WIN-027、
WIN-029、WIN-030”。该句是 2026-08-24 的历史判断，不再代表当前符合性结论；当时文件
没有定义 WIN-007 至 WIN-030 的逐项含义。2026-08-26 起以下第 12 节是这些 ID 的
权威定义和当前状态。
历史自动测试结果：`mvn clean test` 和 `mvn clean package` 均执行 132 tests、
0 failures、0 errors、0 skipped，且 package 成功；PowerShell 脚本全部语法通过；
本地 JAR 和 release overlay JAR 关键清单通过，overlay 输出
`OVERLAY_VALIDATION=OK`。

P0 生产路径覆盖包括：旧帧在 write 前进入但延迟解析、写进行中帧、等于成功边界的帧、
写失败响应、严格晚于边界的快速响应、超时晚帧/新 session、丢帧 single-flight 恢复、并发恢复、poll 与四类
IDE 审批公平串行、设备事务与恢复互斥、USB 阻塞 read 的 close/reopen 与旧 reader 隔离、
手动断开/shutdown 不恢复，以及 mode session 失效。

P1 新增覆盖包括：未超限 GIF 恒等索引、超限严格有序降采样、统一 interval 时长误差、
真实优化确认条件；以及亮度首步失败、灯效第二步失败、全部成功、失败消息不可被成功
覆盖和 TaskActivityService 写入失败上报。软件手工和真机状态不变，仍为 pending。

软件手工验证：未执行。真机验证：未执行。外部资产：正式安装基线的图标和四个语音模型、
真实 1.4.7 CH582 HEX 仍缺失，因此 `build-installer.ps1 -PrepareOnly` 只能验证到基线资产
门禁，不能视为发布安装包完成。

## 10. 变更记录格式

问题完成并验证后，在本文档追加：

```text
### WIN-XXX — Title
Status: Fixed
Commit: <hash>
Verified by:
- <automated test>
- <manual/hardware scenario>
Remaining limitations:
- <none or explicit limitation>
```

不得在没有真实提交哈希时填写伪造哈希；未做的手工验证必须明确标记为 pending。

## 11.产品需求和 UX 不变式

### GIF 上传
- 源 GIF 最大 2 MB。
- 设备目标尺寸 160×80。
- 默认动画最多 8 帧。
- 运行中、等待/错误、已完成最多 12 帧。
- UI 提示、校验逻辑和编码规则必须统一读取 GifUploadRules，
  禁止各处硬编码不同限制。
- 文件不符合限制时不得直接拒绝，应列明超限原因并询问用户
  是否自动优化。
- 用户确认后允许自动缩放、抽帧，并尽量保持原动画总时长。
- 文件选择器记住用户最后一次选择的 GIF。
- 批量写入只处理 dirty 项，不得覆盖未修改动画。

### UI
- 单任务/多任务控制位于灯光设置模块下。
- 本阶段只调整入口位置，不修改多任务任务识别、灯珠映射或协议。
- AI 状态设置区域提供“屏幕动画设置”入口。
- 打开屏幕动画设置时优先定位当前 Mode。

### 默认动画素材
- 统一采用贴纸风 + 像素风 + 外阴影/清晰外轮廓。
- 画布 160×80。
- 动作简单、帧数少、配色克制。
- 单个默认 GIF 尽量控制在几十 KB。

上述产品需求属于长期 UX 不变式。除非产品负责人明确调整需求，
不得因重构、兼容处理或实现简化而静默删除、弱化或改变。

## 12. WIN-001 ～ WIN-030 权威登记与当前符合性（2026-08-26）

状态只允许使用“已满足”“部分满足”“未满足”“需手工/真机验证”。自动测试通过不等同于
真机完成。WIN-001～WIN-006 保留原定义；WIN-007～WIN-030 在本节首次明确登记，后续不得
再以未定义编号宣称完成。

| ID | 权威范围 | 当前状态 | 代码/测试证据 | 后续动作 |
|---|---|---|---|---|
| WIN-001 | fresh + connected + AUTO 唯一自动批准条件 | 需手工/真机验证 | `ApprovalService`、`PhysicalStatusFreshness` 及三组 freshness 测试覆盖代码路径 | 执行 USB/BLE 拔线、超时、旧帧和 100 次审批矩阵 |
| WIN-002 | Cursor 无响应/非法响应 fail closed | 需手工/真机验证 | 客户端严格解析固定字段/类型/值和精确 canonical allow；畸形、截断、额外字段均拒绝 | 四类 IDE 当前版本端到端验证 |
| WIN-003 | Claude/Codex 每次审批刷新硬件且非法响应 fail closed | 需手工/真机验证 | 四类审批共享 `ApprovalService`；严格响应解析测试通过 | USB/BLE 真机审批矩阵 |
| WIN-004 | Mode 快切、延迟响应、发送失败不回滚/误报 UI | 需手工/真机验证 | 离线编辑与设备事务分离；失败回滚 confirmed mode；session invalidation 清 pending | 快速切换、断线重连真机验证 |
| WIN-005 | Hook 安装卸载只改 AhaKey-owned 配置 | 需手工/真机验证 | 原子合并、幂等和保留第三方配置有测试 | 四类客户端当前版本安装/重启/卸载 |
| WIN-006 | bundled firmware、GIF 门槛和发布资产一致 | 部分满足 | expected bundled=1.4.7、GIF minimum=1.4.3、stabilized minimum=1.4.7；严格 provenance/HEX/签名门禁有测试 | 提供正式 HEX/provenance/签名环境并完成发布 |
| WIN-007 | GIF 2 MB、160×80、默认 8 帧、状态 12 帧的唯一规则源 | 已满足 | `GifUploadRules` 从 `AhaKeyProtocol` 读取；生产编码走 preflight/plan | 保留常量边界测试；真机确认固件容量 |
| WIN-008 | 不合规原因提示和按需自动优化 | 部分满足 | `ScreenAnimationDialog` 显示数值并确认；旧 OLED 入口只显示通用说明 | P1 统一原因列表，只有需要时询问 |
| WIN-009 | 未超限保留全部帧，超限按时间轴抽帧并保持总时长 | 需手工/真机验证 | `GifUploadRulesTest` 覆盖恒等索引、递增采样和时长误差 | 真机比较播放时长和视觉节奏 |
| WIN-010 | 最近 GIF 记忆和批量 dirty-only | 需手工/真机验证 | `GifSelectionHistory` 跨入口；批量循环只收集 dirty 项 | UI 重启及未修改槽位前后回读 |
| WIN-011 | AI 状态区入口和打开时定位当前 Mode | 未满足 | 入口仅在 More 菜单；`ScreenAnimationDialog` 未选择当前 tab | P1 移入口并按 `selectedMode` 选 tab |
| WIN-012 | 单/多任务按钮位于灯光设置模块 | 未满足 | 控件在 `TopBar.mainRow`，不在 `InspectorPane.createLightBarGroup` | P1 仅移动入口，不改识别、映射或协议 |
| WIN-013 | 不修改多任务识别、灯珠映射和协议 | 已满足 | 本次客户端 UI 待办不要求改 `TaskActivityService`/固件 task 协议 | 移动入口时锁定现有行为并回归 |
| WIN-014 | 默认 GIF 视觉规范、尺寸、帧数和体积 | 部分满足 | 16 个文件均为 160×80、8/12 帧、约 14–151 KB；仅抽样确认像素贴纸轮廓 | 产品视觉验收全部素材；压缩明显超过几十 KB 的文件 |
| WIN-015 | OLED 串行、真实取消、save 回读及 legacy API 边界 | 部分满足 | `OledUploadService` 共用锁、可中断、回读 start/count/interval；旧 FPS UI 无效，legacy API 仍在 | P1 删除/明确旧 FPS 与 API 语义并补取消集成测试 |
| WIN-016 | TaskActivity、灯光/OLED 状态不重复覆盖且失败可见 | 部分满足 | 多任务槽与全局状态在固件有明确优先级；失败会上报 UI | P1 模式切换失败回滚 UI；真机验证灯珠/OLED 优先级 |
| WIN-017 | low-level keyboard hook 只快速投递 | 需手工/真机验证 | callback 仅 pressed-state 判定和单线程队列投递 | Windows 实机测长按、焦点切换和 hook 延迟 |
| WIN-018 | F18 VK、3 秒长按和 repeat pressed-state | 需手工/真机验证 | F18=`0x81`、3000 ms、`VoiceKeyPressStateTest`；F17 仅作为显式兼容路由 | 键盘短按/长按/重复/丢失 key-up 实测 |
| WIN-019 | ONNX Tensor 确定性释放 | 需手工/真机验证 | 四个 tensor 与 result 均 try-with-resources | 连续录音推理和内存/句柄观察 |
| WIN-020 | AhaType 未实现时隐藏；KeyboardInjector 使用清晰 Unicode 路径 | 需手工/真机验证 | AhaType 控件未加入 UI；注入器无 CapsLock/Shift/OEM 分支 | 中文、英文、标点、换行、Tab 真机输入 |
| WIN-021 | 正常退出只停止本实例拥有的 BLE driver | 需手工/真机验证 | `BleBridgeProcessOwner` 只登记本实例 Process；长按“杀全部”是独立显式操作 | 外部 driver + 本实例 driver 并存退出测试 |
| WIN-022 | 所有退出/更新/语言重启统一走 lifecycle | 已满足 | View/Updater 调用 `ApplicationLifecycle`；`System.exit` 仅在 App 最终清理点 | 托盘/更新/语言入口手工回归 |
| WIN-023 | 第二实例唤醒现有窗口 | 需手工/真机验证 | 文件锁 + loopback `SHOW_WINDOW` 已实现 | 最小化/托盘/普通窗口三种状态实测 |
| WIN-024 | StudioStore 原子写入且生产配置事实源唯一 | 部分满足 | draft 使用临时文件、force、原子替换；未引用 `ConfigStore` 仍像第二套配置路径 | P2 删除无引用 `ConfigStore`，做断电/损坏文件验证 |
| WIN-025 | updater 只接受可发布且来源安全的安装资产 | 未满足 | manifest 入口要求 HTTPS，但 asset URL 未强制 HTTPS；EXE 只校验 MZ | P1 强制资产 HTTPS，并定义不依赖 SHA-256 的发布真实性门禁 |
| WIN-026 | firmware flasher 结构校验、烧录结果和回连版本确认 | 需手工/真机验证 | `IntelHexValidator` 完整行/校验和/EOF；WCHISP 成功后仍要求设备版本确认 | 使用正式 WCHISP 和 1.4.7 候选做成功/失败/降级矩阵 |
| WIN-027 | USB/BLE receiver、callback、到达时间和 session 隔离 | 需手工/真机验证 | 不可变 USB Session、receiver/session 检查及并发测试存在 | 快速插拔、USB↔BLE、延迟帧压力测试 |
| WIN-028 | 普通设备请求、保存和 GIF 操作不得跨 session 或误清 dirty | 部分满足 | 普通响应绑定 transport/session/receiver；保存按 dirty revision snapshot 清理 | 补齐 USB↔BLE 普通响应切换测试及 raw flash 真机断线测试 |
| WIN-029 | 固件源码协议、真实 HEX 和客户端能力一致且可发布 | 部分满足 | 软件侧固定 0x9D、protocol 3.2、model 1、mask 0x7FF、firmware 1.4.7，并严格验证 provenance | 固件团队提供正式可复现资产并做真机合同回读 |
| WIN-030 | legacy 路径清理或明确边界 | 未满足 | `HookClient`、`SocketServer`、`KimiConfigLeverSync`、`ConfigStore` 无引用；`AgentManager.installHooks` 假成功占位仍存在 | P2 删除无引用路径或记录并隔离必要兼容层 |

### 12.1 2026-08-26 新发现问题和优先级

P0：

1. 代码与自动测试已修复严格 Hook 解析和 1.4.7 cross-end contract。
2. 正式 overlay 仍被本机缺少已安装发布基线阻断；正式 HEX/provenance/Authenticode
   资产也尚未提供，因此 P0 只能标记为“代码和自动测试完成，发布/真机待验证”。

P1：

1. 普通命令响应等待未绑定发送 session，旧事务可能跨重连接受新 session 的同命令帧。
2. 配置保存期间产生的新编辑会在旧命令快照成功后被 `clearDirtyAfterSync()` 误清。
3. Mode 和单/多任务切换失败时 UI/Preferences 可保留未被设备确认的选择。
4. 手工审批 15 秒超时只令调用方返回拒绝，不关闭迟到的 JavaFX 对话框。
5. GIF/UI 入口位置、当前 Mode 定位、具体优化原因和无效 FPS 控件未满足产品要求。
6. stable manifest 内 asset URL 未强制 HTTPS；在“不引入 SHA-256 产品校验”的约束下，
   仍必须定义并实现最低限度的传输/签名信任边界。

P2：

1. 删除或隔离无引用 legacy 组件和 `AgentManager.installHooks()` 假成功占位。
2. 对 16 个默认 GIF 做完整视觉验收和有损/调色板压缩，保留 160×80 与帧/时序规则。
3. 动画窗口的异步初始读取不应覆盖用户刚选择后的状态提示。

### 12.2 当前发布判断

- 可以进入受控真机验证，但必须使用明确标记为非发布的测试构建。
- 不适合进入发布候选：上述两个 P0 未修复，正式安装资产和 WCHISP 环境未完成，
  Windows/IDE/USB/BLE/语音真机矩阵仍全部 pending。
- 固件 1.4.7 host 测试和 HEX 结构检查不能证明二进制与当前源码可复现，也不能替代
  CH582/AhaKey 真机烧录、版本回读、GIF/任务灯效和审批联调。

### 12.3 2026-08-26 自动验证记录

```text
mvn clean test
Tests run: 148, Failures: 0, Errors: 0, Skipped: 0
BUILD SUCCESS

mvn clean package
Tests run: 148, Failures: 0, Errors: 0, Skipped: 0
RELEASE_ARTIFACT_CONTENTS=OK
BUILD SUCCESS

PowerShell parser (project root *.ps1): POWERSHELL_PARSE=OK scripts=9
local JAR contents: RELEASE_ARTIFACT_CONTENTS=OK
release overlay: BLOCKED -- C:\Program Files\AhaKeyStudio\app is absent
git diff --check: PASS (line-ending conversion warnings only)
```

这些结果只证明当前 checkout 的 Java 自动测试、本地 JAR 内容和脚本语法通过。
本轮没有修改或验证固件源码；USB/BLE/GIF/OLED/语音真机、正式 overlay、安装包、
固件可复现构建及发布真实性验证仍为 pending。由于阶段门禁未满足，本轮未继续展开
第二阶段和第三阶段的剩余产品/清理工作。
