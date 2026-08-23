# AhaKey Runtime 架构规格

状态：已确认；实施仅由统一主任务调度

日期：2026-08-22
适用范围：macOS AhaKey Studio、AhaKey Runtime、USB/BLE 设备通信、AI Hooks、AhaType 与固件升级

## 1. 架构决定

AhaKey 的能力分为三层：

| 层级 | 负责能力 | 生命周期 |
|---|---|---|
| 键盘固件 | 基础按键、组合键、宏、Mode、已保存灯效、已上传 OLED 内容 | 始终可用 |
| AhaKey Runtime | AI Hooks、自动批准拨杆同步、状态灯/OLED、AhaType、定向会话路由、设备通信、AI 工具检测、防休眠 | 按用户策略常驻，或由 Studio 临时拉起 |
| AhaKey Studio | 配置编辑、账号界面、权限引导、诊断、固件升级入口 | 需要时打开，可完全退出 |

现有 `ahakeyconfig-agent` 演进为 AhaKey Runtime，不创建第三个后台进程。

Runtime 是 BLE 和 USB 设备通信的唯一所有者。Studio 不创建 BLE manager、不打开 USB HID，也不存在生产环境直连设备的回退路径。

```text
Firmware <-> AhaKey Runtime <-> AhaKey Studio
                    ^
                    |
          Codex / Claude / Cursor / Kimi Hooks
```

## 2. 核心不变量

1. 任意时刻只有一个 Runtime 进程可以控制一台设备。
2. Studio 退出、崩溃或升级不取消 Runtime 已受理的配置事务。
3. Runtime 只有在资源与事务日志持久化完成后才返回“已受理”。
4. USB 配置只对通过能力协商确认的 current 协议开放；legacy、unknown 和 restricted 设备不接收 USB 配置写入。
5. USB 与 BLE 只有设备身份匹配时才可视为同一设备的两种传输。
6. 配置包描述完整目标状态，不包含 opcode、物理槽位或传输选择。
7. 已确认步骤幂等；恢复和重试不得重复写入已确认资源。
8. Runtime 不可用时，Studio 不得绕过 Runtime 直连设备。
9. AI 瞬时状态不触发闪存保存；相同持久配置不重复写入。
10. 正式版只允许 Runtime 执行签名固件升级。

## 3. Studio 与 Runtime seam

共享模块只暴露一个小而稳定的 interface：

```swift
protocol AhaKeyRuntimeClient {
    func snapshot() async throws -> RuntimeSnapshot
    func events(after sequence: RuntimeEventSequence?) async -> AsyncThrowingStream<RuntimeEvent, Error>
    func apply(_ package: ConfigurationPackage) async throws -> OperationID
    func requestCancellation(of operation: OperationID) async throws -> CancellationDisposition
    func updatePolicy(_ policy: RuntimePolicy) async throws
}
```

### 3.1 RuntimeSnapshot

快照至少包含：

- Runtime、interface 和配置包 schema 版本。
- 当前活动设备及发现到的其他设备。
- 设备真实状态、协议能力和当前传输状态。
- 已确认配置 revision。
- 活动与最近配置事务的摘要。
- Runtime 策略、权限状态和保持运行的原因。
- 最后一个事件序号。

Studio 先获取快照，再从快照的事件序号订阅增量事件。事件缓冲无法补齐时，Studio 重新获取快照。

### 3.2 ConfigurationPackage

配置包是不可变、声明式目标，至少包含：

- `schemaVersion`
- `operationID`
- `targetDeviceID`
- `baseConfigurationRevision`
- 完整期望配置
- 内容寻址资源 manifest、长度和 SHA-256

配置包不得包含 BLE/USB、opcode、图片物理槽位或重试策略。Runtime 根据固件能力、设备容量和同步基线生成执行计划。

Runtime 接受包以前，将资源复制到 Runtime 管理的事务目录并完成尺寸、帧数、解码内存、总容量与哈希校验。Studio 的临时路径不得成为已受理事务的依赖。

### 3.3 RuntimeEvent

每个事件具有单调递增序号，并包含 operation、device、session 和 transport generation。事件分为：

- 设备真实状态变化。
- 配置事务进度、暂停、恢复和结果。
- Runtime 生命周期和权限变化。
- 结构化诊断与安全事件。

进度 UI 不得依赖某一条事件必然送达。

公开 wire model 使用受约束的设备状态、资源标识和事件码类型；`Codable` 解码必须重新执行范围、格式与哈希校验，不能依赖仅在业务构造器中执行的校验。未知模式和未来事件码通过显式的前向兼容表示处理，不能退回无约束整数或可互换字符串。

## 4. 生产与测试 adapter

生产环境使用两条不同权限的 seam：

