# AhaKey Studio 项目技术文档

## 项目概述

AhaKey Studio 是一个 Windows 桌面应用程序，用于配置和管理 AhaKey 智能键盘设备。项目采用 **JavaFX** 作为 UI 框架，通过 BLE（蓝牙低功耗）协议与键盘设备通信，支持自定义按键映射、OLED 屏幕动画上传、灯光效果控制等功能。

### 技术栈

| 技术 | 版本 | 用途 |
|------|------|------|
| JavaFX | 17.0.10 | 桌面 UI 框架 |
| Jackson | 2.16.0 | JSON 序列化/反序列化 |
| JNA | 5.14.0 | 访问 Windows 原生 API |
| SLF4J + Logback | 2.0.9 / 1.4.11 | 日志框架 |

---

## 项目结构

```
java-demo1/src/main/java/com/example/ahakey/
├── App.java                    # JavaFX 应用入口
├── Main.java                   # 程序启动类
├── app/
│   └── StudioController.java   # 主控制器（业务核心）
├── model/                      # 数据模型
│   ├── DeviceStatus.java       # 设备状态
│   ├── HIDUsage.java           # HID 键码定义
│   ├── IDEState.java           # IDE 状态枚举
│   ├── KeyConfig.java          # 按键配置
│   ├── LightBarPreviewState.java # 灯条预览状态
│   ├── LightEffectStyle.java   # 灯光效果样式
│   ├── ModeSlot.java           # 模式槽位（Claude/Cursor/Codex）
│   ├── OledModeDraft.java      # OLED 动画草稿
│   ├── StudioPart.java         # 可配置部件
│   ├── StudioState.java        # 应用状态（核心）
│   └── VoicePreset.java        # 语音预设
├── platform/
│   ├── VoiceRelayPlatform.java # 跨平台语音桥门面
│   └── windows/
│       ├── WindowsVoiceTyping.java      # Windows 语音输入触发器
│       └── WindowsVoiceRelayService.java # Windows 语音中继服务
├── protocol/                   # 通信协议
│   ├── AhaKeyProtocol.java     # AhaKey 通信协议
│   ├── AhaKeyResponseParser.java # 响应解析器
│   └── BleTcpPacket.java       # BLE TCP 数据包
├── service/                    # 业务服务
│   ├── AgentManager.java       # Hook 管理器
│   ├── BleManager.java         # BLE 通信管理（核心）
│   ├── ConfigStore.java        # 配置持久化
│   ├── DeviceSyncService.java  # 设备同步服务
│   ├── HookClient.java         # Hook 客户端
│   ├── OledUploadService.java  # OLED 上传服务（核心）
│   ├── SocketServer.java       # Unix Socket 服务器
│   └── VoiceInputManager.java  # 语音输入管理器
├── util/                       # 工具类
│   ├── ConfigStore.java        # 配置存储
│   ├── Icons.java              # 图标工厂
│   ├── OLEDFrameEncoder.java   # OLED 帧编码器
│   └── StudioStore.java        # 草稿持久化
└── view/                       # UI 组件
    ├── CanvasController.java   # 画布控制器（FXML）
    ├── CanvasPane.java         # 画布面板
    ├── InfoPill.java           # 信息胶囊组件
    ├── InspectorPane.java       # 检查器面板
    ├── StatusBar.java          # 状态栏
    ├── TopBar.java             # 顶部导航栏
    └── AccentColor.java        # 强调色枚举
```

---

## 核心类详解

### 1. App.java - 应用入口

**类说明**: JavaFX 桌面应用的主类，负责初始化和显示主界面。

| 方法 | 说明 |
|------|------|
| `main(String[] args)` | 程序入口，调用 `launch()` 启动 JavaFX 运行时 |
| `start(Stage primaryStage)` | 核心初始化方法，构建并显示主界面 |

**布局结构**:
```
┌─────────────────────────────────────────┐
│                 TopBar                   │ ← 顶部导航栏
├─────────────────────┬───────────────────┤
│                     │                   │
│    CanvasPane       │   InspectorPane    │ ← 中间工作区
│    (键盘预览)       │   (配置检查器)     │
│                     │                   │
├─────────────────────┴───────────────────┤
│               StatusBar                  │ ← 底部状态栏
└─────────────────────────────────────────┘
```

---

### 2. StudioController.java - 主控制器

