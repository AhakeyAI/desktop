# AhaKey macOS 原生上位机产品总纲

更新时间：2026-04-16

## 1. 文档定位

本文档是 AhaKey macOS 原生上位机的纲领性设计文档，用于统一以下事项：

- 产品目标
- 主界面形态
- 阶段性开发范围
- 模块边界与接口约束
- 验收标准
- 开源与二创传承方式

本文档不直接展开具体像素级 UI 细节，不替代视觉稿、交互稿、接口实现文档与测试用例，但为这些后续文档提供统一母版。

---

## 2. 产品定义

### 2.1 产品名称

暂定：`AhaKey Studio for macOS`

### 2.2 产品使命

做一个“苹果原生、足够轻量、足够直观”的键盘控制台，让用户在看到自己键盘形态的同时，直接完成键位、屏幕、灯效、语音和自动化的配置。

### 2.3 核心产品判断

本产品不是“设置页集合”，而是“键盘的数字孪生编辑器”。

用户打开软件后，第一视觉中心必须是接近实体 1:1 形态的键盘图，而不是表单、标签页、表格或列表。

### 2.4 非目标

- 不做内置大模型推理平台
- 不把复杂云端能力塞进首版主流程
- 不做通用型 IDE 面板拼装器
- 不做偏工程师视角的“参数面板优先”产品

---

## 3. 设计原则

### 3.1 形态优先

主界面必须按照实体键盘主要元素进行映射：

- 灯条
- OLED 屏幕
- 四个按键
- 拨杆

### 3.2 所见即所得

点哪个硬件区域，就编辑哪个硬件区域。

### 3.3 单一主流程

首版最重要流程只有一个：

`连接设备 -> 选择模式 -> 点选硬件部位 -> 修改配置 -> 同步到设备`

### 3.4 原生优先

优先采用苹果官方框架完成体验闭环：

- SwiftUI
- CoreBluetooth
- 系统听写能力 / Speech 能力
- ScreenCaptureKit
- ServiceManagement

### 3.5 开源可传承

任何与设备型号、键位布局、动作体系相关的描述，都必须尽量配置化、数据化，避免写死在 UI 中。

---

## 4. 主界面总方案

### 4.1 核心结论

主界面采用“数字孪生画布 + 原生检查器”的结构。

窗口中心区域是键盘 1:1 可点击图形。
右侧是所选部件的属性编辑区。
顶部只保留连接、模式、同步、状态。

### 4.2 推荐布局

1. 顶部工具栏
2. 中央数字孪生画布
3. 右侧 Inspector 检查器
4. 左下或底部状态条

### 4.3 顶部工具栏内容

- 设备连接状态
- 电量
- 当前模式 Mode 0 / 1 / 2
- 同步到键盘
- 撤销 / 重做
- 更多操作

工具栏不承载复杂配置，不承担主编辑责任。

### 4.4 数字孪生画布内容

画布中的键盘必须包含以下交互热区：

- `Light Bar` 灯条
- `Display` OLED 屏幕
- `Key 1` 语音键
- `Key 2` 确认键
- `Key 3` 取消键
- `Key 4` 自定义键
- `Toggle Switch` 拨杆

每个热区必须支持：

- hover 高亮
- selected 选中态
- 当前配置摘要
- 改动未同步提示

### 4.5 Inspector 检查器

当用户选中不同部件时，右侧检查器切换到相应编辑模型：

- 选中按键：编辑键位、宏、描述、动作
- 选中 OLED：编辑文本、图片、GIF、展示策略
- 选中灯条：编辑状态映射、颜色、效果
- 选中拨杆：编辑自动批准联动逻辑、提示文案

### 4.6 模式切换原则

Mode 0 / 1 / 2 不是不同页面，而是同一把键盘的三套配置。

切换模式后：

- 画布仍是同一把键盘
- 仅配置内容变化
- 所有高亮和摘要即时刷新

### 4.7 官方首版默认预设

首版官方产品语义定义如下：

- `Mode 0`：官方默认编程模式，用于 Claude、Cursor、Codex 等 vibecoding 场景
- `Mode 1`：用户自定义模式
- `Mode 2`：用户自定义模式

首版默认键帽图标语义如下：

- `Key 1`：麦克风
- `Key 2`：对勾
- `Key 3`：叉号
- `Key 4`：回车

拨杆正式状态命名如下：

- 往上：`自动批准`
- 往下：`手动批准`

`Mode 0` 下灯条至少包含以下官方默认状态：