1. Studio 与 Runtime 使用签名校验的 XPC。它可以读取诊断、提交配置、管理策略和发起固件升级。
2. AI Hooks 与 CLI 使用权限为 `0600` 的受限 Unix socket。它只接受版本化、限长、限速、白名单化的 AI 状态和拨杆查询消息，不能提交配置、账号、固件或任意 opcode。

测试使用内存 adapter。调用方和测试必须通过同一个 Runtime interface，不测试或依赖 Runtime 内部 BLE/USB 对象。

## 5. 设备会话与传输

### 5.1 USB 会话

USB 枚举后的状态机：

```text
disconnected
  -> probing
  -> currentReady | legacyDenied | restricted | failed
```

`probing` 阶段只允许必要的状态与 `0x99` 能力协商。确认 current 以前，不开放配置、图片或 AI 状态业务写入。

HID 实现必须具备：

- `07D7:501A` 与 `413C:2107` 双身份匹配。
- vendor usage page `0xFF00`。
- 64-byte report，A1 command、A2 data。
- device RunLoop schedule/unschedule。
- 首次打开失败后的重新枚举和有界退避重试。
- 产品名、序列号和稳定设备 ID 提取。

### 5.2 传输切换

命令 waiter 绑定 operation ID、device ID、session generation、transport generation 和请求标识。图片 session 内固定传输；只有 abort 或安全提交点后才允许切换。USB 超时回退 BLE 后，迟到 USB 回包不得完成 BLE waiter。

### 5.3 多设备

Runtime 可以发现多台设备，但第一阶段只能选择一个活动设备。配置包必须明确目标；Runtime 不自动改选、不广播 AI 状态。USB/BLE 身份不匹配时保持为两个设备。

## 6. 配置事务

Runtime 提供的是可恢复事务编排，不承诺旧协议无法提供的全设备原子性。

执行顺序：

1. 预检协议能力、资源、容量、设备身份与 base revision。
2. current 固件上传图片数据，但暂不切换绑定。
3. 写入键位、灯效和其他基础配置。
4. 更新图片绑定、激活状态并保存。
5. 持久化每个已确认步骤和新的配置 revision。

事务结果明确区分：全部完成、暂停等待恢复、部分完成可续传、永久失败且未写入、永久失败且保留部分提交。

Runtime 使用 SQLite WAL 保存事务、步骤、同步基线和事件游标；图片存入内容寻址文件目录。UserDefaults 不承担事务持久化。

临时断连和可重试超时采用有界退避；永久协议错误、资源错误、容量不足和设备拒绝立即停止。只有同一目标设备重连后才恢复。不得无限重试。

## 7. 命令调度

Runtime 内部优先级：

1. 断连处理、abort 和安全取消。
2. 已取得写租约的配置或固件事务。
3. 用户主动诊断。
4. AI 状态灯和 OLED 状态。
5. 后台轮询与维护。

AI 状态采用 latest-value 合并。配置期间仍接收 Hooks 和物理事件，但不让 AI 写入插入设备事务；事务结束后只补发最新有效状态。

## 8. Runtime 生命周期与 Studio 退出

- 任一智能能力启用时，Runtime 作为用户级登录项常驻。
- 所有智能能力关闭时，Runtime 不随登录启动。
- Studio 需要配置时临时拉起 Runtime。
- Studio 退出且没有智能策略或活动事务时，Runtime 自动退出。
- Studio 退出时若事务仍在运行，Runtime 继续直到完成、永久失败或安全终止。

Studio 对未完成事务采用软保护退出：默认留在 Studio查看进度，同时允许“退出，Runtime 继续”。只有处于可安全取消阶段时才提供“停止写入后退出”。不可中断的固件升级阶段不提供取消。

Runtime 完成、暂停或永久失败后发送不含敏感信息的系统通知；通知打开 Studio 并定位 operation ID。

## 9. 权限、账号和安全

- Runtime 使用稳定 bundle ID 和签名身份，直接持有麦克风、Speech、Accessibility、Input Monitoring 等运行权限；Studio 只展示并引导。
- macOS 13+ 使用 `SMAppService`；macOS 12 使用签名 LaunchAgent adapter。
- Studio 管理账号界面；Studio 与 Runtime 通过限定签名主体的共享 Keychain Access Group 读取凭据。
- refresh token 使用 `WhenUnlockedThisDeviceOnly`，短期 access token 只驻留 Runtime 内存，不经 XPC、socket、配置包或日志传递。
- 默认日志不落语音原文、剪贴板、AI 对话、token、兑换码、图片数据或完整设备序列号。
- 完整协议载荷只在用户显式开启的临时诊断期记录，并自动过期。

## 10. 安装、升级与迁移

XPC 握手返回 Runtime、interface 和配置包版本及能力集合。Runtime 至少兼容当前与上一版 Studio interface。事务运行时只暂存 Runtime 更新，事务结束后原子切换并完成健康检查。

首次迁移：

