# AhaKey 统一固件、纯硬件语音与 Runtime 解耦实施计划

状态：统一调度基线；Runtime 设备所有权决策已确认

日期：2026-08-22
适用范围：AhaKey X1 固件、macOS Studio、Windows Studio、后台 Runtime、生产烧录与发布流程

## 0. 文档权威、当前进度与单一实施入口

本文档是固件、Studio、Runtime、AhaType、AI Hooks 与会话定向的唯一总实施计划。专题文档的关系如下：

| 文档 | 定位 | 约束 |
|---|---|---|
| 本文档 | 产品范围、依赖、WBS、批次与发布门禁 | 发生冲突时决定交付顺序与范围 |
| [`ahakey-runtime-architecture.md`](ahakey-runtime-architecture.md) | Runtime 深模块、设备所有权、事务与安全规格 | 对 Runtime 内部设计具有约束力 |
| [`research/openmicrokbd-session-activation.md`](research/openmicrokbd-session-activation.md) | OpenMicro/OpenMicroKBD 研究证据 | 只提供设计输入，不直接驱动实现 |

从 2026-08-22 起执行单一写入规则：

- “CPU占用优化”当前任务是唯一实施和集成入口，负责拆批、修改、验证、提交与回滚。
- “对比 Rhino 与主线固件进度”任务保持 idle，只提供基线、差异和历史决定，不再改文件。
- “调研 openmicrokhd 会话唤起机制”任务保持 idle，只保留研究结论，不再实现 `SessionRouting`、`TargetLease` 或 Hook。
- 后续若需要专题复核，由主任务下发只读问题；任何实现必须回到本任务按一个批次、一个 owner、一个验收门禁执行。

当前工作区进度：

| 产物 | 状态 | 处理决定 |
|---|---|---|
| Runtime 架构规格 | 初稿完成 | 纳入本文并继续校准语音、轮询与跨平台边界 |
| `AhaKeyRuntimeContract.swift` | WBS 5.0 interface v1.1 已冻结，契约测试通过 | 持久层只依赖该公开 interface，不反向泄漏 SQL/文件布局 |
| `AhaKeyInMemoryRuntimeAdapter.swift` | R0 测试 Adapter 原型 | 仅测试使用，不接入生产路径 |
| Runtime 持久化测试 | 14 项契约测试、9 项持久化集成测试；完整 Swift 套件 194 项通过 | 作为后续兼容与崩溃恢复基线 |
| SQLite WAL、资源仓库 | WBS 5.1 已完成 | 生产 Runtime 接入前保持为独立持久事务内核 |
| XPC、Hook socket | 未开始 | 下一批按 WBS 5.2 实施 |
| Runtime 设备独占、Studio 纯客户端化 | 未开始 | 未完成前不得宣称新客户端架构正式交付 |
| OpenMicro 会话唤起研究 | 已完成 | 延后到核心 Runtime 稳定后的 WBS 5A |
| WBS 0.1 基线冻结 | 已完成 | 见 [`firmware-client-baseline-2026-08-22.md`](firmware-client-baseline-2026-08-22.md) |
| WBS 0.2 行为/协议/Flash 矩阵 | 部分完成 | 行为与协议入口已静态比较；Flash 地址、大小、占用和 HIL 仍开放 |

已解决的跨方案冲突：

1. **设备所有权**：正式版以 Runtime 为 BLE/USB 唯一所有者；Studio 不设直连回退。统一固件和纯硬件能力可以先生成内部固件，但包含新配置 UI 的公开客户端必须等到 Runtime 独占和 Studio 纯客户端化完成。
2. **语音边界**：F5、Win+H、Fn/Globe/F19 和用户自定义语音快捷键属于固件前台动作，不需要 Runtime；只有 AhaType 或 `latestActionableSession` 定向路由需要 Runtime。
3. **轮询策略**：设备通知优先；但连接真实键盘且 AI/拨杆状态需要后台响应时保留 1.5 秒轮询，以满足不超过 2 秒目标。相同状态每轮必须零 UI 发布、零常规磁盘日志；非活动、断连与不需要实时设备状态的场景退避或停止轮询。
4. **配置事务**：Studio 只提交声明式 `ConfigurationPackage`；Runtime 负责协议规划、传输、重试、资源和 SQLite WAL。旧协议允许“可恢复的部分完成”，不能虚构全设备原子性。
5. **会话定向**：会话选择只属于 Runtime；固件不保存窗口或 session 信息。首发先做 Codex App 精确 Adapter，PTY wrapper 是后续增强，不阻塞基础产品。

## 1. 结论与交付目标

本项目交付后，AhaKey 的日常能力分为三层：

1. 键盘固件负责按键、宏、拨杆动作、平台相关系统语音快捷键和本地出厂资源；这些能力不依赖 AhaKey Studio 或 Runtime。
2. AhaKey Runtime 只负责必须在电脑上持续执行的增强能力：AhaType、AI 工具检测与自动批准、最近待操作会话定向、动态 AI 灯效/OLED、防休眠等。
3. AhaKey Studio 只负责编辑配置、固件升级、诊断和 Runtime 管理，完成配置后可以完全退出。

键盘本体没有麦克风，也不处理音频。所有语音路径都始于键盘发送快捷键，电脑端系统、第三方软件或 AhaType Runtime 再调用电脑麦克风。

目标体验：

| 用户场景 | Studio | Runtime | 退出 Studio 后是否可用 |
|---|---:|---:|---:|
| 普通快捷键、宏 | 不需要 | 不需要 | 是 |
| macOS 系统听写（默认 F5） | 不需要 | 不需要 | 是 |
| Windows 系统语音输入（Win+H） | 不需要 | 不需要 | 是 |
| Typeless 等第三方语音软件 | 不需要 | 不需要 | 是，目标软件自身需运行 |
| 拨杆触发快捷键或宏 | 不需要 | 不需要 | 是 |
| AhaType | 不需要 | 需要 | 是 |
| 定向唤起最近待操作会话后语音输入 | 不需要 | 需要 | 是 |
| AI 工具检测与自动批准 | 不需要 | 需要 | 是 |
| 动态 AI 状态灯/OLED | 不需要 | 需要 | 是 |
| 防休眠 | 不需要 | 需要 | 是 |

## 2. 当前代码基线与整合判断

### 2.1 桌面端

macOS 当前已有三个可复用层次：

- `AhaKeyConfig`：SwiftUI Studio。
- `ahakeyconfig-agent`：后台 BLE、Hook、拨杆和状态灯逻辑。
- `AhaKeyConfigShared`：共享路径、Keychain、状态 reducer、固件能力模型。