**类说明**: 应用总线，连接 BLE 通信、状态管理、语音控制的核心编排逻辑。类比 Spring MVC 中的 Controller。

| 方法 | 说明 |
|------|------|
| `StudioController()` | 构造函数，初始化 BLE 管理器、状态轮询、语音服务 |
| `getBleManager()` | 获取 BLE 管理器实例 |
| `getDeviceStatus()` | 获取设备状态对象 |
| `getStudioState()` | 获取应用状态对象 |
| `getAgentManager()` | 获取 Hook 管理器 |
| `isEffectivelyConnected()` | 判断是否有效连接 |
| `hasUnsyncedChanges()` | 检查是否有未同步的改动 |
| `shutdown()` | 关闭应用，释放资源 |
| `startStatusPolling()` | 启动设备状态定时轮询（3秒间隔） |
| `stopStatusPolling()` | 停止状态轮询 |
| `userConnect()` | 用户点击连接按钮 |
| `userDisconnect()` | 用户点击断开按钮 |
| `enterEditingConfiguration()` | 进入编辑配置模式 |
| `finishEditingConfiguration()` | 完成编辑并同步到设备 |
| `returnToKeyboardControl()` | 交还蓝牙控制权给键盘设备 |
| `syncAllModes(boolean returnToAgentWhenDone)` | 同步所有模式的配置到设备 |
| `previewLightOnDevice()` | 发送灯效预览到设备 |
| `updateSwitchState(int state)` | 更新拨杆状态 |
| `selectOledGif(Window owner)` | 打开文件选择对话框选择 OLED 图片 |
| `previewOledOnDevice()` | 预览 OLED 动画 |
| `uploadCurrentOledToDevice()` | 上传 OLED 动画到设备 |

---

### 3. StudioState.java - 应用状态

**类说明**: 集中管理应用的所有状态数据，使用 JavaFX Properties 实现响应式更新。类比 Redux/Vuex 的 Store。

| 方法 | 说明 |
|------|------|
| `selectedModeProperty()` | 当前选中的模式（MODE0/MODE1/MODE2） |
| `selectedPartProperty()` | 当前选中的配置部件（KEY1/OLED/LIGHT_BAR 等） |
| `dirtyCountProperty()` | 未保存的改动数量 |
| `revisionProperty()` | 状态版本号（每次修改递增） |
| `syncStatusProperty()` | 同步状态文本 |
| `syncingProperty()` | 是否正在同步中 |
| `ahaTypeEnabledProperty()` | AhaType 云端整理是否启用 |
| `lightBarPreviewProperty()` | 灯条预览状态 |
| `getKeyConfig(mode, part)` | 获取指定模式和部件的按键配置 |
| `getOledDraft(mode)` | 获取指定模式的 OLED 草稿 |
| `applyOledGifSelection(path, frameCount)` | 应用 GIF 选择结果 |
| `updateKeyCode(part, displayName)` | 更新按键码 |
| `markDirty(part)` | 标记部件为已修改 |
| `clearDirtyAfterSync()` | 同步后清除脏标记 |
| `loadFromPersisted(draft)` | 从持久化数据加载状态 |
| `toPersisted()` | 转换为持久化格式 |

**内部类**:
- `PersistedDraft`: JSON 持久化数据结构
  - `ModeDraft`: 单个模式的草稿数据

---

### 4. BleManager.java - BLE 通信管理

**类说明**: 管理与 BLE 桥的 TCP 连接，处理命令发送与响应接收。使用 `ReentrantLock` + `Condition` 实现线程同步的等待/通知机制。

| 方法 | 说明 |
|------|------|
| `BleManager(callback)` | 构造函数，使用默认地址（127.0.0.1:9000） |
| `BleManager(host, port, callback)` | 构造函数，指定地址 |
| `fromEnvironment(callback)` | 静态工厂，从环境变量读取配置 |
| `connect()` | 连接到 BLE 桥（异步） |
| `disconnect()` | 断开连接 |
| `sendCommand(command)` | 发送命令 |
| `sendCommandExpecting(command, expectedCmd)` | 发送命令并等待指定响应 |
| `writeData(chunk)` | 发送数据块 |
| `writeLargeData(address, data)` | 写入大数据（自动分块） |
| `readPictureState(mode)` | 读取 OLED 图片状态 |
| `queryStatus()` | 查询设备状态 |
| `updateState(state)` | 更新设备状态 |
| `isConnected()` | 是否已连接 |
| `getCachedStatus()` | 获取缓存的设备状态 |
| `getLastStatusUpdateTime()` | 获取最后状态更新时间（毫秒） |

