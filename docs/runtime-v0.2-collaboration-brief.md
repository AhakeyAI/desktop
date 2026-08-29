# AhaKey Runtime 升级方案与 v0.2 协作开发说明

状态：协作开发基线
更新日期：2026-08-29
适用对象：AhaKey Studio、Runtime、安装器、Hook、测试与发布协作者

## 1. 一页结论

AhaKey 正在从“Studio 直接连接键盘并承载后台能力”升级为三层架构：

```text
┌─────────────────────────────────────────────┐
│ AhaKey Studio                               │
│ 配置编辑、诊断、权限引导、固件升级入口       │
└──────────────────┬──────────────────────────┘
                   │ signed libxpc
┌──────────────────▼──────────────────────────┐
│ AhaKey Runtime（由现有 ahakeyconfig-agent 演进）│
│ 唯一设备 owner、事务、Hook、AI 状态、防休眠   │
└───────────────┬───────────────────────▲─────┘
                │ BLE / USB             │ 0600 socket
┌───────────────▼──────────────┐   ┌────┴──────────────┐
│ AhaKey X1 固件               │   │ AI 工具 Hooks     │
│ 按键、灯效、已保存配置        │   │ Codex/Cursor 等   │
└──────────────────────────────┘   └───────────────────┘
```

核心决定：

1. Runtime 是 BLE/USB 的唯一设备所有者；Studio 没有生产直连回退。
2. Studio 可以完全退出；已启用的 AI 检测、自动批准、防休眠和已受理事务继续运行。
3. 配置通过声明式 package 提交；Runtime 负责预检、规划、传输、重试和恢复。
4. v0.2 先交付可靠的 macOS 客户端，不等待统一固件、OLED、语音、拨杆宏和 Windows。
5. v0.2 的 OLED/任务图功能由集中式发布策略关闭；基础键位/灯效不能夹带 `0x95`、`0x97` 或图片资源。

## 2. 为什么要升级 Runtime

旧架构暴露了四类产品问题：

- Studio 与 Agent 可能同时连接设备，造成 BLE/USB 抢占和命令竞态。
- Studio 关闭后，AI 工具检测、拨杆自动批准、防休眠等后台能力可能中断。
- 配置写入依赖前台进程和临时文件，断连、退出或崩溃后缺乏可靠恢复。
- BLE 正常轮询、日志和隐藏页面观察曾持续触发 SwiftUI 发布与布局计算，造成 CPU/RSS 投诉。

新架构把复杂性集中到 Runtime 深模块后，Studio 只需要学习一个小 interface，而不需要了解 BLE、USB、opcode、重试或存储细节。

## 3. 冻结的架构不变量

以下规则是协作者修改代码时必须守住的边界：

1. 同一时刻只有一个 Runtime 进程控制一台设备。
2. Studio 不创建 BLE manager、不打开 USB HID、不在 Runtime 离线时直连设备。
3. Runtime 只有在资源和事务日志持久化完成后才返回“已受理”。
4. Studio 退出、崩溃或升级不取消 Runtime 已受理的事务。
5. 配置 package 不包含 opcode、物理槽位或 BLE/USB 选择。
6. Runtime 根据设备能力、容量、同步基线生成执行计划。
7. legacy、unknown、restricted 和矛盾能力状态必须 fail-closed。
8. AI 瞬时状态不写 Flash；相同状态不重复发布 UI 或常规日志。
9. 配置事务窗口内暂缓会覆盖 OLED 的动态 `0x90`，结束后只补发最新状态。
10. 安装、签名、登录项变更、刷机和正式发布都需要独立 USER-GATE。

完整规格见 [`ahakey-runtime-architecture.md`](ahakey-runtime-architecture.md)。

## 4. Runtime interface 与关键 seam

Studio 面向的核心 interface 是：

```swift
protocol AhaKeyRuntimeClient {
    func snapshot() async throws -> RuntimeSnapshot
    func events(after sequence: RuntimeEventSequence?)
        async -> AsyncThrowingStream<RuntimeEvent, Error>
    func apply(_ package: ConfigurationPackage) async throws -> OperationID
    func requestCancellation(of operation: OperationID)
        async throws -> CancellationDisposition
    func updatePolicy(_ policy: RuntimePolicy) async throws
}
```

### 4.1 Studio ↔ Runtime