当前需要纠正的地方：

- `VoicePreset` 同时表达“固件发什么键”和“电脑收到后做什么”，职责混合。
- Studio 启动时会无条件启动 `VoiceRelayService` 和 `NativeSpeechTranscriptionService`。
- macOS 系统听写、Typeless 等纯快捷键路径被错误地变成了 Studio 运行时依赖。
- Studio 与 Agent/Runtime 都可能持有 BLE，存在连接所有权交接和重复实现。
- Runtime 策略尚未形成独立、版本化的事实来源。

### 2.2 固件

GitHub `AhaKey-X1-hardware-source/dev` 当前基线提交为 `3e7f900`。该基线包括有线 HID、AI 状态、拨杆上报、自动关机和默认关闭的 SDK bridge；默认录音键仍为 F18。

Gitee/Rhino 定制版及本地 Rhino 后续包含：

- 四状态 OLED 与双套任务 GIF。
- 事务化出厂资源和资源 manifest。
- 图片槽位保护、上传恢复和更可靠的写入确认。
- LCD/SPI 超时保护。
- macOS USB 枚举、USB/BLE 身份与 VBUS 切换修复。
- 强制关机等真实硬件稳定性修复。

整合结论：

- GitHub `dev` 作为统一主线。
- Rhino 能力按行为逐项移植，不做目录级盲目合并。
- SDK bridge、自动关机等 GitHub 新能力不得丢失。
- Rhino 稳定性、资源和上传能力不得回退。
- Standard 与 Rhino 只允许出厂资源不同，不允许长期形成两套业务代码。

## 3. 目标技术架构

```text
┌─────────────────────────────────────────────────────────┐
│ AhaKey Studio                                           │
│ 配置编辑 / 平台状态 / 固件升级 / 诊断 / Runtime 管理       │
└──────────────────────┬──────────────────────────────────┘
                       │ Signed XPC / Runtime Interface
┌──────────────────────▼──────────────────────────────────┐
│ AhaKey Runtime                                          │
│ RuntimeOrchestrator                                     │
│ ├─ AhaTypeModule                                        │
│ ├─ AIIntegrationModule                                  │
│ ├─ SessionRoutingModule                                 │
│ ├─ DeviceRuntimeModule                                  │
│ └─ PowerProtectionModule                                │
└──────────────────────┬──────────────────────────────────┘
                       │ USB / BLE（Runtime 唯一持有）
┌──────────────────────▼──────────────────────────────────┐
│ AhaKey Unified Firmware                                 │
│ ├─ HostPlatformModule                                   │
│ ├─ InputActionModule                                    │
│ ├─ LeverBindingModule                                   │
│ ├─ DeviceConfigStore                                    │
│ ├─ OLED/LED/FactoryAssetsModule                         │
│ └─ USB/BLE Transport Adapters                           │
└─────────────────────────────────────────────────────────┘
```

### 3.1 三个事实来源

#### DeviceConfiguration

存储在固件，负责不依赖电脑后台进程的行为：

```text
键位绑定
硬件宏
系统语音语义动作
拨杆三档硬件动作
本地灯效
OLED 静态/本地动画绑定
平台覆盖和已学习的平台信息
```

#### RuntimePolicy

存储在电脑，负责后台增强能力：

```text
AhaType 是否启用及触发键
AI 工具与 Hook 策略
拨杆自动/手动批准解释规则
语音输入是作用于当前前台还是最近待操作会话
动态状态灯/OLED
防休眠
日志与临时诊断策略
```

#### StudioDraft

只负责编辑过程和 UI 临时状态，不是固件或 Runtime 的事实来源。保存时分别编译为 `DeviceConfiguration` 和 `RuntimePolicy`。

## 4. 语音能力设计

### 4.1 统一定义

语音配置表达“快捷键由谁消费”，不表达键盘录音：

```swift
enum VoiceActivationTarget: Codable, Equatable {
    case systemVoice
    case thirdParty(ThirdPartyVoiceProfile)
    case ahaType(AhaTypeActivationPolicy)
    case custom(ShortcutBinding)
}

enum VoiceRoutingPolicy: Codable, Equatable {
    case foreground
    case latestActionableSession(SessionSelectionPolicy)
}
```

语音执行目标与会话路由是两个独立维度：

```text
VoiceConfiguration {
  activationTarget: systemVoice | thirdParty | ahaType | custom
  routingPolicy: foreground | latestActionableSession
}
```

- `foreground`：系统语音和第三方语音由固件直接发送快捷键，不需要 Runtime；AhaType 仍需要 Runtime。
- `latestActionableSession`：不论最终使用系统语音、第三方语音还是 AhaType，都需要 Runtime 先选择并激活目标会话。
- `requiresRuntime = activationTarget == AhaType || routingPolicy != foreground`。

默认行为：

| 目标 | macOS | Windows | Runtime |
|---|---|---|---:|
| 系统语音 | F5 | Win+H | 不需要 |
| Typeless | Fn/Globe 或用户设置 | 第三方实际配置 | 不需要 |
| AhaType | F18，允许修改 | F18，允许修改 | 需要 |
| 自定义语音软件 | 用户配置 | 用户配置 | 不需要 |

### 4.2 固件语义动作

系统语音不保存为固定 F18/F19，而保存为语义动作：

```c
typedef enum {
    ACTION_NONE = 0,
    ACTION_SHORTCUT,
    ACTION_MACRO,
    ACTION_SYSTEM
} action_kind_t;

typedef enum {
    SYSTEM_ACTION_VOICE_INPUT = 1
} system_action_t;
```

`SYSTEM_ACTION_VOICE_INPUT` 在执行时根据有效平台解析：

```text
macOS  -> F5
Windows -> Left GUI + H
Unknown -> 不猜测；显示平台待确认并走兜底流程
```

这样不会给每个键复制两套 100 字节 Mac/Windows 映射，也把未来平台快捷键变化集中在 `InputActionModule`。

### 4.3 Fn/Globe 风险门

当前标准六键 HID 报告能稳定表达 F5、F18、F19 和 Win+H，但不能在未验证前假设可以等价模拟 Apple Fn/Globe。

必须先完成：

- 真实 Apple 键盘 USB 报告抓取。
- 真实 Apple 键盘 BLE HOGP 报告抓取。
- AhaKey 在 macOS 上短按、长按、双击 Fn/Globe 的兼容测试。
- Typeless 对不同触发方式的兼容测试。
- 新 HID 描述符对 Windows 和旧 macOS 的回归。

若不能可靠实现，Typeless 默认回退为标准 HID 键（如 F19），并由用户在 Typeless 内绑定同一快捷键。不得继续依赖 Studio 实时注入 Fn。