1. 停止并注销旧 `ahakeyconfig-agent`。
2. 导入已确认配置、同步 baseline、活动设备和 Runtime 策略。
3. 将图片复制到内容寻址存储。
4. 保留旧数据只读备份并写入 migration version。
5. 新 Runtime 健康后完成接管。

迁移后，旧 Studio 只能只读或提示升级，不得重新直连设备。正式版不保留 Runtime 失败时 Studio 直连的生产回退。

## 11. 性能与存储门槛

- Runtime 空闲五分钟平均 CPU `< 0.5%`。
- 非语音处理时常驻内存目标 `<= 60 MB`。
- 空闲唤醒平均 `<= 1/s`。
- 优先使用设备通知和系统事件；连接真实键盘且 AI/拨杆状态要求不超过 2 秒响应时保留 1.5 秒轮询，相同状态不得产生 UI 发布或常规磁盘日志；其他场景退避或停止轮询。
- 资源存储设总配额；垃圾回收不得删除活动事务引用。
- AI 瞬时状态不触发 flash save；相同内容哈希不重复上传。

## 12. 发布阻断条件

以下任一失败都阻断正式发布：

- current 纯 USB 无法完成全配置。
- legacy、unknown 或 restricted 设备收到 USB 配置写入。
- Studio 或旧 Agent 能与 Runtime 同时控制设备。
- Studio 退出、Runtime 重启或系统睡眠造成事务丢失或重复写入。
- USB/BLE 迟到回包能完成新 transport generation 的 waiter。
- 多用户会话能同时控制同一设备。
- Runtime 超出资源预算。
- Runtime、XPC、Keychain entitlement、安装包签名或公证失败。
- 正式版能够安装未签名固件。

## 13. 分阶段实施

1. **R0 — Interface 与持久化模型**：共享类型、schema、SQLite journal、内存 adapter 和契约测试，不改变现有设备路径。
2. **R1 — Runtime 外壳**：XPC、受限 hook socket、生命周期、版本握手和资源预算基线。
3. **R2 — Agent 能力迁移**：Hooks、拨杆、AI 状态、AhaType、语音和防休眠迁入唯一 Runtime。
4. **R3 — 设备通信迁移**：BLE/USB、current-only 协商、身份、队列、waiter 和断线恢复迁入 Runtime。
5. **R4 — 配置事务**：声明式配置包、资源存储、同步规划、图片及基础配置事务。
6. **R5 — Studio 纯客户端化**：删除 Studio 直连、接入快照/事件/操作 UI、软保护退出。
7. **R6 — 升级与迁移**：旧 Agent 清理、权限迁移、共享 Keychain、签名固件与 Runtime 原子更新。
8. **R7 — 灰度发布**：自动化、HIL、多用户、睡眠唤醒、性能、签名、公证和回滚演练。

每个阶段必须独立可测试、可回退；不得直接合并 `main-anpx` 的完整 USB 提交。所需行为应逐项移植，并保留 current-only、设备身份匹配、超时隔离与 legacy 保护。

## 14. 当前实施状态

R0 interface v1.1 已冻结：

- Snapshot 明确携带 Runtime、interface 与配置包 schema 三类版本。
- 纯硬件前台语音不进入 RuntimePolicy；AhaType 与定向会话路由分别表达。
- RuntimePolicy 结构化表达 AhaType 触发键、启用的 AI 工具、拨杆批准规则、语音路由、动态 LED/OLED、防休眠和临时诊断期限。
- Snapshot 包含权限、保活原因、设备能力、真实设备状态以及 session/transport generation；RSSI 不进入主快照。
- Event 携带 operation/device/generation context，并支持 lifecycle、permission、keep-alive、结构化诊断与安全事件。
- 相同策略更新零事件发布。
- 只有完整完成的声明式目标推进 configuration revision；部分完成保留原 revision。
- 永久失败区分“未写入”和“保留部分提交”；部分完成记录真实 completed/total steps。
- operation ID 的相同配置包在 revision 推进后仍可幂等重放，内容冲突仍被拒绝。

R0 持久化内核已完成：

- SQLite 使用 WAL、`synchronous=FULL`、schema version 和外键约束；拒绝打开更高版本 schema。
- 已受理事务、步骤确认、同步基线、RuntimePolicy 和事件序号均可跨进程重启恢复；崩溃前的 `running` 状态重开后归一为 `paused`。
- 资源在事务受理前校验普通文件、长度和 SHA-256，复制到权限收紧的内容寻址目录；相同摘要去重计费，并实施单文件与总容量配额。
- 恢复前重新验证托管资源完整性；符号链接、损坏资源和 operation ID 内容冲突均拒绝。
- 9 项持久化集成测试与完整 194 项 Swift 测试通过。

下一阶段是 WBS 5.2 生产 seam：签名 XPC、受限 framed Hook socket、版本握手和事件重放。持久内核尚未接入生产 Runtime、BLE/USB 或 Studio。
