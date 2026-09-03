# AhaKey 统一固件、纯硬件语音与 Runtime 解耦实施计划

状态：统一调度基线；采用 0.2 → 0.3 → 0.4 → 0.5 → 1.0 → 1.1 分批发布；Runtime 设备所有权决策已确认

日期：2026-08-22（发布列车拆分更新 2026-08-29）
适用范围：AhaKey X1 固件、macOS Studio、Windows Studio、后台 Runtime、生产烧录与发布流程

## 0. 文档权威、当前进度与单一实施入口

本文档是固件、Studio、Runtime、AhaType、AI Hooks 与会话定向的唯一总实施计划。专题文档的关系如下：

| 文档 | 定位 | 约束 |
|---|---|---|
| 本文档 | 产品范围、依赖、WBS、批次与发布门禁 | 发生冲突时决定交付顺序与范围 |
| [`runtime-v0.2-collaboration-brief.md`](runtime-v0.2-collaboration-brief.md) | Runtime 改动与 v0.2 协作者导读 | 便于交接，不替代本文、架构规格或任务卡 |
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
| Runtime 持久化测试 | 14 项契约测试、12 项持久化集成测试；完整 Swift 套件 197 项通过 | 作为后续兼容与崩溃恢复基线 |
| SQLite WAL、资源仓库 | WBS 5.1 已完成 | 生产 Runtime 接入前保持为独立持久事务内核 |
| XPC、Hook socket | WBS 5.2 accepted @ `1ac1524`；libxpc 签名 server 与双进程 smoke 已通过 | 作为 v0.2 稳定生产 seam，不再列为开放前置 |
| Runtime 设备独占、Studio 纯客户端化 | WBS 5.5/5.7 静态与自动门禁完成 | 主链已 accepted；0.2 先经兼容策略、最小安装链与独立 HIL 发布，不再等待全部新功能 |
| OpenMicro 会话唤起研究 | 已完成 | 延后到核心 Runtime 稳定后的 WBS 5A |
| WBS 0.1 基线冻结 | 已完成 | 见 [`firmware-client-baseline-2026-08-22.md`](firmware-client-baseline-2026-08-22.md)；2026-08-26 确认 GitHub **`master@71b11676` 与 `dev@3e7f900` 源码树相同** |
| WBS 1 统一固件 | 进行中 | 1.1-1.4 已验收；1.5 implementation accepted @ `b678137`，真机 HIL 延后到 1.7 可刷镜像；当前 Zcode 执行 1.6 checkpoint A，1.7 未开放。**产品源仍为 GitHub master/dev 同树**，不换到 `eternal-dev`。 |
| OLED 编辑/局部提交 | 客户端底层已通过差分 HIL，正式 UI 待验 | Gitee Rhino 上 Runtime 专用驱动已完成 B-only `5/5`、`102400/102400`、A 保留与 A/B 断电保持；v0.3 改为独立客户端兼容列车，不等待统一固件 |
| WBS 0.2 行为/协议/Flash 矩阵 | 部分完成 | 行为与协议入口已静态比较；Flash 地址、大小、占用和 HIL 仍开放 |

### 0.1 产品版本列车（2026-08-29 冻结）

版本号描述的是**可交付产品能力**，不等同于某一张 WBS 是否全部完成；正文中的产品版本可读作 `v0.2` 等，以区别 WBS `0.2` 这类工作包编号。后续功能不得反向阻塞前一版本，前一版本也不得以隐藏按钮掩盖未经验证的写入路径。