## 5. 平台识别设计

### 5.1 平台状态

```c
typedef enum {
    HOST_PLATFORM_UNKNOWN = 0,
    HOST_PLATFORM_MACOS,
    HOST_PLATFORM_WINDOWS
} host_platform_t;

typedef enum {
    PLATFORM_SOURCE_NONE = 0,
    PLATFORM_SOURCE_FACTORY_DEFAULT,
    PLATFORM_SOURCE_BOND_CACHE,
    PLATFORM_SOURCE_USB_PROBE,
    PLATFORM_SOURCE_HOST_HANDSHAKE,
    PLATFORM_SOURCE_USER_OVERRIDE
} platform_source_t;
```

外部接口保持小而稳定：

```c
void host_platform_on_usb_setup(const usb_setup_packet_t *packet);
void host_platform_on_ble_connected(const ble_peer_t *peer);
void host_platform_set_hint(host_platform_t platform);
void host_platform_set_override(host_platform_t platform);
host_platform_state_t host_platform_current(void);
```

判断、置信度、存储、超时和冲突处理全部留在 `HostPlatformModule` 实现内。

### 5.2 解析优先级

```text
用户明确覆盖
  > 当前主机自动 handshake
  > USB 强平台特征
  > 当前 BLE bond 的已学习平台
  > 最近一次可靠平台
  > Unknown
```

### 5.3 现实限制与产品兜底

- Windows USB 枚举时对 Microsoft OS Descriptor `0xEE` 的请求可作为强 Windows 信号。
- 未观察到 `0xEE` 不能直接证明是 macOS，因为主机可能使用缓存。
- 通用 BLE HID 没有可靠的主机操作系统字段。
- 因此“首次纯 BLE 配对、电脑从未运行 AhaKey 软件、仍然 100% 自动识别平台”不能作为可保证指标。

交付行为：

1. USB 强信号优先自动识别。
2. Studio 或 Runtime 存在时连接后自动发送当前系统 hint，不要求用户手工设置。
3. 固件按 BLE bond/peer 保存已学习平台，后续脱离软件继续工作。
4. 平台仍未知时，不发送可能产生副作用的系统语音快捷键。
5. OLED 显示 `Select MAC / WIN`，通过预留按键组合完成一次选择并持久化。
6. Studio 提供 `自动 / macOS / Windows` 覆盖入口和当前来源、置信度。

“不让用户每台电脑都打开 Studio 手工配快捷键”是本阶段可达目标；“蓝牙协议自身可靠暴露操作系统”不是事实，不能写入产品承诺。

## 6. 拨杆自定义快捷键和宏

拨杆有两个正交结果：

1. 状态事件始终上报，供 Runtime 解释自动/手动批准。
2. 固件可在进入某档位时执行一次硬件动作。

```c
typedef struct {
    uint8_t action_kind;
    uint8_t payload_length;
    uint8_t payload[LEVER_ACTION_MAX_LEN];
} lever_action_t;

typedef struct {
    lever_action_t on_enter[3];
} lever_binding_config_t;
```

必须满足以下不变量：

- 仅在 debounce 后稳定进入新档位时执行一次。
- 开机读取初始档位默认不执行动作。
- USB 重新枚举、BLE 重连不触发动作。
- 无论硬件动作是否存在，状态都继续上报 Runtime。
- 快捷键和宏结束时强制 `release all`，避免修饰键卡住。
- 宏执行中再次拨动只保留最新一次待执行动作，不建立无界队列。
- 配置写入中、固件升级中和 OLED 大文件事务中禁止执行拨杆宏。

Studio 中每个档位可独立选择：无动作、快捷键、宏、系统动作。另设独立选项“拨杆控制 AI 自动批准”，两者不能互斥。

## 7. 固件统一与量产变体

### 7.1 统一主线

建议在 GitHub 固件仓库建立 `unified-dev`，验收后合入 `dev`：

```text
firmware/
  APP/
  modules/
    host_platform/
    input_action/
    lever_binding/
    config_store/
    factory_assets/
  products/
    standard/factory-assets.json
    rhino/factory-assets.json
  tests/
  tools/
```

### 7.2 变体规则

Standard 与 Rhino：

- 使用相同源码提交。
- 使用相同协议版本。
- 使用相同 VID/PID、BLE 行为、键位逻辑和运行时状态机，除非生产明确要求不同身份。
- 仅资源 manifest、图片二进制、manifest CRC 和只读 variant ID 可不同。
- 禁止用散落的 `#ifdef RHINO` 分叉业务逻辑。

推荐产物：

```text
AhaKey-X1-unified.hex
factory-standard.bin
factory-rhino.bin
```

若工厂只能烧录一个 HEX，则发布打包阶段合成为：

```text
AhaKey-X1-standard-factory.hex
AhaKey-X1-rhino-factory.hex
```

核心对象只编译一次，两份产物只链接不同资源对象。

### 7.3 移植方式

先建立行为矩阵，再逐项移植并验收：

| 能力 | GitHub dev | Rhino/local | 统一版要求 |
|---|---:|---:|---:|
| SDK bridge | 有 | 缺失 | 保留 |
| 可配置自动关机 | 有 | 部分落后 | 保留 GitHub 新版 |
| 四状态/双套任务图 | 基础 | 完整 | 移植 Rhino |
| 事务化出厂资源 | 缺失 | 有 | 移植 Rhino |
| 图片上传恢复与槽位保护 | 较弱 | 有 | 移植 Rhino |
| USB/BLE 身份与 VBUS 修复 | 部分 | 本地较新 | 以实机结果合并 |
| 平台识别/语义动作 | 无 | 无 | 新增 |
| 拨杆硬件动作 | 无 | 无 | 新增 |

## 8. 固件协议 v4

保留现有 `0x73` 快捷键/宏写入和 `0x99` 能力协商，v4 增加能力位：

```text
supportsHostPlatform
supportsPlatformHint
supportsSystemActions
supportsLeverBindings
supportsTransactionalConfig
supportsFactoryVariant
supportsDualTaskPictureSet
supportsSessionUpload
```

建议使用正式命令空间剩余范围：

```text
0x9A  PLATFORM       读取状态 / 自动 hint / 用户覆盖
0x9B  ACTION_BINDING 读取或写入 key / lever 动作
0x9C  CONFIG_TX      begin / commit / abort
0x9D  CONFIG_READ    分页读取有效配置
```

`0xA0-0xEF` 继续保留给 SDK 用户命令。

`ACTION_BINDING` 使用统一目标寻址：

