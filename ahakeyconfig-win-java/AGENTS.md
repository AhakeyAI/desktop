# ahakeyconfig-win-java

## 项目结构

Java 17 Maven 单模块项目，基于 **JavaFX 17** 构建的桌面应用程序，用于键盘设备配置和语音输入功能。

项目采用经典的分层架构：

```
src/main/java/com/example/ahakey/
├── app/              # 应用控制器层（MVC 的 Controller）
├── config/           # 配置类（ModelConfig）
├── model/            # 数据模型（状态、配置、协议等）
├── platform/         # 平台相关代码（语音、键盘钩子）
│   └── windows/      # Windows 平台特定实现
├── protocol/         # 协议处理层（BLE TCP 通信协议）
├── service/          # 核心服务层（业务逻辑）
├── sherpa/           # Sherpa-ONNX 语音识别集成
├── util/             # 工具类
└── view/             # UI 视图组件
```

## 可部署应用

| 应用 | 入口类 | 用途 |
|------|--------|------|
| AhaKeyStudio | `com.example.ahakey.App` | 键盘配置 Studio（设备管理、宏编程、语音输入） |

**应用启动方式：**
- IDE 运行：`mvn javafx:run`
- 打包后运行：`java -jar ahakey-studio-1.2.0.jar`
- 安装包运行：`AhaKeyStudio-xxx.exe`（通过 jpackage 生成）

## 配置

- 应用配置：`src/main/resources/model_config.properties` — 语音模型路径、流式模式开关等
- 日志配置：`src/main/resources/logback.xml` — Logback 日志配置
- 模型文件：`src/main/resources/models/` — Sherpa-ONNX 语音识别模型

## 构建

```bash
# 编译项目
mvn clean compile

# 运行应用（需 JavaFX 环境）
mvn javafx:run

# 打包为可执行 JAR
mvn clean package

# 打包为 Windows 安装包（需 jpackage）
powershell -ExecutionPolicy Bypass -File build-installer.ps1
```

**构建脚本：**
- `build-exe.bat` — Windows 批处理构建脚本
- `build-exe.ps1` — PowerShell 构建脚本
- `build-installer.ps1` — 生成 Windows 安装包（.exe）

## 技术栈要点

- **JavaFX 17.0.10** — 桌面 UI 框架（Controls + FXML + Graphics）
- **Jackson 2.16.0** — JSON 序列化/反序列化
- **JNA 5.14.0** — Java Native Access（调用 Windows API）
- **SLF4J 2.0.9 + Logback 1.4.11** — 日志框架
- **Sherpa-ONNX 1.13.3** — 离线语音识别（支持中英文双语）
- **Lombok 1.18.30** — 代码简化（可选）

## 模块职责

### app 层（控制器）

负责 UI 交互和业务协调：

- `StudioController.java` — 主界面控制器，管理设备连接、宏编辑等
- `VoiceInputController.java` — 语音输入面板控制器

### service 层（核心服务）

封装所有业务逻辑：

| 服务类 | 职责 |
|--------|------|
| `SpeechService.java` | 语音识别核心服务（Sherpa-ONNX 集成） |
| `VoiceInputManager.java` | 语音输入管理（录音、识别、输出） |
| `BleManager.java` | BLE 设备连接管理 |
| `AgentManager.java` | 蓝牙代理管理 |
| `DeviceSyncService.java` | 设备配置同步 |
| `KeyboardInjector.java` | 键盘事件注入 |
| `HookClient.java` / `HookDispatchServer.java` | 低级别键盘钩子 |
| `UsbHidTransport.java` | USB HID 通信 |
| `SocketServer.java` | TCP Socket 服务端（BLE 桥接） |
| `KimiAhaKeyBridge.java` | Kimi AI 集成 |

### platform/windows 层

Windows 平台特定实现：

- `WindowsVoiceRelayService.java` — 语音输入路由（本地模型 / Win+H）
- `WindowsVoiceTyping.java` — Windows 语音输入 API 封装

### protocol 层

通信协议处理：

- `AhaKeyProtocol.java` — 键盘设备协议
- `AhaKeyResponseParser.java` — 响应解析器
- `BleTcpPacket.java` — BLE TCP 数据包解析

### model 层

数据模型：

- `DeviceStatus.java` — 设备状态
- `KeyConfig.java` — 按键配置
- `StudioState.java` — Studio 应用状态
- `VoicePreset.java` — 语音预设
- `ModeSlot.java` — 模式插槽

### view 层

UI 组件：

- `CanvasController.java` — 键盘画布控制器
- `CanvasPane.java` — 键盘画布面板
- `TopBar.java` — 顶部工具栏（含 BLE 驱动按钮，支持长按杀进程）
- `StatusBar.java` — 状态栏
- `InspectorPane.java` — 属性检查面板
- `FloatingVoiceNotification.java` — 语音输入浮动通知

## 编码规范

### 命名规范

- 类名：大驼峰（PascalCase）
- 方法名：小驼峰（camelCase）
- 变量名：小驼峰（camelCase）
- 常量名：全大写，下划线分隔（UPPER_CASE）

### 依赖注入

使用构造器注入或字段注入，优先使用 `@Resource` 或直接声明字段。

### 异常处理