- 生产 Adapter：签名校验的 libxpc。
- 数据格式：受约束、版本化的 wire model。
- 启动流程：handshake → snapshot → event long-poll。
- 事件断档：重新获取权威 snapshot，不猜测状态。
- Studio 断开：Runtime 内已受理操作继续。

### 4.2 Hook ↔ Runtime

- 使用权限 `0600` 的 Unix socket。
- 只接受限长、限速、版本化、白名单消息。
- Hook 可以发布 AI 状态和查询拨杆批准模式。
- Hook 不能提交配置、固件、账号或任意 opcode。
- 拨杆上档为自动批准、下档为手动批准；离线或异常必须 fail-closed。

### 4.3 Runtime ↔ 设备

- Runtime 独占 BLE/USB。
- 协商状态区分 current、legacy、restricted、unknown。
- 命令 waiter 绑定设备、会话和 transport generation，迟到回包不能完成新请求。
- 配置事务持有写租约；AI 状态在事务期间合并，结束后补发最新值。

## 5. 已落地的主要改动

### 5.1 Runtime 基础设施

| 工作包 | 状态 | 已交付能力 |
|---|---|---|
| WBS 5.0 | accepted | RuntimePolicy、Snapshot、Event、ConfigurationPackage、revision 语义 |
| WBS 5.1 | accepted | SQLite WAL、内容寻址资源仓库、配额、崩溃恢复 |
| WBS 5.2 | accepted | 签名 libxpc server/client、Hook socket、握手、回放、双签名 smoke |
| WBS 5.3 | accepted | RuntimeOrchestrator、AI Hook、批准、灯效、防休眠、AhaType 接入 |
| WBS 5.4 | accepted | 策略化生命周期、Studio 退出保活、模块启停 |
| WBS 5.5 | accepted | Runtime 唯一设备 owner、BLE/USB、身份、队列、waiter、回连 |
| WBS 5.6 | accepted | 声明式配置规划、持久事务、资源 ingest/apply/cancel/resume |
| WBS 5.7 | accepted | Studio 纯 Runtime 客户端、snapshot/event、操作 UI、退出语义 |

### 5.2 配置事务与 UI 收口

已完成的客户端能力包括：

- durable accept 后立即返回 operation ID，Agent 后台串行执行。
- 取消、断连、暂停、部分完成和恢复状态持久化。
- byte progress 是可选 wire 字段；旧客户端/Runtime 可双向兼容。
- progress 只在设备确认块后推进，同值零发布，运行中约不超过 4 Hz。
- 失败上下文、事件和 snapshot 从同一 WAL 事实来源恢复。
- Studio 写入时冻结提交快照，上传期间切模式或继续编辑不会误标同步。
- 图片预检在 ingest/apply 前完成；规范化临时文件在所有退出路径清理。
- CPU/文件编码离开 facade actor，并支持取消。

OLED 的这些代码能力归 v0.3；v0.2 通过发布策略隐藏，不对当前量产固件开放。

### 5.3 v0.2 集中式兼容策略

`AhaKeyReleaseFeaturePolicy` 是 v0.2 的单一功能事实来源：

- 输入是发布通道和已经协商出的 typed negotiation state。
- 不复制 `0x99` parser，不允许调用方自由拼接 protocol mode 与 capabilities。
- `.negotiating`、畸形响应、未知响应和矛盾状态 fail-closed。
- v0.2 对所有设备关闭 OLED/default picture/task picture/resource package。
- 基础键位/灯效只对明确识别且安全的终态开放。
- UI、draft dirty 计算、assembler、facade、planner、mapper、runner 与 Agent 都消费同一策略投影。

最终兼容策略产品提交：`d9d2cbb`。最终门禁：Swift 全量 593 项通过、App/Agent Release 构建通过。

## 6. v0.2 产品范围

### 6.1 对用户开放

- macOS AhaKey Studio。
- 轻量 AhaKey Runtime。
- 键盘连接和真实状态展示。
- AI 工具检测。
- 拨杆自动批准/手动批准切换。
- Studio 退出后的后台防休眠与已启用能力保活。
- 当前量产固件上经过门禁的基础键位/灯效配置。
- 签名 DMG、覆盖升级、卸载和回滚路径。

AhaType 已迁入 Runtime 架构，但 v0.2 不把它包装成新的“纯硬件语音”能力；现有 AhaType 路径必须不回归，系统/第三方纯硬件语音的正式产品范围归 v0.4。

### 6.2 明确不包含