```text
operation
targetKind: key | lever
mode
targetIndex
actionKind: none | shortcut | macro | system
payloadLength
payload
```

协议设计阶段必须基于实际 BLE 协商包长确定宏分片；不能把当前最大宏直接加头后假设仍能单包发送。

配置提交遵循：

```text
BEGIN_CONFIG
  SET_KEY...
  SET_SYSTEM_ACTION...
  SET_LEVER...
COMMIT_CONFIG
```

断连、校验失败或超时后继续使用上一份完整配置。

## 9. Runtime 架构

### 9.1 不新增第三个后台进程

现有 `ahakeyconfig-agent` 演进为 `AhaKey Runtime`，不同时保留 Agent 和 Runtime 两个常驻实现。

Runtime 内部：

```text
RuntimeOrchestrator
├─ AhaTypeModule
├─ AIIntegrationModule
├─ SessionRoutingModule
├─ DeviceRuntimeModule
├─ PowerProtectionModule
└─ RuntimePolicyStore
```

Runtime 根据策略按需启动：

- 只有系统语音或 Typeless：不启动 Runtime。
- 只有 AhaType：启动快捷键监听、麦克风和转写，不必为此启动 BLE。
- 只有定向会话路由：启动 Hook、会话注册表和相应 target Adapter；最终语音仍可交给系统或第三方软件。
- AI 自动批准或动态灯效：启动 Hook 与 BLE。
- 防休眠：启动防休眠模块。
- 所有增强能力关闭：Runtime 退出。

### 9.2 Studio 与 Runtime seam

详细且具有约束力的 Runtime 规格见 [`ahakey-runtime-architecture.md`](ahakey-runtime-architecture.md)。共享模块提供：

```swift
protocol AhaKeyRuntimeClient {
    func snapshot() async throws -> RuntimeSnapshot
    func events(after sequence: RuntimeEventSequence?) async -> AsyncThrowingStream<RuntimeEvent, Error>
    func apply(_ package: ConfigurationPackage) async throws -> OperationID
    func requestCancellation(of operation: OperationID) async throws -> CancellationDisposition
    func updatePolicy(_ policy: RuntimePolicy) async throws
}
```

生产与测试 Adapter：

- 签名校验的 XPC Adapter：Studio 管理和配置通道。
- 受限 Unix socket Adapter：Hook 状态和拨杆查询，不具备配置权限。
- `InMemoryRuntimeAdapter`：测试。

配置包只描述完整目标状态，不包含 opcode、物理槽位或传输选择。固件、OLED 和图片大文件通过 Runtime 管理的内容寻址存储、长度及 SHA-256 传递，不经 JSON Base64，也不依赖 Studio 临时路径。

### 9.3 签名与权限

最终 Runtime 应包装为稳定签名的 helper application/login item：

- 独立稳定 Bundle ID。
- macOS 13+ 使用 `SMAppService`。
- macOS 12 保留兼容安装路径。
- 麦克风、Speech、Accessibility、Input Monitoring 权限授予 Runtime。
- Studio 仅展示 Runtime 报告的权限状态。
- Runtime 升级必须验证权限不丢失。
- Runtime 是 BLE/USB 唯一所有者；Studio 与旧 Agent 不得在任何生产降级路径中直连设备。

## 9A. 最近待操作会话定向唤起

详细调研见 [`research/openmicrokbd-session-activation.md`](research/openmicrokbd-session-activation.md)。可借鉴的核心不是“窗口魔法”，而是 OpenMicro 的三项结构：hook session identity、可验证 owner、一次输入手势内固定 target lease。

### 9A.1 固件职责

固件不得保存 session id、window id、cwd、thread deep link 或应用进程信息。固件只提供两类路径：

```text
foreground voice action
  -> 直接发送 F5 / Win+H / Fn / 自定义键

targeted voice trigger down/up
  -> Runtime 消费稳定触发事件
```

建议优先复用专用 F18 down/up 作为兼容触发；若 protocol v4 的 vendor event 在 USB/BLE 两条传输上均通过延迟与丢包验证，再升级为：

```text
VOICE_TARGETED down|up, sequence, deviceMode
```

不能让同一次按键同时发送 F5 和 targeted trigger，否则系统会先在错误窗口启动听写。配置为定向模式时，Runtime 不在线应明确提示功能不可用；是否增加前台语音 fallback 需另做有时限的 Runtime lease，不能依赖按键后的临时探测。

### 9A.2 Hook envelope 与 SessionRegistry

Hook 向 Runtime 发送：

```text
protocolVersion
runtimeInstanceId
hookBuildId
client
sessionId
turnId?
event
cwd
occurredAt
toolName?
ownerToken?
targetLocator?
```

不得把 prompt、完整 transcript 或用户文本写入注册表或永久日志。session key 必须包含 client namespace，避免 Codex、Claude、Kimi 的相同字符串碰撞：

```text
AgentSessionKey = client + sessionId
```

Session FSM：

```text
UserPromptSubmit   -> working，清除 awaitingFollowup
PermissionRequest -> awaitingApproval
PostToolUse       -> working
Stop/TaskCompleted-> awaitingFollowup
SessionEnd        -> closed，删除 target
```

`awaitingFollowup` 不使用 OpenMicro 的 8 秒短衰减；它持续到下一次用户提交、显式 dismiss、会话关闭或较长 TTL。

### 9A.3 选择规则与 TargetLease

默认选择：

```text
最近 awaitingApproval
  > 最近 awaitingFollowup
  > lastFocused
  > mostRecentOpen
```

同级按 Runtime 接收的单调 `eventSequence` 排序，墙钟时间只用于诊断。按键 down 时原子选择一次目标并创建：

```text
TargetLease {
  leaseId
  sessionKey
  turnId?
  targetKind
  targetHandle
  acquiredAt
  expiresAt
  generation
}
```

整个按住说话手势使用同一个 lease。期间即使出现更新的批准请求，也只能影响下一次按键。所有延迟动作在执行前重新验证 generation；会话结束、进程退出、用户取消或超时立即 revoke。

### 9A.4 Target Adapter 优先级

`SessionRoutingModule` 只暴露小接口：

```swift
protocol SessionTargetPort {
    func resolve(_ session: AgentSession) async -> SessionTarget?
    func activate(_ target: SessionTarget) async throws -> ActivationReceipt
    func verify(_ receipt: ActivationReceipt) async -> Bool
}
```

生产和测试分别使用真实 Adapter 与 in-memory Adapter。生产 Adapter 按可靠性分层：