**内部接口**:
```java
interface BleCallback {
    void onConnected();           // 连接成功
    void onDisconnected();       // 断开连接
    void onStatusReceived(status); // 收到状态更新
    void onError(message);        // 发生错误
}
```

**协议常量**:
- `RESPONSE_TIMEOUT_MS = 15000`: 命令响应超时时间
- `RECONNECT_WAIT_MS = 30000`: 断线重连等待时间

---

### 5. OledUploadService.java - OLED 上传服务

**类说明**: 处理 GIF/静态图片的上传，使用线程池异步执行。

| 方法 | 说明 |
|------|------|
| `resolveStartIndex(ble, mode, frameCount)` | 计算 OLED 帧的起始索引 |
| `uploadGif(ble, mode, gifPath, fps, onProgress, onComplete, onError)` | 上传 GIF 动画（异步） |
| `uploadStaticImage(ble, mode, imagePath, onProgress, onComplete, onError)` | 上传静态图片（PNG/JPG） |
| `previewGif(ble, gifPath, fps, onComplete, onError)` | 预览 GIF 动画 |

**上传流程**:
1. 读取 GIF 文件，编码为 RGB565 格式
2. 计算起始帧索引
3. 分块写入每帧数据（每块 4096 字节）
4. 发送 `updatePicture` 命令激活显示
5. 更新进度回调

**回调接口**:
```java
@FunctionalInterface
interface Consumer<T> {
    void accept(T t);
}

record UploadProgress(int completedFrames, int totalFrames, String detail) {}
```

---

### 6. DeviceSyncService.java - 设备同步服务

**类说明**: 将配置数据转换为设备协议命令，并顺序写入设备。

| 方法 | 说明 |
|------|------|
| `commandsForModes(state, modes)` | 为指定模式生成所有同步命令 |
| `writeSequentially(ble, commands, onComplete, onStatus)` | 顺序执行命令 |

**同步的数据项**:
- 按键映射（KEY1-KEY4）
- 按键描述
- 宏定义

---

### 7. AhaKeyProtocol.java - 通信协议

**类说明**: 定义与设备通信的二进制协议格式。

**帧格式**:
```
[0xAA, 0xBB] [CMD] [DATA...] [0xCC, 0xDD]
    头部         命令    数据      尾部
```

| 命令常量 | 值 | 说明 |
|---------|------|------|
| `CMD_QUERY_STATUS` | 0x00 | 查询设备状态 |
| `CMD_CHANGE_NAME` | 0x01 | 修改设备名称 |
| `CMD_SAVE_CONFIG` | 0x04 | 保存配置 |
| `CMD_UPDATE_CUSTOM_KEY` | 0x73 | 更新自定义按键 |
| `CMD_PREPARE_WRITE` | 0x80 | 准备大数据写入 |
| `CMD_WRITE_RESULT` | 0x81 | 写入结果响应 |
| `CMD_UPDATE_PIC` | 0x82 | 更新 OLED 图片 |
| `CMD_READ_PIC_STATE` | 0x83 | 读取图片状态 |
| `CMD_UPDATE_STATE` | 0x90 | 更新状态 |

**OLED 常量**:
| 常量 | 值 | 说明 |
|------|------|------|
| `OLED_WIDTH` | 160 | OLED 屏幕宽度 |
| `OLED_HEIGHT` | 80 | OLED 屏幕高度 |
| `OLED_FRAME_BYTES` | 25600 | 每帧字节数 |
| `OLED_FRAME_SLOT_SIZE` | 28672 | 帧槽大小（含元数据） |
| `OLED_MAX_FRAMES` | 74 | 最大帧数 |
| `OLED_CHUNK_SIZE` | 4096 | 写入块大小 |

---

### 8. BleTcpPacket.java - BLE TCP 数据包

**类说明**: BLE 桥通信的 TCP 数据包编解码。

| 方法 | 说明 |
|------|------|
| `encode(type, data)` | 编码数据包 `[Type:1][Length:2 LE][Data:N]` |
| `decode(header, body)` | 解码数据包 |