- AI 运行中：来回流水灯
- AI 结束：红色常亮停住

更丰富的状态矩阵可在后续版本继续扩展，但首版必须先把这组默认语义跑通。

### 4.8 Mode 0 灯条状态矩阵

以下矩阵基于两部分整理：

- 旧版 hook 发送的 `ClaudeState`
- 固件 `update_claude_ws2812()` 中对状态的实际映射

其中：

- `Aha Accent Red` 指旧固件里的主强调色 `0xF02029`，视觉上接近红 / 品牌洋红
- `Working Blue` 指旧固件里的运行色 `0x2050FF`

旧固件里的灯效模式语义如下：

- `WS2812_MIDDLE_LIGHT`：中间最亮、两侧渐弱的静态灯
- `WS2812_SINGLE_MOVE`：单点来回流水
- `WS2812_BREATHING`：整条呼吸
- `WS2812_RAINBOW_MOVE`：彩虹单点来回流水
- `WS2812_RAINBOW_WAVE`：整条彩虹波浪
- `WS2812_OFF`：熄灭

#### 4.8.1 旧代码已实现矩阵

| 状态值 | Hook 事件 | 手动批准 | 自动批准 | 说明 |
|------|------|------|------|------|
| 0 | Notification | 未单独实现 | 未单独实现 | 固件当前不会切换专属灯效，基本等于保持上一状态 |
| 1 | PermissionRequest | `BREATHING + Aha Accent Red` | `RAINBOW_WAVE` | 等待授权时最显眼 |
| 2 | PostToolUse | `SINGLE_MOVE + Aha Accent Red` | `RAINBOW_MOVE` | 工具调用完成后的过渡态 |
| 3 | PreToolUse | `SINGLE_MOVE + Working Blue` | `RAINBOW_WAVE` | 工具执行中 |
| 4 | SessionStart | `MIDDLE_LIGHT + Aha Accent Red` | `MIDDLE_LIGHT + Aha Accent Red` | 会话开始提示 |
| 5 | Stop | `MIDDLE_LIGHT + Aha Accent Red` | `MIDDLE_LIGHT + Aha Accent Red` | 停止态 |
| 6 | TaskCompleted | 未单独实现 | 未单独实现 | 固件当前不会切换专属灯效，基本等于保持上一状态 |
| 7 | UserPromptSubmit | `SINGLE_MOVE + Aha Accent Red` | `RAINBOW_MOVE` | 用户提交后的过渡态 |
| 8 | SessionEnd | `OFF` | `OFF` | 会话结束熄灭 |

#### 4.8.2 Native 首版补齐后的完整矩阵

为避免 `Notification` 和 `TaskCompleted` 在新原生版本中继续表现为“无专属灯效”，首版产品建议补齐为以下矩阵：

| 状态值 | Hook 事件 | 手动批准 | 自动批准 | 设计意图 |
|------|------|------|------|------|
| 0 | Notification | `MIDDLE_LIGHT + Aha Accent Red` | `MIDDLE_LIGHT + Aha Accent Red` | 有提醒，但不打断主流程 |
| 1 | PermissionRequest | `BREATHING + Aha Accent Red` | `RAINBOW_WAVE` | 明确表示授权相关状态 |
| 2 | PostToolUse | `SINGLE_MOVE + Aha Accent Red` | `RAINBOW_MOVE` | 工具执行后反馈 |
| 3 | PreToolUse | `SINGLE_MOVE + Working Blue` | `RAINBOW_WAVE` | AI 正在工作 |
| 4 | SessionStart | `MIDDLE_LIGHT + Aha Accent Red` | `MIDDLE_LIGHT + Aha Accent Red` | 会话建立 |
| 5 | Stop | `MIDDLE_LIGHT + Aha Accent Red` | `MIDDLE_LIGHT + Aha Accent Red` | 停止并停住 |
| 6 | TaskCompleted | `MIDDLE_LIGHT + Aha Accent Red` | `MIDDLE_LIGHT + Aha Accent Red` | 任务完成，停住提示 |
| 7 | UserPromptSubmit | `SINGLE_MOVE + Aha Accent Red` | `RAINBOW_MOVE` | 用户刚提交，系统准备进入下一轮 |
| 8 | SessionEnd | `OFF` | `OFF` | 整个会话结束 |

补充说明：