1. Codex app 可用的原生 task navigation。
2. 经验证 `hook session_id == thread id` 后的 Codex deep-link Adapter；这是兼容层，升级后必须 smoke test。
3. Runtime 自己启动的 PTY wrapper Adapter；可直接写入正确 PTY，但不保证窗口可见。
4. iTerm2/tmux/kitty/WezTerm 等 Terminal Adapter，注册并保存 pane/window token。
5. 只有 cwd 而无可验证 locator 时，不做精确注入；相同 cwd 可以存在多个会话。

第一版不把 PTY wrapper 作为前置条件：先交付 Codex App 精确唤起，再逐个增加终端 Adapter。若产品要求所有终端都具备强保证，再把可选 wrapper 做成后续批次。

### 9A.5 语音 handoff

```text
hardware down
  -> selectTarget + acquireLease
  -> resolve + activate target
  -> verify frontmost target/composer
  -> system/third-party voice trigger 或 AhaType start

hardware up
  -> system/third-party voice release 或 AhaType stop/finalize
  -> revalidate lease
  -> AhaType 安全注入，或结束外部语音手势
  -> releaseLease
```

默认只把 AhaType 文本填入输入框，不自动提交。语音键不承担批准动作；拨杆自动批准继续由 `PermissionRequest` hook policy 独立决定。

目标在录音中关闭或验证失败时，AhaType transcript 进入安全草稿，不粘贴到当前前台应用。系统/第三方语音路径在启动前验证失败则不触发快捷键。

### 9A.6 Hook/Runtime 升级

- Hook 结构化 merge，只管理带 AhaKey marker 的配置，不删除第三方 Hook。
- Runtime 接受当前与前一版 hook envelope。
- Hook fail-open/no-op；Runtime 不在线时快速退出，不阻塞 AI 工具。
- Runtime 更新先安装兼容 Hook，health-check 成功后切换；保留上一 helper 回滚。
- SessionRegistry 是临时运行态，不进入固件；崩溃恢复后由新事件重建。
- 永久诊断只记录 event、session hash、target kind、lease result、activation latency 和 inject result。

## 10. Studio 改动

### 10.1 模型

- 将 `VoicePreset` 拆成 `VoiceActivationTarget` 与 `ActionBinding`。
- `AhaType` 是唯一需要语音 Runtime 的目标。
- 增加 `HostPlatformState`、`PlatformOverride`、`LeverBindingDraft`。
- 旧模型仅保留解码迁移，不继续扩展。

### 10.2 界面

语音配置展示：

```text
系统语音输入
  当前平台：macOS
  实际发送：F5
  需要 Runtime：否

Typeless
  实际发送：Fn/Globe（或 F19）
  需要 Runtime：否

AhaType
  实际发送：F18
  需要 Runtime：是
```

新增：

- 平台 `自动 / macOS / Windows`。
- 检测来源和置信度。
- 拨杆上/中/下三档动作编辑。
- “拨杆控制 AI 自动批准”独立选项。
- 保存前展示退出 Studio 后的可用性。
- Runtime 设置页展示保持运行的具体原因。

### 10.3 启动行为

- 移除 Studio 启动时无条件启动 `VoiceRelayService` 和 `NativeSpeechTranscriptionService`。
- 系统语音与第三方语音不安装 Event Tap。
- AhaType 监听由 Runtime 启动。
- Studio 关闭后停止所有动画、诊断日志观察和非必要 UI 发布。

## 11. BLE 与 CPU 约束

继续执行已经确认的性能规则：

- 后台设备状态轮询保持 1.5 秒，目标响应不超过 2 秒。
- 周期性和连接生命周期设备状态全部经过 reducer。
- 单一 `DeviceStatusSnapshot` 为设备状态事实来源。
- 相同状态每轮零 UI 发布、零常规磁盘日志。
- Agent/AhaType 自身状态保持独立来源。
- RSSI 不进入主快照，只在设备信息窗口打开时轮询并写诊断 Store。
- `BLELogStore` 最多保留 200 条，仅诊断窗口观察。
- 原始 TX/RX 只在用户主动开启后记录，15 分钟自动关闭。
- 日志后台串行写入，单文件 5 MB，保留 3 份。
- 隐藏窗口暂停持续动画和诊断观察；真实设备状态变化允许发布一次。
- Studio 关闭后，已启用的 AI 检测、防休眠、AhaType 和后台 BLE 能力继续工作。

目标门槛：

| 场景 | 指标 |
|---|---:|
| Runtime 连接键盘空闲 CPU | `< 0.5%` 平均值 |
| Runtime 未连接键盘空闲 CPU | `< 0.2%` 平均值 |
| 设备状态/拨杆响应 | `<= 2s` |
| 相同状态 UI 发布 | 0 |
| 正常轮询磁盘日志 | 0 |
| 隐藏窗口持续动画 | 0 |

## 12. 兼容与迁移

### 12.1 旧设备

- 升级固件不静默改写已有 F18/F19。
- 新出厂或恢复出厂使用 `SYSTEM_ACTION_VOICE_INPUT`。
- Studio 检测到旧版默认 F18 时提示一键升级为自动平台系统语音。
- 用户明确配置过的 F18/F19 保持不变。
- 旧 `.typeless` 若依赖 Studio Fn relay，迁移界面明确询问采用 Fn/Globe 还是保留 F19。
- AhaType 旧触发键迁移到 `AhaTypeActivationPolicy`。

### 12.2 协议兼容

- 新 Studio + 旧固件：隐藏平台语义动作和拨杆硬件动作。
- 旧 Studio + 新固件：旧 `0x73` 快捷键和宏继续工作。
- 未识别协议版本：只允许经过验证的基础能力，不猜测支持新命令。
- protocol v4 上线至少保留一个正式版本周期的旧配置解码。

### 12.3 回滚

- 固件配置 schema 保留前一版本读取和回滚槽。
- 配置事务失败不替换 active config。
- Runtime policy、事务和事件游标使用带 schema version 的 SQLite WAL；大资源使用内容寻址文件目录。
- 灰度期间保留旧 Agent 安装恢复脚本，但不得同时运行。
- 每个发布包记录固件、Studio、Runtime、资源 manifest 的兼容矩阵。

## 13. WBS

工作量使用“人日”估算，不包含审批、采购和工厂排队。建议配置：1 名固件主责、1 名 macOS 主责、1 名 Windows/协议主责、1 名 QA/硬件测试；多人可并行但每个 Module 保持单一主责。

### WBS 0：基线冻结与风险验证（10-15 人日）