**数据包类型**:
| 类型 | 值 | 说明 |
|------|------|------|
| `WRITE_DATA` | 0x01 | 写入数据 |
| `WRITE_COMMAND` | 0x02 | 写入命令 |
| `QUERY_BLE_STATUS` | 0x03 | 查询 BLE 状态 |
| `QUERY_DEVICE_INFO` | 0x04 | 查询设备信息 |
| `BLE_NOTIFY` | 0x81 | BLE 通知（上行） |
| `BLE_STATUS_RESP` | 0x82 | BLE 状态响应 |
| `DEVICE_INFO_RESP` | 0x83 | 设备信息响应 |

---

### 9. OLEDFrameEncoder.java - OLED 帧编码器

**类说明**: 将 GIF/图片编码为设备可用的 RGB565 格式。

| 方法 | 说明 |
|------|------|
| `validateGifSourceFileSize(path)` | 验证 GIF 文件大小（≤2MB） |
| `frameCount(gifPath)` | 获取 GIF 帧数（最多74帧） |
| `framesFromGif(gifPath)` | 从 GIF 提取所有帧并编码 |
| `encodeFrame(source)` | 编码单帧图片 |
| `frameFromSingleImage(imagePath)` | 从静态图片创建单帧编码 |
| `toRgb565BigEndian(image)` | 转换图片为 RGB565 大端格式 |

**编码流程**:
1. 按比例缩放图片到 160×80
2. 居中填充黑色背景
3. 转换为 RGB565 格式（每像素2字节）

---

## 数据模型

### ModeSlot - 模式槽位

表示键盘的三个工作模式：

| 枚举值 | 索引 | 简称 | 用途 |
|--------|------|------|------|
| `MODE0` | 0 | Claude Code | 主键盘模式 |
| `MODE1` | 1 | Cursor | 备选模式 |
| `MODE2` | 2 | Codex | 第三模式 |

### StudioPart - 可配置部件

| 枚举值 | ID | 显示标题 | 说明 |
|--------|-----|---------|------|
| `LIGHT_BAR` | lightBar | 灯条 | 状态预览灯光 |
| `OLED` | oledDisplay | OLED 屏幕 | 动画与上传反馈 |
| `KEY1` | key1 | Key 1 | 语音键 |
| `KEY2` | key2 | Key 2 | 确认键 |
| `KEY3` | key3 | Key 3 | 拒绝键 |
| `KEY4` | key4 | Key 4 | 回车键 |
| `TOGGLE_SWITCH` | toggleSwitch | 拨杆 | 自动批准开关 |

### VoicePreset - 语音预设

| 枚举值 | 显示名 | 说明 |
|--------|--------|------|
| `CUSTOM` | 自定义快捷键 | 自行绑定 HID 键 |
| `WINDOWS_NATIVE` | Windows 语音 (Win+H) | 使用系统语音输入 |
| `MACOS_NATIVE` | macOS 原生语音 | 仅 macOS 支持 |
| `TYPELESS` | Typeless / Fn | 暂未实现 |
| `WECHAT` | 微信语音 | 暂未实现 |

### LightBarPreviewState - 灯条预览状态

| 枚举值 | ID | 标题 | 对应 IDE 状态 |
|--------|-----|------|--------------|
| `AI_RUNNING` | aiRunning | AI 运行中 | PRE_TOOL_USE |
| `WAITING_APPROVAL` | waitingApproval | 等待批准 | PERMISSION_REQUEST |
| `STOPPED` | stopped | 已停止 | STOP |
| `TASK_COMPLETED` | taskCompleted | 任务完成 | TASK_COMPLETED |

### IDEState - IDE 状态码

| 枚举值 | Code | 标签 |
|--------|------|------|
| `NOTIFICATION` | 0 | 通知 |
| `PERMISSION_REQUEST` | 1 | 等待授权 |
| `POST_TOOL_USE` | 2 | 工具完毕 |
| `PRE_TOOL_USE` | 3 | 工具执行 |
| `SESSION_START` | 4 | 会话开始 |
| `STOP` | 5 | 已停止 |
| `TASK_COMPLETED` | 6 | 任务完成 |
| `USER_PROMPT_SUBMIT` | 7 | 用户提交 |
| `SESSION_END` | 8 | 会话结束 |

---

## 视图层组件

### TopBar.java - 顶部导航栏

**位置**: 应用窗口顶部