- 上表中 `Notification` 与 `TaskCompleted` 的映射属于产品补齐，不是旧固件现状
- 若后续希望把“完成”与“错误”区分得更明显，可再引入绿色完成态或独立完成动画
- 旧 hook 代码中 `SwitchState == 0` 代表自动模式；原生上位机需要把这个设备值映射到产品文案 `自动批准`

---

## 5. 用户主流程

### 5.1 首次使用流程

1. 欢迎引导
2. 蓝牙权限提示
3. 搜索并连接设备
4. 显示数字孪生主界面
5. 引导用户先修改一个键
6. 点击“同步到键盘”

### 5.2 日常使用流程

1. 打开软件
2. 自动恢复最近设备连接
3. 读取当前状态
4. 进入数字孪生画布
5. 点选部位并修改
6. 同步并保存

### 5.3 语音键配置与使用流程

语音能力在首版产品中的核心定位不是“上位机自己接管转写运行时”，而是“为语音键提供面向软件的预设绑定能力”。

用户看到的是语音软件或语音方案选择，例如：

- macOS 原生语音转文本
- Typeless / Fn
- 微信语音
- Claude Code 自带语音快捷键
- Codex 自带语音快捷键
- 豆包输入法内测版
- 自定义快捷键

主路径中不优先向用户暴露原始快捷键编码；快捷键只作为底层实现细节存在。

首版推荐流程如下：

1. 用户在 `Mode 0` 中选中 `Key 1`
2. 在 Inspector 中选择“语音方案”
3. 默认预设为 `macOS 原生语音转文本`
4. 用户也可切换为 `Typeless / Fn` 或其他第三方软件
5. 系统将该预设解析为实际快捷键组合
6. 同步到键盘后，键盘按下 `Key 1` 时发送对应快捷键
7. 被选中的语音软件在 macOS 中响应该快捷键并完成后续转文字

这意味着：

- 用户心智是“我在给键盘选择语音软件”
- 工程实现是“系统把软件预设转换成快捷键并写入键盘”
- 后续若接入更深的原生语音能力，也应兼容这一层抽象，而不是破坏已有配置模型

当前迭代范围进一步明确如下：

- 默认预设：`macOS 原生语音转文本`
- 本次首批落地的软件预设：`Typeless / Fn`、`微信语音`
- 已列入后续迭代的软件预设：`Claude Code 自带语音快捷键`、`Codex 自带语音快捷键`、`豆包输入法内测版`

---

## 6. 分阶段实施计划

## 阶段 P0：资产与规格冻结

### 目标

建立可实施的 1:1 数字孪生基础资产。

### 产出

- 键盘正视或近正视高清参考图
- 尺寸表
- 热区定义图
- 三种模式的语义说明
- 当前硬件状态表

### 输入要求

- 至少一张正面图
- 最好补一张接近俯视图
- 屏幕、灯条、四键、拨杆的相对尺寸
- 键帽中心点坐标或可推导尺寸

### 验收

- 画布原型中热区位置可被工程准确命中
- 设计、产品、硬件三方对部件命名统一

### 当前已确认输入（2026-04-16）

已收到一张带尺寸标注的俯视/正视混合参考图，可作为首版数字孪生画布的比例基线。

已确认的硬件尺寸与相对关系如下：

- 整机外形约 `109mm x 54mm`
- RGB LED 灯条约 `80mm x 3mm`
- OLED 显示区域约 `28mm x 15mm`
- 单个键帽约 `15mm x 15mm`
- 键距中心到中心约 `18mm`
- 键间隙约 `3mm`
- 拨动开关底座约 `8mm x 12mm`

已确认的默认物理角色如下：

- `Key 1`：语音键
- `Key 2`：确认键
- `Key 3`：取消键
- `Key 4`：自定义键 / 回车键
- `OLED`：屏幕显示区域
- `Light Bar`：顶部状态灯条
- `Toggle Switch`：模式/自动化相关拨杆

已确认的 `Mode 0` 产品语义如下：

- 用途：默认编程模式，适配 Claude、Cursor、Codex 的 vibecoding 使用场景
- 屏幕：当前版本仅默认显示自定义动图
- 屏幕开发预告：文字、token 用量、模型环境等信息型显示在 UI 中以“开发中”提示呈现
- 灯效：表达 AI 写代码过程中的状态变化
- 默认状态 1：AI 运行中时，灯条表现为来回流水灯
- 默认状态 2：AI 结束时，灯条表现为红色常亮停住

已确认的 `Mode 1` / `Mode 2` 产品语义如下：