| ID | 工作包 | 产物 | 依赖 |
|---|---|---|---|
| 0.1 | 冻结 GitHub dev、Gitee Rhino、本地 Rhino 提交 | 三方基线清单 | 无 |
| 0.2 | 建立行为/协议/Flash 布局差异矩阵 | parity matrix | 0.1 |
| 0.3 | 抓取 macOS F5、Fn/Globe USB/BLE HID 报告 | 抓包和结论 | 硬件 |
| 0.4 | Windows USB `0xEE` 与枚举缓存验证 | 平台识别报告 | 硬件 |
| 0.5 | BLE 首次连接识别验证 | 明确不可达项与兜底 | 硬件 |
| 0.6 | 冻结 protocol v4 与 EEPROM/Flash 预算 | 协议 ADR | 0.2-0.5 |
| 0.7 | 验证 Codex hook session id、桌面 thread id 与可导航目标的 join | 会话定向可行性报告 | 现行 Codex App |

退出条件：Fn/Globe 路线、平台未知行为、统一主线、协议内存预算和首个精确会话 Adapter 全部有明确决定。

### WBS 1：统一固件基线（15-22 人日）

| ID | 工作包 | 产物 | 依赖 |
|---|---|---|---|
| 1.1 | 建立 unified-dev 与可重复工具链 | CI 可构建固件 | 0.1 |
| 1.2 | 保留 GitHub SDK bridge/自动关机 | 基线能力测试 | 1.1 |
| 1.3 | 移植 Rhino 四状态和双套任务图 | 统一 OLED 状态机 | 1.2 |
| 1.4 | 移植事务化 factory assets | 资源模块 | 1.2 |
| 1.5 | 移植图片上传恢复和槽位保护 | 上传 HIL 测试 | 1.3-1.4 |
| 1.6 | 合并 USB/BLE 身份与 VBUS 修复 | 传输回归报告 | 1.2 |
| 1.7 | 建立 Standard/Rhino 两份资源 pack | 两个量产产物 | 1.4 |

退出条件：同一源码在两种资源变体上通过现有功能回归，除资源外行为一致。

### WBS 2：平台与系统语音（12-18 人日）

| ID | 工作包 | 产物 | 依赖 |
|---|---|---|---|
| 2.1 | 实现 HostPlatformModule | 平台状态机测试 | 0.6、1.6 |
| 2.2 | 实现 USB 平台 probe | Windows 强信号 | 2.1 |
| 2.3 | 实现 host hint、用户覆盖和 bond cache | BLE 学习能力 | 2.1 |
| 2.4 | 实现 InputActionModule | 统一动作执行器 | 0.6 |
| 2.5 | 实现系统语音语义动作 | F5 / Win+H | 2.1、2.4 |
| 2.6 | 实现 Fn/Globe 或 F19 fallback | 第三方语音模板 | 0.3、2.4 |
| 2.7 | OLED 平台未知选择流程 | 无软件兜底 | 2.1 |
| 2.8 | protocol v4 capabilities/platform/action | 固件协议实现 | 0.6、2.1-2.6 |

退出条件：USB 和已学习 BLE 主机在无 Studio/Runtime 时可正确触发系统语音；Unknown 不误发。

### WBS 3：拨杆硬件动作（8-12 人日）

| ID | 工作包 | 产物 | 依赖 |
|---|---|---|---|
| 3.1 | 实现 LeverBindingModule | 三档配置模型 | 2.4 |
| 3.2 | edge/debounce/开机抑制 | 稳定状态机 | 3.1 |
| 3.3 | 快捷键/宏执行与 release-all | 动作执行 | 3.1 |
| 3.4 | 宏重入、上传/升级互锁 | 安全策略 | 3.2-3.3 |
| 3.5 | protocol v4 拨杆读写 | 客户端可配置 | 2.8、3.1 |
| 3.6 | 保留 Runtime 状态通知 | 自动批准不回退 | 3.2 |

退出条件：500 次快速拨动无重复动作、卡键或丢失状态；Runtime 开关不影响硬件动作。

### WBS 4：Studio 模型与界面（15-22 人日）

| ID | 工作包 | 产物 | 依赖 |
|---|---|---|---|
| 4.1 | Shared 增加 v4 模型与编解码 | Swift 协议模型 | 0.6、2.8 |
| 4.2 | VoicePreset 兼容迁移 | 新语音模型 | 4.1 |
| 4.3 | 系统/Typeless/AhaType 配置 UI | 新语音编辑器 | 4.2 |
| 4.4 | 平台状态、来源和覆盖 UI | 平台面板 | 4.1 |
| 4.5 | 拨杆三档快捷键/宏 UI | 拨杆编辑器 | 3.5、4.1 |
| 4.6 | 配置事务和失败回滚 | 保存流程 | 4.1 |
| 4.7 | Windows Studio 协议与 UI 对齐 | Windows 支持 | 4.1-4.6 |
| 4.8 | 旧配置迁移和提示 | 升级体验 | 4.2 |

退出条件：macOS/Windows 都能配置统一固件；能力显示由 `0x99` 决定；旧固件 UI 自动降级。

### WBS 5：Runtime 解耦与唯一设备所有权（35-55 人日）

| ID | 工作包 | 产物 | 依赖 |
|---|---|---|---|
| 5.0 | **已完成**：冻结 RuntimePolicy、Snapshot、Event、ConfigurationPackage 与 revision 语义 | R0 interface v1.1 | 无 |
| 5.1 | **已完成**：SQLite WAL journal、内容寻址资源仓库、配额与崩溃恢复 | 持久事务内核 | 5.0 |
| 5.2 | 签名 XPC、受限 framed hook socket、握手与事件重放 | 生产 seam | 5.0-5.1 |
| 5.3 | Agent 演进为 RuntimeOrchestrator，迁移 AhaType、AI Hook/批准、灯效与防休眠 | 单一后台进程 | 5.2 |
| 5.4 | 按策略启停模块；区分前台纯硬件语音、AhaType 与定向路由 | 生命周期测试 | 5.3 |
| 5.5 | BLE/USB、current-only 协商、设备身份、命令队列、waiter 与断线恢复迁入 Runtime | 唯一设备 owner | 5.1-5.3 |
| 5.6 | 声明式配置规划、图片/基础配置事务、取消与恢复 | 可恢复配置事务 | 5.5、4.1 |
| 5.7 | Studio 接入 snapshot/event/operation UI，并删除生产直连 BLE/USB | Studio 纯客户端 | 5.2、5.6 |
| 5.8 | 删除 Studio 无条件语音启动，验证纯硬件路径零监听 | 纯硬件路径零 Runtime | 5.4、4.3 |
| 5.9 | 旧 Agent 清理、签名 helper、Keychain/权限/安装迁移与原子更新 | 正式 Runtime 安装链 | 5.3-5.8 |
| 5.10 | macOS interface 的跨平台语义抽象与 Windows Adapter 方案 | 跨平台 seam 决定 | 5.0、4.7 |