- 语音识别错误：捕获并记录日志，显示用户友好提示
- JNI 调用错误：捕获 `UnsatisfiedLinkError`，提示原生库加载失败
- 网络/蓝牙错误：优雅降级，保持应用可用

### 资源管理

- 原生库（JNI）通过 `LibraryLoader.java` 加载
- 语音模型文件在 `SpeechService.initialize()` 中初始化
- 关闭应用时调用 `dispose()` 释放资源

## 语音识别核心流程

```
用户按下录音键（F18）
  → WindowsVoiceRelayService 路由判断
    → 语音输入已激活 → SpeechService 本地识别
    → 语音输入未激活 → Win+H 系统语音
  → SpeechService.startRecording() 开始录音
  → VoiceInputManager 管理录音状态
  → SpeechService.stopRecording() 停止录音
  → SpeechService.recognize() 识别音频
  → 识别结果 → KeyboardInjector 注入按键
```

### 本地识别模式

使用 Sherpa-ONNX 离线模型进行语音识别：

- 模型文件：`models/encoder.int8.onnx`, `models/decoder.int8.onnx`, `models/tokens.txt`
- VAD 模型：`models/silero_vad.onnx`
- 标点符号模型：`models/punct_model.onnx`（可选，需配置 `punct.enabled=true`）
- 流式/非流式模式：通过 `model_config.properties` 中的 `model.type` 配置

### 系统语音模式

调用 Windows 自带语音输入（Win+H），通过 JNA 调用 Windows API。

## BLE 驱动管理

### BLE 驱动按钮功能

- **短按**：启动/重启 `BLE_tcp_driver.exe`（BLE 桥接工具）
- **长按5秒**：强制杀死所有 `BLE_tcp_driver.exe` 进程（包括挂起的卡死进程）

### BLE 进程清理

- 应用退出时（点击托盘 Exit）：自动停止 `BLE_tcp_driver.exe` 进程
- 连接断开时：停止定时轮询，保持 BLE 连接不断开

## 构建产物

```
target/
├── classes/          # 编译后的 class 文件
├── lib/              # 依赖 JAR（jackson, jna, logback, javafx 等）
├── jpackage-resources/ # jpackage 资源
├── ahakey-studio-1.2.0.jar # 可执行 JAR
└── installer/        # Windows 安装包（.exe, .zip）
```

## 常见问题

### JVM 崩溃（hs_err_pidxxx.log）

通常是 Sherpa-ONNX 原生库加载失败或模型文件损坏：

1. 检查 `sherpa-onnx/native/win-x64/` 目录下的 DLL 文件是否完整
2. 检查模型文件是否为空
3. 确保模型文件已正确放置在 `models/` 目录下

### 语音输入无响应

1. 检查 `model_config.properties` 中模型路径配置正确
2. 检查语音输入是否已激活（UI 上点击"启动语音输入"）
3. 检查录音键是否正确映射（默认 F18）

### BLE 连接失败

1. 检查 BLE 适配器是否启用
2. 检查设备是否在蓝牙范围内
3. 检查 `BLE_tcp_driver.exe` 是否正常运行（BLE 桥接工具）
4. 如果 BLE 进程卡死，长按 BLE 驱动按钮5秒强制杀死

<!-- AHAKEY-DESKTOP-HARNESS:BEGIN -->
## AhaKey Windows Harness 1.3.0
正式项目入口：根 AGENTS + `.agents/skills/ahakey-desktop-{lead,builder,harness}`。历史 backups/bundle-staging 不作为入口。
主流程：Owner Task → DLA CHANGE → DIB IMPLEMENT → DLA VERIFY → 可选 Release Batch。Owner 排期；官网接收，eternal/Firmware只读。
CHANGE 未批准不得实现；新任务必须绑定 Journey Registry 与 change classification。scope expansion / architecture / protocol 变化回 CHANGE；architecture/protocol 强制高影响独立审阅。
DIB 仅在 IMPLEMENT/FIX/BUILD_ONLY 合法模式开工；submit 后进入 VERIFY/DLA_REVIEW。失败证据允许保存，但不自动使漂移代码合格。
每轮正式交测绑定 Git candidate、Artifact identity、Firmware identity和实际测试包。JAR 通过不代表 EXE/安装包通过。
Release Batch 只由 Owner 显式启动；累计约5个已关闭JAR增量时可提醒，不能自动创建。启动时必须询问 Lite / Local Model / Both；两版是同一应用二选一可切换。
每轮按 OWNER_COMMUNICATION 面向Owner汇报：上一步做什么、Owner决策/操作/测试、当前状态、下一动作，并在当前聊天正文完整显示可复制 Prompt。
不自动Git写、构建、下载模型、kill进程、安装、设备写入、烧录、发布。Harness问题不能由实现Agent自行降低规则。
<!-- AHAKEY-DESKTOP-HARNESS:END -->


### Firmware-driven Windows intake
Firmware 只读来源已绑定时，Windows DLA 应主动从 Firmware Harness 的正式 state、Journey/Module、Gate、artifact、协议、实现与测试证据发现下一联调阶段。不得要求 Owner 手工提供仓库内已存在的 HEX 路径、SHA256、commit、command/request/response 或测试证据。
用 Windows 侧 `firmware-sync.json` 记录 last-consumed cursor；多个同等有效 gate 才请求 Owner 选优先级。发现/绑定不等于批准、实现或测试，不自动切换当前 Active Implementation。