- `Mode 1`：用户自定义模式，保留给用户自由定义，也允许后续官方继续扩展
- `Mode 2`：用户自定义模式，保留给用户自由定义，也允许后续官方继续扩展

已确认的首版官方默认图标与命名如下：

- `Key 1`：麦克风
- `Key 2`：对勾
- `Key 3`：叉号
- `Key 4`：回车

已确认的拨杆正式命名如下：

- 往上：`自动批准`
- 往下：`手动批准`

### 当前仍待补充的最少信息

以下信息不是开始线框设计的阻塞项，但会影响默认预设与交互文案：

- `OLED` 在编程场景下的信息优先级，例如动图、token、模型名、运行状态谁优先显示
- `Key 1` 未来迭代中的第三方语音软件优先级排序

## 阶段 P1：原生数字孪生外壳

### 目标

完成“看起来就是这把键盘”的主界面外壳。

### 功能

- 顶部工具栏
- 数字孪生画布
- 热区 hover / select
- 右侧 Inspector
- 模式切换
- 未同步状态提示

### 验收

- 用户首次看到界面，能在 5 秒内说出四个按键和屏幕位置
- 用户不看文档，能独立点击某个键进入编辑态

## 阶段 P2：键位配置主链路

### 目标

打通最核心的“改键并同步”能力。

### 功能

- 快捷键录制
- HID 键码编辑
- 宏编辑
- 软件预设选择器（面向用户）
- 预设到快捷键的解析层（面向设备）
- OLED 描述编辑
- 同步到设备
- 本地草稿与设备配置对比

### 验收

- 4 个键在 3 个模式下都可编辑
- `Key 1` 支持“选软件而不是手填快捷键”的主路径
- 写入后执行 `SAVE_CONFIG`
- 设备断电重连后配置不丢失

## 阶段 P3：屏幕与灯效

### 目标

完成 OLED 和 LED 的可视化配置。

### 功能

- GIF 上传与帧预览
- 信息型 OLED 功能的“开发中”占位提示
- IDE 状态与灯效映射
- 灯条效果预览

### 验收

- 用户可把 160x80 内容上传到设备
- 当前版本主路径聚焦动图能力，其他 OLED 信息显示功能在界面中明确标记为“开发中”
- 至少支持 1 套默认灯效映射和 1 套自定义映射

## 阶段 P4：语音软件适配与自动化

### 目标

完成语音软件预设体系和 AhaKey 自动化桥接。

### 功能

- `macOS 原生语音转文本` 预设
- `Typeless / Fn` 预设
- `微信语音` 预设
- 自定义快捷键预设
- 软件预设与快捷键的双向映射规则
- Claude / Cursor / Codex 状态联动
- 屏幕内容抓取并上传到 OLED

后续迭代预留但不纳入本次交付：

- `Claude Code 自带语音快捷键`
- `Codex 自带语音快捷键`
- `豆包输入法内测版`

### 验收

- 用户在主路径中看到的是“软件选择”，不是“原始快捷键编码”
- 选择不同语音软件后，系统能把对应快捷键正确写入键盘
- 本次交付仅要求稳定支持 `macOS 原生语音转文本`、`Typeless / Fn`、`微信语音`
- 不依赖自带模型完成基础语音转文字接入
- Hooks 与后台服务可安装、可停止、可卸载

## 阶段 P5：开源与二创能力

### 目标

让社区可以低成本衍生自己的上位机。

### 功能

- 导入导出配置
- 设备布局配置化
- 动作注册表
- 开发者文档
- 示例主题 / 示例布局

### 验收

- 第三方不改核心 BLE 层，也能新增一种皮肤或动作
- 配置文件可被版本管理和分享

---

## 7. 模块划分

### 7.1 AppShell

负责窗口、导航、权限引导、全局状态。

### 7.2 DeviceTwinRenderer

负责数字孪生画布渲染、热区命中、选中态、高亮态、部件摘要。

### 7.3 InspectorModule

负责按部件展示编辑器。

### 7.4 DeviceSession

负责 CoreBluetooth 连接、扫描、发现、重连、状态订阅、原始命令发送。

### 7.5 ConfigDomain

负责本地配置模型、草稿状态、差异检测、序列化、导入导出。

### 7.6 SyncEngine

负责把草稿配置转换为 BLE 命令序列，并保证顺序写入与保存。

### 7.7 VoiceBindingService

负责语音软件预设、快捷键解析、默认方案管理，以及未来更深层原生语音能力的兼容扩展。