退出条件：Runtime 是生产环境唯一设备 owner；Studio 完全退出后增强功能和已受理事务继续；纯硬件配置时 Runtime 不常驻；配置、崩溃恢复、权限升级和旧 Agent 清理均通过实机验证。WBS 5.0-5.1 已完成；必须继续完成 5.2-5.3，不能跳到 5.5 或 5.7。

### WBS 5A：最近待操作会话定向（18-29 人日）

| ID | 工作包 | 产物 | 依赖 |
|---|---|---|---|
| 5A.1 | Hook envelope 增加 session/turn/client/owner | v2 Hook 事件 | 5.1、5.4 |
| 5A.2 | SessionRegistry 与 FSM | 会话状态测试 | 5A.1 |
| 5A.3 | SessionSelector 与 TargetLease | 选择/租约测试 | 5A.2 |
| 5A.4 | 固化 Codex App session/thread join 与升级 smoke test | 可行性报告/自动测试 | 0.7、5A.1 |
| 5A.5 | Codex App navigation/deep-link Adapter | 首个精确目标 Adapter | 5A.3-5A.4 |
| 5A.6 | 目标激活、焦点和 composer 验证 | ActivationReceipt | 5A.5 |
| 5A.7 | 系统/第三方/AhaType voice handoff | 定向语音链 | 5.3、5A.6 |
| 5A.8 | 安全草稿、取消、TTL、崩溃恢复 | 失败保护 | 5A.3、5A.7 |
| 5A.9 | iTerm2/tmux 首批 Terminal Adapter | 终端 beta | 5A.3 |
| 5A.10 | Hook N/N-1 与 Runtime 更新回滚 | 兼容测试 | 5.7、5A.1 |
| 5A.11 | 隐私化诊断与性能指标 | session hash/latency | 5A.2-5A.8 |

退出条件：两个相同 cwd 会话不会串线；一次语音手势目标不漂移；Codex App 目标关闭、deep link 失效或权限不足时不向错误窗口注入。PTY wrapper 不阻塞此批次，可作为后续增强。

### WBS 6：性能、灰度与量产（14-21 人日）

| ID | 工作包 | 产物 | 依赖 |
|---|---|---|---|
| 6.1 | reducer/日志/隐藏 UI 性能门禁 | 性能报告 | WBS 4-5 |
| 6.2 | Mac/Windows × USB/BLE HIL 矩阵 | 硬件测试报告 | WBS 1-5 |
| 6.3 | Standard/Rhino 量产一致性校验 | 二进制差异报告 | WBS 1 |
| 6.4 | 升级、降级、断电和断连测试 | 恢复报告 | WBS 1-5 |
| 6.4A | 多会话选择、lease 与错误目标注入测试 | 会话路由报告 | WBS 5A |
| 6.5 | 基础版本内测 10 台 | 阻断问题清单 | 6.1-6.4 |
| 6.6 | 灰度 50 台 | 遥测与客服反馈 | 6.5 |
| 6.7 | 正式发布与工厂切换 | 签名安装包/固件包 | 6.6 |

退出条件：基础版本性能、功能、升级和量产门禁全部通过，无 P0/P1 缺陷。WBS 5A 使用 6.4A 独立验收，不能反向阻塞基础版本。

## 14. 分批交付节奏

以下日历按“1 固件 + 1 macOS + 1 Windows/协议 + 1 QA”并行估算；若只有 1-2 名工程师，应以人日为准，整体周期约增加 50%-100%。

完整范围总工作量约 127-194 人日。日历周期不能直接用总人日除以人数，因为固件硬件验证、Runtime 设备接管、签名权限、会话 join 和灰度发布存在顺序门禁。

### 批次 A：技术风险关闭，1 周

范围：WBS 0。

可交付：

- 三套固件差异矩阵。
- Fn/Globe 可行性结论。
- USB/BLE 平台识别边界。
- protocol v4 草案。
- Flash/EEPROM/RAM 预算。
- Codex hook session id 与桌面 thread/目标 locator 的 join 结论。

此批次不发给用户。未通过不得开始量产功能开发。

### 批次 B：统一固件基线，2-3 周

范围：WBS 1。

可交付：

- Standard/Rhino 共用源码的内部固件。
- 两套出厂资源包。
- Rhino 功能与 GitHub 新能力 parity 报告。
- USB/BLE 基础回归。

此批次可给内部硬件团队，不给普通用户升级。

### 批次 C：纯硬件语音与平台学习，2 周

范围：WBS 2 + Studio 最小平台 UI。

可交付：

- macOS F5、Windows Win+H 系统语音。
- Typeless Fn/Globe 或 F19 fallback。
- USB 自动识别、host hint、BLE 平台学习。
- 平台未知设备端兜底。
- protocol v4 beta。

此批次进入 10 台 Alpha。验收重点是“Studio 退出后仍可用”。

### 批次 D：拨杆快捷键/宏，1-2 周

范围：WBS 3 + Studio 拨杆 UI。

可交付：

- 上/中/下三档动作。
- 快捷键、宏、无动作、系统动作。
- AI 自动/手动批准语义继续独立工作。
- 快速拨动与卡键压力报告。

可以与批次 C 后半段并行，但不能早于 `InputActionModule` 稳定。

### 批次 E1：Runtime 与 Studio 解耦，5-7 周

范围：WBS 4 余项 + WBS 5。

可交付：

- 系统/第三方语音完全脱离 Studio/Runtime。
- AhaType 由正式 Runtime 提供。
- AI 检测、自动批准、动态灯效、防休眠在 Studio 退出后继续。
- 未启用增强功能时 Runtime 不运行。
- 签名 helper 和权限升级路径。

此批次先进入 20 台 Beta。统一固件、纯硬件语音和拨杆可以在此前作为内部固件验证，但包含新配置 UI 的公开客户端不得绕过 Runtime 唯一设备所有权门禁。会话定向不阻塞此批次。

### 批次 E2：最近待操作会话定向，2-3 周

范围：WBS 5A。

可交付：

- Hook session/turn/client envelope。
- `awaitingApproval / awaitingFollowup / working` 会话状态机。
- 最近待批准优先的 SessionSelector。
- 一次语音手势固定的 TargetLease。
- Codex App 精确会话唤起和升级 smoke test。
- 系统听写、第三方语音与 AhaType 三种执行目标的定向 handoff。
- 目标失效后的安全草稿和禁止误注入。
- iTerm2/tmux 首批 Terminal Adapter beta。