| 版本 | 面向用户的交付 | 必须完成 | 明确不包含 |
|---|---|---|---|
| **v0.2/v0.2.1 可用客户端 Beta** | macOS Studio + 轻量 Runtime；AI Hook 自动/手动批准、后台设备检测、防休眠、连接状态；经兼容门控验证后的基础键位/灯效配置；正式签名 DMG；v0.2.1 收口 BLE 唤醒与 legacy socket 生存性 | 已验收 Runtime 主链；`RELEASE-0.2-COMPATIBILITY`；WBS 5.9A；`HIL-RELEASE-0.2`；`HIL-RELEASE-0.2.1` | OLED/任务图写入、统一固件、跨平台语音、拨杆宏、Windows、会话定向 |
| **v0.3 客户端 OLED 兼容版** | 对外发布的重构后 macOS 客户端；正式 Studio UI 经 Runtime 按当前编辑页 dirty-only 写入；每页独立 operation/FIFO/断连续传/三级 baseline；兼容已登记的 GitHub Standard、Gitee Rhino、Local Rhino 旧固件；字节进度与 A/B 写入并激活 | 最终 v0.2.1；`V03-STUDIO-OLED-LEGACY-COMPATIBILITY` C1-C4；`HIL-V03-STUDIO-OLED-COMPATIBILITY` C5；`HIL-RELEASE-0.3` | 统一固件刷写、客户端自动补齐出厂默认、键盘端旧固件进度修复、平台语音、拨杆宏、Windows、会话定向 |
| **v0.4 统一固件与平台快捷键** | 完成统一固件基线，并按 macOS/Windows/已学习平台发送不同系统语音快捷键；基础语音无需 Runtime | WBS 1、WBS 2、WBS 4.1-4.4、WBS 5.8、`HIL-RELEASE-0.4` | 拨杆自定义宏、Windows Studio 完整对齐、会话定向 |
| **v0.5 拨杆快捷键/宏** | 三档自定义快捷键、宏、互锁与 Runtime 状态正交 | WBS 3、WBS 4.5、`HIL-RELEASE-0.5` | Windows 正式客户端、完整量产资格、会话定向 |
| **v1.0 正式统一版** | macOS/Windows 对齐、完整迁移/升级/降级、性能与量产门禁、正式包 | WBS 4.6-4.8、5.10、5.9B、WBS 6.1-6.7（不含 6.4A） | 最近待操作会话定向 |
| **v1.1 会话定向** | Codex App 精确会话唤起、TargetLease、安全草稿、首批 Terminal Adapter | WBS 5A、`HIL-RELEASE-1.1` | 可选 PTY wrapper 等后续增强 |

发布纪律：每个版本都维护自己的功能开关、兼容矩阵、HIL 证据、安装/回滚包和已知限制；禁止在 v0.2/v0.2.1 包中暴露 v0.3 的 OLED 写入口，也禁止为了赶版本恢复 Studio 直连 BLE。v0.3 的“兼容全部旧固件”限定为已登记并有冻结 SHA/HEX 的历史固件族；未知固件只读或明确拒绝。统一固件和平台快捷键不得反向阻塞 v0.3 客户端发布。

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

GitHub 公开产品源是 [`AhaKey-X1-hardware-source/master`](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/tree/master) @ `71b11676c4ebc8ff5b4885a24b601cb9cc04aa67`（2026-08-14 将 `dev` 合入 `master`）。**该提交的 tree 与 `dev@3e7f900ae6f5fe71d57a03da973d79356afea1b6` 字节级相同**（`git diff 3e7f900 origin/master` 为空）。WBS 0.1 冻结的 `3e7f900` 因此仍是正确的 `git archive` 产品基线；不必为“追上线上 master”再做一次源码 rebase。

该树包括有线 HID、AI 状态（`0x90–0x94`）、拨杆上报、可配置自动关机（`0x86`）和默认关闭的 SDK bridge；默认录音键仍为 F18。没有 Rhino 的 `factory_assets`，也没有 `0x95–0x99`。

独立统一仓 `cursor/wbs-1-unified-firmware` 以该树为祖先，只叠加：可重复 macOS 工具链/Flash 门禁，以及 1.2 的 `auto_power_off` 共用策略模块（opcode 仍为 `0x86`）。不得把未合入 `master` 的 `eternal-dev`（protocol 3 / 重编号 `0x95–0x9F`）或 `port-pr2-safe-effects`（删除 SDK bridge）当作线上产品源。

Gitee/Rhino 定制版及本地 Rhino 后续包含：

- 四状态 OLED 与双套任务 GIF。
- 事务化出厂资源和资源 manifest。
- 图片槽位保护、上传恢复和更可靠的写入确认。
- LCD/SPI 超时保护。
- macOS USB 枚举、USB/BLE 身份与 VBUS 切换修复。
- 强制关机等真实硬件稳定性修复。

整合结论：