- OLED/任务图编辑和写入。
- 统一 Standard/Rhino 固件。
- 图片上传、`0x95`/`0x97` active set 和断电保持。
- macOS F5 / Windows Win+H 的统一固件平台学习。
- Typeless/Fn/Globe/F19 语音模板配置。
- 拨杆自定义快捷键和宏。
- Windows Studio/Runtime 正式支持。
- 最近待操作会话定向。

延期功能必须隐藏或只读，不能留下可通过深链、恢复草稿或旧 UI 绕过的入口。

## 7. v0.2 写入安全口径

基础键位/灯效保存必须满足：

```text
Studio draft
  → ReleaseFeaturePolicy 投影
  → package assembler（强制空 OLED）
  → Runtime planner
  → step mapper
  → 仅允许的基础 opcode
```

当前冻结证明：

- 不 ingest 图片资源。
- 不生成 resource transaction。
- 不发送 `0x95`、`0x97`。
- 基础命令 opcode 只能落在当前 v0.2 白名单中。
- 隐藏 OLED 草稿不计入 v0.2 dirty 状态。
- 键位/灯效成功只推进对应同步基线，不把 OLED 草稿标成已同步。
- 畸形 OLED 草稿不能阻塞键位/灯效保存。

不要通过“忽略 `0x97` 失败”或“双绑 A/B 图片”来制造成功；v0.2 的策略是根本不进入图片写入路径。

## 8. 性能与日志原则

- 设备状态先归并为 Equatable snapshot，字段真实变化后才发布。
- 连接真实键盘且需要 AI/拨杆状态时保留 1.5 秒轮询，目标响应不超过 2 秒。
- 相同状态每轮零 UI 发布、零常规磁盘日志。
- RSSI 只在诊断窗口打开时进入诊断 Store。
- 诊断日志独立保存，内存最多 200 条。
- 默认永久日志只记连接、断开、重连、真实状态变化和错误。
- 原始 TX/RX 仅用户主动开启，15 分钟自动关闭；后台串行写入并轮转。
- Studio 隐藏时暂停持续动画和诊断观察；真实状态变化允许一次发布。

v0.2 HIL 需要连接真实键盘连续采样至少 30 分钟；无设备空跑不能作为唯一性能证据。

## 9. 安装与发布路径

### 9.1 当前任务：WBS 5.9A

状态：`active`，Cursor 是唯一执行 owner（20:22 已 ACK）。

本卡只允许开发和验证：

- 可复现的未签名 Studio + Runtime 候选。
- 安装器和打包脚本。
- 稳定 Bundle ID、Signing ID、Team ID、Mach service 输入检查。
- 旧 Agent 互斥/清理逻辑。
- 可注入的安装、覆盖升级、失败回滚、卸载测试。
- 签名输入清单、版本清单、回滚说明和已知限制。

本卡禁止：

- 实际使用 Developer ID 签名。
- 修改 `/Applications`。
- 修改登录项或实际安装/卸载。
- 启动 v0.2 HIL、发布或 push。

### 9.2 下一门禁：HIL-RELEASE-0.2

只有 WBS 5.9A accepted 且用户明确批准后，才能：

1. 使用 Developer ID 生成签名候选 DMG。
2. 干净安装、覆盖升级、登录重启、卸载和回滚。
3. 验证只有一个 Runtime/Agent owner。
4. 用当前量产键盘验证连接、重连、基础配置、Hook 和防休眠。
5. 验证 OLED 入口不可进入。
6. 运行 30 分钟真实键盘 CPU/RSS 与日志门禁。

HIL 卡只做验证；发现产品缺陷必须另开返工卡，不能在 HIL 中顺手修改业务代码。

## 10. 当前状态与下一步

截至 2026-08-29：

| 通道 | 当前状态 | 下一动作 |
|---|---|---|
| macOS 客户端 | v0.2 兼容策略 accepted @ `d9d2cbb`；WBS 5.9A active | Cursor 开发未签名安装链 |
| v0.2 真机发布 | `HIL-RELEASE-0.2` draft / USER-GATE | 等 5.9A accepted 和用户批准 |
| OLED / 配置事务 | E-1 accepted；HIL-CONFIG blocked | 归 v0.3，不阻塞 v0.2 |
| 统一固件 | Zcode 执行 WBS 1.5 R20 | 独立固件仓继续；不刷机、不阻塞 v0.2 |

发布列车：