此批次进入 30-50 台定向会话 Beta。Codex App Adapter 达到发布门槛后即可发版；可选 PTY wrapper 放入后续增强，不阻塞首发。

### 批次 F：性能与正式量产，2 周

范围：WBS 6。

可交付：

- CPU/RAM/日志/响应性能报告。
- 基础版本完整 HIL；会话定向批次另附多会话路由回归。
- Standard/Rhino 两套正式量产包。
- macOS 签名 DMG、Windows 安装包、固件升级包。
- 回滚包和客服排障文档。

预计基础正式版（不含会话定向）并行团队总日历：12-15 周；完整范围含会话定向约 14-18 周。串行小团队按 20-28 周规划。

若拆成产品版本：

```text
Internal Alpha（第 5-8 周，不公开发布新客户端）
  统一固件 + 纯硬件跨平台语音 + 拨杆快捷键/宏

Release 1（第 12-15 周）
  Internal Alpha 能力 + Runtime 唯一设备所有权 + Studio 纯客户端
  + AhaType + AI/防休眠后台持续运行 + 性能/签名/灰度门禁

Release 2（再 2-3 周）
  最近待操作会话定向 + Codex App Adapter + 首批终端 Adapter
```

Release 2 不能反向阻塞 Release 1；会话定向属于 Runtime 增强能力，不改变基础语音的纯硬件承诺。

## 15. 发布门禁与验收矩阵

### 15.1 纯硬件语音

- macOS + USB：F5 系统听写，无 Studio/Runtime。
- macOS + BLE：已学习平台后 F5，无 Studio/Runtime。
- Windows + USB：Win+H，无 Studio/Runtime。
- Windows + BLE：已学习平台后 Win+H，无 Studio/Runtime。
- Typeless：按最终验证模板触发，无 AhaKey Runtime。
- AhaType：Studio 退出、Runtime 运行时完整录音/转写/整理/输入。

### 15.2 平台切换

- 同一设备从 Mac 切到 Windows。
- 同一设备从 Windows 切到 Mac。
- USB 与 BLE 交替。
- 多个 BLE bond 使用不同平台。
- Windows 枚举缓存命中与未命中。
- 平台 Unknown 不误发。
- 用户覆盖后自动信号不得偷偷覆盖。

### 15.3 拨杆

- 三档各 500 次切换。
- 快速越过中档。
- 宏执行中再次切换。
- 断连/重连、开机、睡眠恢复。
- 配置/升级事务中切换。
- Runtime 开启和关闭两种状态。

### 15.4 固件与资源

- Standard/Rhino 两种出厂资源。
- 出厂恢复后默认配置正确。
- 图片上传中断、断电、重连恢复。
- 旧配置升级不丢键位和宏。
- 新旧 Studio/固件交叉兼容。
- Flash 越界、CRC 错误和错误资源包拒绝。

### 15.5 Runtime 性能

- 使用真实键盘连接测试，不接受无设备空跑作为唯一性能证据。
- 连接、断开、反复重连至少 8 小时。
- Studio 隐藏与完全退出分别采样。
- 1.5 秒轮询不产生相同状态 UI 发布和常规日志。
- AhaType、AI Hook、防休眠组合开启时分别测量和叠加测量。

### 15.6 会话定向

- 两个相同 cwd 的会话分别触发批准，选择最新批准而不是按 cwd 猜测。
- A 完成待下一步、B 请求批准时选择 B；B 处理后 A 仍可被选择。
- 按住语音期间出现新的批准请求，当前 TargetLease 不漂移。
- 目标在录音中关闭时不向当前前台应用粘贴，AhaType 文本进入安全草稿。
- Codex thread/deep-link contract 升级失效时自动降级并停止注入。
- Runtime 不在线时，foreground 系统语音仍由固件工作；targeted 模式明确提示不可用。
- Accessibility、Speech 权限缺失时不启动录音、不夺焦点、不粘贴。
- Hook 与 Runtime N/N-1 混合升级不阻塞 AI 工具，不删除第三方 Hook。

## 16. 关键风险与应对

| 风险 | 影响 | 应对 |
|---|---|---|
| BLE 无可靠 OS 标识 | 首次纯 BLE 无法全自动 | handshake + bond cache + 设备端一次选择 |
| Fn/Globe 非标准或双传输不一致 | Typeless 默认失效 | 先抓包；失败则使用 F19 fallback |
| 合并固件导致稳定性修复丢失 | 量产故障 | 行为矩阵 + 逐项移植 + HIL 门禁 |
| `key_bund_s` 扩展超 EEPROM | 保存失败/损坏 | WBS 0 冻结预算；语义动作避免双倍键表 |
| 配置中断形成半套状态 | 键位混乱 | 双槽/事务化 config store |
| Runtime 权限迁移失败 | AhaType 不可用 | 稳定签名身份 + 升级实测 + 回滚 |
| 新旧客户端错误写新命令 | 配置损坏 | `0x99` 能力门禁 + restricted unknown |
| 拨杆宏与自动批准耦合 | 用户功能冲突 | 状态事件与硬件动作正交设计 |
| Runtime 空转造成 CPU 投诉 | 用户不愿常驻 | 策略化模块启停 + 性能发布门禁 |
| hook session id 无法可靠关联 GUI thread | 打开错误会话 | 上线前验证 join；失败只激活应用并停止注入 |
| 固定 sleep 后模拟按键 | 慢机器或动画期间串线 | ActivationReceipt + frontmost/composer 验证 |
| 录音中出现更高优先级批准 | 文本目标漂移 | 一次手势固定 TargetLease |
| 终端只有 cwd 无 pane locator | 同目录多会话串线 | 要求注册 pane token 或 PTY owner；否则不精确注入 |

## 17. 建议的项目里程碑

```text
M0  技术风险关闭
M1  统一固件 parity
M2  纯硬件跨平台语音
M3  拨杆快捷键/宏
M4  Runtime/Studio 解耦
M5  最近待操作会话定向
M6  性能与量产发布
```

每个里程碑都必须有可烧录固件、配套客户端、测试报告和回滚产物；不能只以代码合并作为完成标准。

## 18. 最终产品表述

对用户的统一说明应为：

> AhaKey Studio 只用于配置。普通快捷键、宏、系统语音输入、Typeless 和拨杆硬件动作由键盘独立完成；AhaType、AI 自动批准、最近待操作会话定向、动态状态灯和防休眠等增强能力由轻量 AhaKey Runtime 在后台提供。关闭 Studio 不会影响已启用的能力，不使用增强能力时也无需运行 Runtime。