- GitHub **`master`（树 ≡ `dev@3e7f900`）** 作为统一主线产品源。独立仓分支 `cursor/wbs-1-unified-firmware` 是当前 `unified-dev`。
- Rhino 能力按行为逐项移植到该树上，不做目录级盲目合并，也不先换成 `eternal-dev`。
- SDK bridge（default-off / internal-enable）与 `0x86` 自动关机等 GitHub 已发布能力不得丢失。
- Rhino 稳定性、资源和上传能力不得回退。
- Standard 与 Rhino 只允许出厂资源不同，不允许长期形成两套业务代码。
- `eternal-dev` 的 protocol 3 把 `0x95–0x9F` 用于待机/任务槽/配置读取，与本计划 v4（Rhino 任务图 `0x95–0x99` + 平台/事务 `0x9C–0x9F`）冲突；合入前必须单独 ADR，不能当“更新的 master”。

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

公开合入目标是 GitHub `master`（当前与 `dev` 同树）。施工在独立仓 `cursor/wbs-1-unified-firmware`（unified-dev），验收后再考虑回推 `dev`/`master`；未授权不得 push 远端。

目录目标不变：

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

| 能力 | GitHub master/dev 同树 | Rhino/local | 统一版要求 |
|---|---|---|---|
| SDK bridge | 有（default-off） | 缺失 | 保留；1.2 仅 internal enable，不宣称公共 SDK |
| 可配置自动关机 | `0x86` | 部分落后 | 保留 GitHub 号与语义；1.2R1 共用 policy 模块 |
| 四状态/双套任务图 | 基础 `0x93/0x94` | 完整 `0x95–0x98` | 移植 Rhino（1.3），勿用 eternal-dev 的 `0x95` 待机语义 |
| 事务化出厂资源 | 缺失 | 有 | 移植 Rhino（1.4） |
| 图片上传恢复与槽位保护 | 较弱 | 有 | 移植 Rhino（1.5） |
| USB/BLE 身份与 VBUS 修复 | 部分 | 本地较新 | 以实机结果合并（1.6） |
| 平台识别/语义动作 | 无 | 无 | 新增（WBS 2） |
| 拨杆硬件动作 | 无 | 无 | 新增（WBS 3） |

## 8. 固件协议 v4

保留现有 `0x73` 快捷键/宏写入；从 Rhino 移植并冻结 `0x95-0x99`（任务图绑定/查询/激活/完成/能力协商），v4 增加能力位：

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

正式命令空间冻结如下。现有客户端已经使用 `0x9A/0x9B` 做会话化资源上传，禁止再分配给平台或动作：

```text
0x84  LIGHT_MAPPING       AI 状态灯效映射（既有）
0x85  BRIGHTNESS          亮度（既有）
0x86  AUTO_POWER_OFF      自动关机（既有）
0x95  TASK_PICTURE_BIND   mode/set/state/start/count/interval（Rhino/current）
0x96  TASK_PICTURE_QUERY  查询任务图绑定
0x97  ACTIVE_PICTURE_SET  激活套图
0x98  PICTURE_WRITE_END   完成任务图写入
0x99  CAPABILITIES        能力与 factory 状态
0x9A  SESSION_ABORT       中止会话化资源写入（current）
0x9B  SESSION_PREPARE     准备会话化资源写入（current）
0x9C  PLATFORM            读取状态 / 自动 hint / 用户覆盖（v4）
0x9D  ACTION_BINDING      读取或写入 key / lever 动作（v4）
0x9E  CONFIG_TX           begin / commit / abort（v4）
0x9F  CONFIG_READ         分页读取有效配置（v4）
```

`0xA0-0xEF` 继续保留给 SDK 用户命令。