**功能区域**:
1. 标题区（图标 + "AhaKey Studio"）
2. 信息胶囊（连接状态、电量、拨杆状态）
3. 连接/断开按钮
4. AhaType 开关
5. 配置模式按钮
6. 更多菜单

**关键方法**:
| 方法 | 说明 |
|------|------|
| `createStatusBox()` | 创建状态显示盒子 |
| `showDeviceInfoDialog()` | 显示设备信息对话框 |

### CanvasPane.java - 画布面板

**位置**: 工作区左侧

**功能区域**:
1. 模式选择器（MODE0/MODE1/MODE2）
2. 键盘预览卡片（通过 FXML 加载）
3. 操作提示
4. 手动卡片（主流程说明）

### InspectorPane.java - 检查器面板

**位置**: 工作区右侧

**功能区域**: 根据选中部件显示不同配置项：
- **KEY1**: 语音软件选择 + 按键绑定 + 描述
- **KEY2-4**: 按键绑定 + 描述
- **LIGHT_BAR**: 灯效选择
- **OLED**: 图片选择 + FPS 设置 + 上传按钮
- **TOGGLE_SWITCH**: 拨杆状态

### StatusBar.java - 状态栏

**位置**: 应用窗口底部

**显示信息**:
- 当前选中部件
- 设备名称
- 待同步改动数
- 同步状态
- 最后同步时间

---

## 平台集成

### WindowsVoiceTyping.java - Windows 语音输入

**功能**: 通过 JNA 调用 `SendInput` 发送 Win+H 组合键。

**方法**:
| 方法 | 说明 |
|------|------|
| `isWindows()` | 判断是否为 Windows 系统 |
| `trigger()` | 触发 Win+H 语音输入 |

### WindowsVoiceRelayService.java - Windows 语音中继

**功能**: 拦截键盘 F17/F18 按键，触发系统语音输入。

**方法**:
| 方法 | 说明 |
|------|------|
| `getInstance()` | 单例获取实例 |
| `configure(studioState, workMode)` | 配置状态供应者 |
| `updateRoutes(state)` | 更新语音路由 |
| `start()` | 启动键盘钩子 |
| `stop()` | 停止键盘钩子 |
| `simulateVoiceKeyTap(mode)` | 模拟语音键点击 |
| `listeningProperty()` | 监听状态属性 |
| `statusMessageProperty()` | 状态消息属性 |

**内部类**:
```java
record VoiceRoute(int vkCode, ModeSlot mode, boolean factoryFallback) {}
```

---

## 工具类

### StudioStore.java - 草稿持久化

**路径**: `~/.ahakey/studio-draft.json`

| 方法 | 说明 |
|------|------|
| `save(draft)` | 保存草稿到文件 |
| `loadOrDefault()` | 加载草稿，不存在则返回默认 |

### ConfigStore.java - 配置存储

**路径**: `~/.ahakey/`

| 方法 | 说明 |
|------|------|
| `saveKeyMappings(keys)` | 保存按键映射 |
| `loadKeyMappings()` | 加载按键映射 |
| `save(key, value)` | 保存任意配置 |
| `load(key, type)` | 加载配置 |

### Icons.java - 图标工厂

使用 Windows Segoe MDL2 Assets 字体提供图标。

**方法**:
| 方法 | 返回图标 |
|------|---------|
| `bluetooth(size)` | 蓝牙图标 |
| `bluetoothConnected(size)` | 已连接蓝牙 |
| `battery(size, level)` | 电量图标 |
| `settings(size)` | 设置图标 |
| `keyboard(size)` | 键盘图标 |
| `display(size)` | 显示器图标 |
| `lightbulb(size)` | 灯泡图标 |

---

## BLE 通信流程

### 连接流程

```
1. userConnect() 
   ↓
2. BleManager.connect()
   ├─ 创建 TCP Socket
   ├─ 启动 readerThread 读取数据
   └─ 查询设备状态
   ↓
3. readerThread 接收数据
   ├─ 解析 BleTcpPacket
   ├─ 解析 AhaKeyResponseParser
   └─ 回调 onStatusReceived()
   ↓
4. StudioController.applyBleStatus()
   └─ 更新 UI 状态
```

### 命令响应流程

```
1. sendCommandExpecting(cmd, expected)
   ↓
2. 获取 commandLock 锁
   ↓
3. pendingNotifyFrame = null
   ↓
4. sendCommand() 发送命令
   ↓
5. waitForResponse(expectedCmd)
   ├─ 循环等待直到超时或收到响应
   ├─ 使用 Condition.awaitNanos() 挂起线程
   └─ readerThread 收到响应后调用 notify
   ↓
6. 返回响应数据
```