### 7.8 CaptureService

负责屏幕内容获取、缩放、颜色格式转换、OLED 数据准备。

### 7.9 AutomationBridge

负责 Claude / Cursor / Codex hooks、状态映射、后台服务协议。

### 7.10 OpenProfileKit

负责对外 JSON 配置格式、布局定义、动作注册机制。

---

## 8. 核心数据模型

```text
KeyboardProfile
- profileId
- hardwareModel
- hardwareRevision
- deviceName
- activeMode
- modes[3]
- automation
- metadata

ModeProfile
- modeId
- keyBindings[4]
- displayProfile
- lightProfile
- switchProfile

KeyBinding
- keyIndex
- role
- actionKind: shortcut | macro | voicePreset | hostAction
- shortcut
- macro
- voicePreset
- hostAction
- displayLabel

VoicePresetBinding
- providerId: appleDictation | typelessFn | customShortcut | ...
- providerName
- resolvedShortcut
- exposeRawShortcutInPrimaryUI: false
- note

DisplayProfile
- renderType: text | image | gif | capture
- text
- assetId
- fps

LightProfile
- stateMappings[]
- brightness
- effect

SwitchProfile
- semantic: manual | autoApprove | custom
- linkedAction
```

---

## 9. 接口约束

### 9.1 UI 与 BLE 的边界

UI 不直接拼帧，不直接处理硬件字节流。

UI 只能调用领域接口，例如：

- `connectDevice()`
- `loadDeviceSnapshot()`
- `applyDraft(profile)`
- `syncDraftToDevice()`

### 9.2 SyncEngine 与协议层边界

SyncEngine 负责“业务配置 -> 命令序列”。
协议层只负责“命令对象 -> 字节帧”。

### 9.3 语音绑定模块边界

主路径中，语音模块负责“软件预设 -> 快捷键解析 -> 键盘绑定”。

原则如下：

- UI 优先呈现软件名称，而不是原始快捷键
- SyncEngine 只消费解析后的快捷键结果
- 若未来引入更深的原生语音运行时，也必须兼容既有 `voicePreset` 配置模型

### 9.4 自动化桥接边界

后台桥接服务只接收标准化事件，不关心 UI 来源。

推荐使用 Unix Domain Socket + JSON Lines：

```json
{"type":"ide_state","state":"preToolUse"}
{"type":"speech","action":"start"}
{"type":"capture","source":"frontmost_window"}
```

---

## 10. 可传承文档清单

建议仓库最终至少具备以下文档：

1. `00-product-charter.md`
2. `01-director-brief.md`
3. `02-ux-blueprint.md`
4. `03-domain-model.md`
5. `04-ble-contract.md`
6. `05-helper-service-contract.md`
7. `06-acceptance-matrix.md`
8. `07-open-profile-spec.md`
9. `08-community-extension-guide.md`

---

## 11. 当前工程基础与差距

当前仓库已经具备以下基础：

- 原生 CoreBluetooth 通信管理
- 设备状态查询
- 键位写入
- 描述写入
- 状态同步到 LED
- 守护进程与 hooks 基础

当前仓库仍缺以下关键产品层能力：

- 1:1 数字孪生主界面
- 多模式完整编辑
- 宏编辑完整主流程
- OLED 上传完成态
- 面向用户的语音软件预设与快捷键映射层
- 可配置的开源动作体系

---

## 12. 是否需要借助其他 AI

结论：不是必须，但对“高保真视觉稿”有帮助。

### 不需要其他 AI 也能完成的部分

- 产品总纲
- 信息架构
- 模块拆分
- 接口设计
- 原生技术选型
- 工程实施路线

### 适合借助其他 AI 的部分

- 根据照片快速生成接近成品感的视觉概念稿
- 生成不同材质、配色、光效的视觉探索图
- 为 Figma 初稿提供背景资产或透明底物料

### 不建议完全交给 AI 的部分

- 热区精确位置
- 尺寸映射
- 交互状态定义
- 工程实现规格

这些必须以真实硬件尺寸和产品定义为准。

---

## 13. 下一步建议

立即进入以下顺序：

1. 冻结硬件可视资产和尺寸
2. 输出低保真线框图
3. 输出高保真视觉稿
4. 冻结数据模型和同步协议封装
5. 实现 P1 和 P2

如果要推进高保真主界面，优先补齐：

- 正视图
- 俯视图
- 尺寸图
- 各部件命名表
- 三模式语义说明