`eternal-dev` 上的 protocol 3 占用 `0x95–0x9F` 做待机/任务槽/配置读取，**未合入 master**。v4 冻结前禁止从该分支 cherry-pick 命令号。

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
| 1.1 | **已验收 @ `cec02f8`**：独立仓 + 可重复工具链 + 三基线 Flash 门禁 | CI 可构建固件 | 0.1 |
| 1.2 | **已验收 @ `105250c`**：保留 GitHub master 的 SDK bridge / `0x86`（internal enable + 共用 policy） | 生产 policy 与六路调用链门禁 | 1.1 |
| 1.3 | **已验收 @ `9135183`**：Rhino 四状态/双套任务图、caps14 交叉契约、interval 与持久化迁移 | 统一 OLED 状态机 | 1.2 accepted |
| 1.4 | **已验收 @ `97f0ae8`**：事务化 factory assets 与断电恢复门禁 | 资源模块 | 1.2、1.3 accepted |
| 1.5 | **实现已验收 @ `b678137`；HIL 待 1.7 后刷机**：配置 EEPROM journal、0x95/0x97 持久化、图片上传恢复与逐块进度 | 上传/持久化 HIL 测试 | 1.3-1.4 |
| 1.6 | **B2A accepted @ `4fb65a8`；B1R13 wiring @ `600a8f2` 续 B1R13R1**：补 EOF fail-closed/真实 synthetic checks/clear-pair MOVE，并完成真实 USB partial、四 mutant durable evidence、损坏 rows 13/14 与 provenance/H-E；实机 7A/7B 与 VBUS 行为切换仍待 USER-GATE | 传输回归报告 | 1.2 |
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
| 5.2 | **已验收 @ `1ac1524`**：受限 Hook socket、libxpc XPC、签名 peer policy、握手/重放与双签名 smoke | 生产 seam | 5.0-5.1 |
| 5.3 | **已验收 @ `b49e83e`**：RuntimeOrchestrator 接入 AhaType、AI Hook/批准、灯效与防休眠 | 单一后台进程 | 5.2 |
| 5.4 | **已验收 @ `762863d`**：策略化生命周期、Studio 退出保活与后台模块启停 | 生命周期测试 | 5.3 |
| 5.5 | **已验收 @ `ea770d6`**：BLE/USB、协商、身份、命令队列、waiter 与断线恢复迁入 Runtime | 唯一设备 owner | 5.1-5.3 |
| 5.6 | **静态实现已验收 @ `19eb4dc`，待 HIL-CONFIG USER-GATE**：声明式配置规划、图片/基础配置事务、取消与恢复 | 可恢复配置事务 | 5.5、4.1 |
| 5.7 | **已验收 @ `488097d`**：Studio 纯 Runtime 客户端、production snapshot/event、即时 operation acceptance、事件刷新、空闲 long-poll 与并发/取消收口 | Studio 纯客户端；进入 HIL USER-GATE | 5.2、5.6 |
| 5.8 | **目标 v0.4**：删除 Studio 无条件语音启动，验证纯硬件路径零监听 | 纯硬件路径零 Runtime | 5.4、4.3 |
| 5.9A | **目标 v0.2**：最小签名安装链、稳定身份、旧进程互斥清理、原子升级/回滚与 DMG | v0.2 Beta 安装包 | 5.3-5.7、v0.2 兼容策略 |
| 5.9B | **目标 v1.0**：完整 Keychain/TCC/权限迁移、支持版本升级/降级矩阵与正式安装器 | 正式 Runtime 安装链 | 5.8、5.9A、4.8、5.10 |
| 5.10 | macOS interface 的跨平台语义抽象与 Windows Adapter 方案 | 跨平台 seam 决定 | 5.0、4.7 |

调度更新（2026-08-26）：真机回归证明当前 Studio 保存仍走旧直接 BLE 路径，不会触发 5.6 的 Runtime Store/operation。用户因此裁决将 5.7 从 Cursor 转交 Kimi，并将顺序从“HIL-CONFIG→5.7”改为“5.7 Studio Runtime 客户端化→HIL-CONFIG C1–C6”。旧路径配置/图片上屏成功只记兼容回归，不记配置事务 HIL 通过。