### 大数据写入流程（OLED）

```
writeLargeData(address, data)
   ↓
计算分块数 (data.length / 4096 + 1)
   ↓
循环 for each chunk:
   ├─ prepareWrite(chunkLen, chunkAddr)
   │   └─ 等待 CMD_PREPARE_WRITE (0x80) 响应
   ├─ writeData(chunk)
   │   └─ 等待 CMD_WRITE_RESULT (0x81) 响应
   └─ chunkAddr += 4096
   ↓
写入完成
```

---

## 环境变量

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `AHAKEY_BLE_HOST` | 127.0.0.1 | BLE 桥 IP 地址 |
| `AHAKEY_BLE_PORT` | 9000 | BLE 桥端口 |
| `AHAKEY_STUDIO_SIMULATE_BLE` | false | 是否模拟 BLE 连接 |

---

## 依赖关系图

```
App.java
    └── StudioController.java
            ├── DeviceStatus.java (状态数据)
            ├── StudioState.java (状态管理)
            ├── AgentManager.java (Hook 管理)
            ├── VoiceRelayPlatform.java (语音平台)
            │       └── WindowsVoiceRelayService.java
            │               └── WindowsVoiceTyping.java
            └── BleManager.java (BLE 通信)
                    ├── AhaKeyProtocol.java (协议定义)
                    ├── AhaKeyResponseParser.java (响应解析)
                    └── BleTcpPacket.java (数据包编解码)

OledUploadService.java
        ├── BleManager.java
        ├── OLEDFrameEncoder.java
        └── AhaKeyProtocol.java

DeviceSyncService.java
        ├── BleManager.java
        └── AhaKeyProtocol.java

StudioState.java
        ├── StudioStore.java (持久化)
        ├── ModeSlot.java (枚举)
        ├── StudioPart.java (枚举)
        ├── KeyConfig.java (模型)
        └── OledModeDraft.java (模型)

View 组件
        ├── TopBar.java
        ├── CanvasPane.java
        │       └── CanvasController.java (FXML)
        ├── InspectorPane.java
        └── StatusBar.java
```

---

## 关键设计模式

### 1. 单例模式
- `WindowsVoiceRelayService.getInstance()`
- `VoiceInputManager.getInstance()`

### 2. 观察者模式（JavaFX Properties）
- `StudioState.selectedModeProperty().addListener(...)`
- 所有 `Property` 对象均可监听变更

### 3. 生产者-消费者模式
- BLE 数据通过 `BlockingQueue` 或 `wait/notify` 传递
- OLED 上传使用单独的 `Thread` 执行

### 4. 门面模式
- `VoiceRelayPlatform` 为跨平台提供统一接口
- 内部封装各平台的实现细节

### 5. 策略模式
- `VoicePreset` 定义不同的语音输入策略
- `LightEffectStyle` 定义不同的灯效样式

---

## 配置文件格式

### studio-draft.json

```json
{
  "revision": 1,
  "lightBarPreviewId": "aiRunning",
  "modes": [
    {
      "key1Hid": 109,
      "key1Desc": "Record",
      "key2Hid": 89,
      "key2Desc": "Approve",
      "key3Hid": 78,
      "key3Desc": "Reject",
      "key4Hid": 40,
      "key4Desc": "Enter",
      "oledSummary": "上传成功",
      "oledCaption": "预览动画中",
      "oledGifPath": null,
      "oledFps": 10,
      "oledFrameCount": 0,
      "voicePresetId": "WINDOWS_NATIVE"
    },
    // ... MODE1, MODE2 similar structure
  ]
}
```

---

## 注意事项

1. **BLE 连接保活**: 通过每 3 秒轮询一次状态，超过 15 秒无响应则认为断开
2. **线程安全**: BLE 命令操作使用 `ReentrantLock` 保护
3. **UI 线程**: 所有 UI 更新必须通过 `Platform.runLater()` 执行
4. **资源释放**: 应用关闭时需调用 `shutdown()` 停止轮询、断开 BLE 连接
5. **OLED 文件限制**: 最大 2MB，最多 74 帧，每帧 160×80 像素

---

*文档生成时间: 2026-05-28*