```text
v0.2  Runtime 可用客户端 + 兼容策略 + 安装/HIL
  ↓
v0.3  统一固件 + OLED + 配置事务 C1-C6
  ↓
v0.4  纯硬件跨平台语音
  ↓
v0.5  拨杆快捷键与宏
  ↓
v1.0  Windows + 完整迁移 + 性能/灰度/量产
  ↓
v1.1  最近待操作会话定向
```

## 11. 主要代码导航

| 关注点 | 主要文件 |
|---|---|
| Runtime 共享契约 | `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimeContract.swift` |
| Runtime 持久化 | `AhaKeyRuntimePersistentStore.swift` |
| XPC server/client | `AhaKeyRuntimeXPCLibXPCServer.swift`、`AhaKeyRuntimeXPCLibXPCClient.swift` |
| Hook socket | `AhaKeyRuntimeHookSocket.swift` |
| 生产 seam | `AhaKeyRuntimeProductionSeam.swift` |
| Agent/设备 owner | `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift` |
| 设备快照 reducer | `DeviceStateReducer.swift`、`CoreSnapshotChangeSummary.swift` |
| BLE 日志隔离 | `BLELogStore.swift`、`BLELogPolicy.swift`、`VerboseLogSessionController.swift` |
| 配置规划 | `AhaKeyConfigurationPlanner.swift` |
| 配置执行 | `AhaKeyConfigurationTransactionEngine.swift`、`AhaKeyConfigurationTransactionRunner.swift` |
| Studio facade | `AhaKeyStudioRuntimeFacade.swift` |
| Studio 状态投影 | `AhaKeyStudioRuntimeStore.swift` |
| v0.2 功能策略 | `AhaKeyReleaseFeaturePolicy.swift` |
| package 组装 | `AhaKeyStudioPackageAssembler.swift` |

## 12. 协作纪律

协作开发以以下文件为唯一事实来源：

- 总范围与版本：[`unified-firmware-runtime-implementation-plan.md`](unified-firmware-runtime-implementation-plan.md)
- 架构不变量：[`ahakey-runtime-architecture.md`](ahakey-runtime-architecture.md)
- 顺序与 owner：[`collab/queue.md`](collab/queue.md)
- 当前任务卡：[`collab/taskcards/`](collab/taskcards/)
- 异步沟通：[`collab/board.md`](collab/board.md)

执行规则：

1. 同一写入域同一时刻只有一个 owner。
2. 没有 `ready` 任务卡和路径白名单不得开工。
3. 执行方按逻辑提交，回传固定 commit、测试和未做事项后停手。
4. Codex 只读验收，决定 accepted、返工或 blocked。
5. board 只在末尾追加，不修改历史。
6. 安装、签名、刷机、远端 push 和发布均不因任务卡完成而自动授权。

## 13. 接手者常见误区

- 不要恢复 Studio 直连 BLE 作为“临时兼容”。
- 不要在 View 中散落版本判断；统一消费 ReleaseFeaturePolicy。
- 不要把源图片路径写进已受理事务；Runtime 必须拥有持久资源副本。
- 不要把 OLED 失败降级成 v0.2 成功；v0.2 根本不提交 OLED。
- 不要把 `framesPerSlot=30` 说成 0x99 的设备总容量。
- 不要在正常 1.5 秒轮询中写 TX/RX 详细日志。
- 不要让隐藏窗口继续动画、观察诊断 Store 或重复发布相同状态。
- 不要在 HIL 卡里顺手修产品代码。
- 不要把 v0.3-v1.1 的未验收能力反向阻塞 v0.2。

## 14. 相关文档

- [`unified-firmware-runtime-implementation-plan.md`](unified-firmware-runtime-implementation-plan.md)
- [`ahakey-runtime-architecture.md`](ahakey-runtime-architecture.md)
- [`collab/taskcards/RELEASE-0.2-COMPATIBILITY.md`](collab/taskcards/RELEASE-0.2-COMPATIBILITY.md)
- [`collab/taskcards/WBS-5.9A-BETA-INSTALLER.md`](collab/taskcards/WBS-5.9A-BETA-INSTALLER.md)
- [`collab/taskcards/HIL-RELEASE-0.2.md`](collab/taskcards/HIL-RELEASE-0.2.md)
- [`collab/taskcards/STUDIO-OLED-ENCODE-AND-PARTIAL-APPLY.md`](collab/taskcards/STUDIO-OLED-ENCODE-AND-PARTIAL-APPLY.md)