退出条件按版本分段：0.2/0.2.1 只要求 Runtime 为唯一设备 owner、Studio 退出后后台能力继续、兼容功能面 fail-closed、安装/回滚和对应 HIL 通过；0.3 独立加入旧固件 OLED 客户端兼容；0.4 起再加入统一固件、平台快捷键、语音与后续拨杆；1.0 才要求完整权限迁移、Windows 和量产矩阵。

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
| 6.0A | **目标 v0.2**：当前量产固件 + macOS BLE 的兼容、性能、安装/回滚 HIL | v0.2 发布资格报告 | 5.9A、v0.2 兼容策略 |
| 6.0B | **目标 v0.3-v0.5**：每个增量版本执行适用的固件/OLED/语音/拨杆 HIL | 分版本增量资格报告 | 对应功能 WBS |
| 6.1 | **目标 v1.0**：reducer/日志/隐藏 UI 完整性能门禁 | 性能报告 | WBS 4-5 |
| 6.2 | **目标 v1.0**：Mac/Windows × USB/BLE HIL 矩阵 | 硬件测试报告 | WBS 1-5 |
| 6.3 | **目标 v1.0**：Standard/Rhino 量产一致性校验 | 二进制差异报告 | WBS 1 |
| 6.4 | **目标 v1.0**：升级、降级、断电和断连测试 | 恢复报告 | WBS 1-5 |
| 6.4A | 多会话选择、lease 与错误目标注入测试 | 会话路由报告 | WBS 5A |
| 6.5 | 基础版本内测 10 台 | 阻断问题清单 | 6.1-6.4 |
| 6.6 | 灰度 50 台 | 遥测与客服反馈 | 6.5 |
| 6.7 | 正式发布与工厂切换 | 签名安装包/固件包 | 6.6 |

退出条件按发布列车执行：6.0A 只放行 v0.2；6.0B 分别放行 v0.3-v0.5；6.1-6.7 放行 v1.0。任何早期版本不得借用未来版本的未完成能力；WBS 5A 使用 6.4A 独立验收，不能反向阻塞 v1.0。

## 14. 分批交付节奏

发布采用短列车，不再等待“统一固件 + 语音 + 拨杆 + Windows”全部完成才交付客户端。日历以当前卡实际验收为准，不在本文承诺固定日期。

### 14.1 v0.2：先交付可用 macOS 客户端

执行顺序：

1. Codex 关闭当前 E-1R1 review；若仍有返工，可将其冻结/暂停在 v0.3，不能继续阻塞 v0.2。OLED 能力在 v0.2 始终隐藏。
2. Cursor 执行 `RELEASE-0.2-COMPATIBILITY`，建立单一 `ReleaseFeaturePolicy`：按发布版本、固件能力和 HIL 结果决定功能可见性及可写范围。
3. 基础键位/灯效若会间接生成 OLED/0x97 步骤，必须在 v0.2 兼容 planner 中剥离或拒绝；不能发送半套包。
4. Cursor 执行 WBS 5.9A，生成可复现的可签名候选，并提供安装/升级/卸载/回滚测试。
5. 用户批准 `HIL-RELEASE-0.2`：实际签名候选，用当前量产固件 + 真实键盘验证安装、连接、基础配置、Hook 拨杆自动/手动、防休眠、Studio 退出、重启和 CPU/RSS。
6. 无 P0/P1 后交付 v0.2 Beta；不等待 WBS 1.5、HIL-CONFIG C1-C6、WBS 2/3/5A。

### 14.2 v0.3：客户端 OLED 兼容版

Cursor 在 v0.2.1 收口后顺序执行 `V03-STUDIO-OLED-LEGACY-COMPATIBILITY` 的四个产品切片：C1 建立旧固件能力 profile 与 Standard/Rhino/current 真协议路由；C2 建立页面唯一字段归属、dirty-only assembler 与三级 baseline；C3 建立每页独立 Runtime operation、设备 FIFO、对象 CAS、断连续传和逐字段确认；C4 完成 Studio 页面锁、按钮与底部队列。随后用户批准 C5 `HIL-V03-STUDIO-OLED-COMPATIBILITY`，在 GitHub Standard `3e7f900`、Gitee Rhino `53cd0a97`、Local Rhino `00eb7efc` 上逐项验证正式 UI 写入、显示、切换、断电保持与自动重连。通过后才从 `ReleaseFeaturePolicy` 开放 OLED，并由 `HIL-RELEASE-0.3` 生成/安装客户端 DMG。

v0.3 写入契约冻结如下：每个按键、灯条、屏幕、拨杆、电源键等编辑页是独立 scope，每个字段只能归属一个页面；点击时只冻结并写当前页 dirty 字段，其他页面即使已修改也不得进入本 operation。零差异必须在 operation/CAS/WAL 之前 strict no-op。屏幕页若 A/B 都 dirty 则两套均写，但只激活当前套；普通页按钮为“写入当前页”，屏幕页为“写入并激活”。每页 operation 使用独立 UUID，同设备 Runtime 严格 FIFO 并沿用 Studio 底部队列；当前页排队即锁定，其他页仍可编辑。queued 可移除，running 不可普通取消；断连超过 60 秒才提供不回滚已确认内容的“放弃未完成写入”。

断连续传只在 stable device ID 与写入语义 compatibility fingerprint 均一致时沿用原 UUID，并从已确认的最小字段/资源块继续；fingerprint 不包含电量、当前通道等动态事实。永久失败 fail-fast，已确认字段推进 baseline，剩余字段保持 dirty，重试只生成剩余差异。baseline 分为 `verified`、`writeConfirmed`、`unknown`：设备读回/fingerprint 是权威，本地同步稿只作缓存；旧固件不可读回且协议要求整组写时，必须显式“覆盖写入此页”，不得静默猜测或扩大到其他页。

Studio 首次连接永远只读，不自动补齐出厂配置。新统一固件的完整快捷键、灯效与图片由版本化 factory manifest 在真正 virgin first boot 初始化；固件升级不得自动覆盖用户配置，新默认只通过用户明确确认的恢复出厂生效。旧固件沿用其既有出厂内容；客户端不能以 baselineUnknown 为理由自动写设备。

2026-09-02 的 Gitee Rhino 差分证据已证明 Runtime 底层链路可以完成 B-only `5/5`、`102400/102400` 且 A/B 断电保持；尚缺的是正式 Studio UI 等价路径和上述页面事务语义。旧 Rhino 键盘端 `0,0` 是固件上传页显示缺陷，不代表 Runtime 写入失败。v0.3 不刷统一固件，也不以 WBS 1.6/1.7 或 `HIL-CONFIG` C1-C6 为发布依赖。

### 14.3 v0.4：统一固件与平台快捷键

Zcode 先关闭 WBS 1.6/1.7，再完成 WBS 2；Cursor 完成 WBS 4.1-4.4 与 WBS 5.8。重点验收同一固件按 macOS、Windows 与已学习平台发送不同系统语音快捷键，并验证“Studio 和 Runtime 均退出时，系统/第三方语音仍由固件工作”；只有 AhaType 需要 Runtime。统一固件的 `HIL-CONFIG` C1-C6、键盘端逐块进度和 Standard/Rhino pack 在该固件列车中独立验收，不回绑 v0.3。

### 14.4 v0.5：拨杆快捷键与宏

完成 WBS 3 与 WBS 4.5。验收三档动作、快速拨动、release-all、宏重入、配置/升级互锁，并确认硬件宏与 AI 自动批准拨杆语义正交。

### 14.5 v1.0：正式统一版

完成 WBS 4.6-4.8、5.9B、5.10 和 WBS 6 正式资格/灰度/量产。交付 macOS DMG、Windows 安装包、Standard/Rhino 固件、升级/降级/回滚包和客服材料。

### 14.6 v1.1：最近待操作会话定向

完成 WBS 5A 与 6.4A。Codex App Adapter、TargetLease、安全草稿和首批 Terminal Adapter 独立发布；不能反向阻塞 v1.0。

## 15. 发布门禁与验收矩阵

### 15.0 过程测试与实机介入节奏

测试不得集中到 WBS 6。每个 Runtime 批次采用以下逐级门禁：

1. **每次提交**：相关公开 seam 的单元/契约测试、`git diff --check`；批次结束运行完整 Swift 测试和 Release 构建。
2. **WBS 5.2 无设备集成门禁**：连续/拆分/超长 frame、N/N-1 握手、未握手拒绝、白名单消息、跨连接总限速、socket `0600` 与同 UID、XPC wire/timeout/cancellation、事件断档强制 Snapshot。生产 server 在 macOS 12+ 使用 C libxpc 的 `xpc_connection_set_peer_code_signing_requirement` 与 `xpc_connection_get_euid`，不允许用 `NSXPCConnection.processIdentifier` 重新查询 SecCode。随后用两个实际签名进程验证 Studio ↔ Runtime XPC；错误 Team/Signing ID 必须拒绝。签名 smoke 不需要键盘，未通过时 WBS 5.2 保持“部分完成”。
3. **第一次实机冒烟——签名 smoke 通过且 WBS 5.3 接入现有 Agent 路径后、5.3 完成前**：使用当前可用固件和至少一把真实键盘，不等待统一固件。必须验证 Hook ↔ Runtime socket、实时拨杆“自动/手动”切换、Studio 完全退出后 AI 检测与防休眠继续、断连重连，以及后台状态响应不超过 2 秒。连接键盘连续运行至少 30 分钟并采样 CPU/RSS；相同状态轮询必须零 UI 发布、零常规磁盘日志。此门禁失败不得宣告 5.3 完成。
4. **第二次实机 HIL——WBS 5.5 唯一设备 owner 完成后**：macOS 上 BLE/USB 各跑连接、切换、睡眠唤醒、迟到回包隔离和 Studio 退出；确认旧 Agent/Studio 不再争抢设备。
5. **配置事务实机 HIL——WBS 5.6 完成后**：图片与基础配置、取消、断电、断连、恢复、容量拒绝和 revision/baseline 一致性。
6. **完整发布 HIL——WBS 6.2/6.4**：Mac/Windows × USB/BLE、Standard/Rhino、升级/降级、8 小时重连与性能矩阵。这是发布门禁，不替代前述早期实机测试。

第一次实机使用现有固件验证 Runtime/Hook/拨杆后台链路；统一固件的平台识别、纯硬件语音和自定义拨杆宏按 WBS 1-3 的固件 Alpha 另行验收，二者不能混为一次测试。

### 15.0A 分版本发布门禁

| 版本 | 必须通过的最小门禁 | 失败时处理 |
|---|---|---|
| v0.2 | 当前量产固件兼容矩阵；功能策略 fail-closed；基础配置无 OLED/0x97 副作用；Hook/防休眠/退出 Studio；30 分钟真实键盘 CPU/RSS；签名安装/升级/卸载/回滚 | 不发布 v0.2；不得临时显示 OLED 或恢复直连 BLE |
| v0.3 | 正式 Studio UI；GitHub Standard/Gitee Rhino/Local Rhino 已登记旧固件矩阵；A/B scoped 写入与保留；断电保持；Runtime 字节进度；未知能力 fail-closed；签名 DMG 升级/回滚 | 保持 v0.2.1 功能策略，OLED 继续隐藏；不以刷统一固件绕过旧固件兼容 |
| v0.4 | WBS 1 统一固件基线；Mac/Windows × USB/BLE 平台学习与系统/第三方语音；Studio/Runtime 均退出；统一固件配置事务 HIL | 保持 v0.3，不把 AhaType 冒充纯硬件语音，不回退旧固件兼容 |
| v0.5 | 拨杆 500 次/档、快速越档、宏重入、release-all 与升级互锁 | 保持 v0.4，拨杆自定义 UI 不开放 |
| v1.0 | WBS 6.1-6.7 完整资格、灰度与量产；Windows 对齐；完整迁移 | 不切正式渠道或工厂 |
| v1.1 | WBS 6.4A 多会话错误目标注入与 Adapter 升级回归 | 只回退会话定向，不影响 v1.0 基础能力 |

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
M0    技术风险与 Runtime/Studio 主链关闭（已完成主体）
M0.2  可用 macOS 客户端 Beta：兼容策略 + 最小安装链 + 当前固件 HIL
M0.3  统一固件 parity + OLED/配置事务 HIL
M0.4  纯硬件跨平台语音
M0.5  拨杆快捷键/宏
M1.0  Windows、完整迁移、性能灰度与量产发布
M1.1  最近待操作会话定向
```

每个里程碑都必须有可烧录固件、配套客户端、测试报告和回滚产物；不能只以代码合并作为完成标准。

## 18. 最终产品表述

对用户的统一说明应为：

> AhaKey Studio 只用于配置。普通快捷键、宏、系统语音输入、Typeless 和拨杆硬件动作由键盘独立完成；AhaType、AI 自动批准、最近待操作会话定向、动态状态灯和防休眠等增强能力由轻量 AhaKey Runtime 在后台提供。关闭 Studio 不会影响已启用的能力，不使用增强能力时也无需运行 Runtime。
