# CURRENT_REPOSITORY_MAP

## 范围

本文件记录 `C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java` 当前代码事实。生产代码未修改。

## 顶层结构

- `pom.xml`: Maven 项目定义，artifact 为 `ahakey-studio`，版本 `1.5.3`。
- `src/main/java/com/example/ahakey`: Java 主代码。
- `src/main/resources`: JavaFX CSS、FXML、语言包、固件能力配置、WCHISP 基线资源、默认 GIF。
- `src/test/java`: JUnit 5 测试。
- `third-party`: vendored `sherpa-onnx-java-api-1.13.3.jar`。
- `packaging/windows`: jpackage/WiX 覆盖文件。
- `build-release-installer.ps1`, `build-installer.ps1`, `build-exe.ps1`, `build-exe.bat`: 打包入口。
- `ble_bridge.py`: Python BLE bridge 参考/旧实现。
- `artifacts`: GIF 布局测试资产。

## Java 技术栈 / UI Framework

- Java 17。
- JavaFX 17.0.10: `javafx-controls`, `javafx-fxml`, `javafx-graphics`。
- UI 主要用 Java 代码构建，局部使用 FXML:
  - `fxml/CanvasLayout.fxml`
  - `fxml/VoiceInputPanel.fxml`
- Jackson 2.16.0 用于 JSON。
- JNA/JNA Platform 5.14.0 用于 Windows native API。
- SLF4J + Logback 用于日志。
- Sherpa-ONNX Java API 以 system scope vendored jar 方式引入。

## 程序入口

- `com.example.ahakey.Main` 只转发到 `App.main(args)`。
- `com.example.ahakey.App` 是 JavaFX `Application` 入口，`pom.xml` 和 jar manifest 都指向 `com.example.ahakey.App`。
- `App.start()` 负责:
  - 单实例检查；
  - 注册退出生命周期；
  - 加载语言；
  - 创建 `StudioController`；
  - 条件初始化 `VoiceInputManager`；
  - 初始化系统托盘；
  - 构建主窗口 `TopBar + CanvasPane + InspectorPane + StatusBar`；
  - 关闭/最小化到托盘逻辑。

## 主包职责

- `app`: 应用编排。`StudioController` 是核心总线；`WorkModeSynchronizer`、`StatusRefreshScheduler`、`ManualApprovalGate`、`ApplicationLifecycle` 管理流程边界。
- `view`: JavaFX 视图。`TopBar`、`CanvasPane`、`InspectorPane`、`StatusBar`、设备维护、屏幕动画、支持/配对指南。
- `service`: BLE/USB 设备管理、配置同步、OLED 上传、Hook 服务、任务活动、审批、语音输入、键盘注入、GIF 资产。
- `protocol`: AhaKey 应用协议编码/解析，以及 BLE-TCP bridge 包格式。
- `model`: `DeviceStatus`、`StudioState`、按键配置、模式、灯效、语音预设等 UI/设备状态模型。
- `firmware`: WCHISP 固件升级、运行时定位、烧录、校验、能力契约。
- `update`: App 更新、远端 release/client config、下载和 Windows installer 执行。
- `platform/windows` 与 `platform/voice`: Windows 低级键盘 hook、语音按键状态机、模拟输入。
- `util`: 本地配置、语言、图标、OLED frame 编码、草稿持久化。
- `sherpa`: Sherpa native library loader。

## Build System

- Maven 构建。
- `maven-compiler-plugin`: Java 17。
- `maven-surefire-plugin`: JUnit 5 测试。
- `javafx-maven-plugin`: main class `com.example.ahakey.App`。
- `maven-resources-plugin`: 复制资源，并在 package 阶段复制 vendored Sherpa jar 到 `target/lib`。
- `maven-jar-plugin`: 生成可执行 jar，并显式写入 `Class-Path`。
- `maven-dependency-plugin`: 复制 runtime dependencies 到 `target/lib`。
- `exec-maven-plugin`: package 阶段运行 `Test-ReleaseArtifactContents.ps1` 校验 release artifact。

## 依赖

主要依赖:

- JavaFX controls/fxml/graphics。
- Jackson databind。
- JNA / JNA Platform。
- SLF4J / Logback。
- Sherpa-ONNX vendored jar。
- JUnit Jupiter 测试依赖。

## 打包 / 发布方式

- 开发 jar: `mvn package`。
- `build-exe.bat`: 历史 jlink + jpackage 打包流程，要求 BLE driver 可用。
- `build-exe.ps1`: 当前为兼容入口，转到 `preview-part3-release-overlay.ps1`。
- `build-installer.ps1`: 当前为兼容入口，转到 `build-release-installer.ps1`。
- `build-release-installer.ps1`: 正式发布入口，执行 release 输入校验、BLE driver staging、可选 WCHISP runtime staging、jpackage、WiX、签名校验和 stable installer 复制。
- `packaging/windows/main.wxs`: WiX 覆盖，记录安装目录到 HKLM `Software\AhaKey\AhaKeyStudio`，控制 upgrade/downgrade，使用 jpackage 文件组。

## Windows-specific Native Dependency

- JNA 调用:
  - `kernel32`, `setupapi`, `hid` 用于 USB HID 枚举、打开、读写、取消 IO。
  - Windows 低级键盘 hook / SendInput / Win+H / F18 路由在 `platform/windows`。
- USB HID 设备匹配:
  - `VID_413C`, `PID_2107`，优先 `MI_01` 或 `COL02`。
- BLE driver:
  - 外部 `BLE_tcp_driver.exe`，默认通过 `BleBridgeProcessOwner` 管理，TCP 端口 9000。
- WCHISP:
  - `WCHISPTool_CH57x-59x.exe`
  - `WCH55xISPDLL.dll`
  - `CONFIG_CH57X59X.WCH`
  - ISP 设备探测包含 `VID_4348&PID_55E0`。

## 当前测试体系

- JUnit 5 测试数量覆盖较多，包包括:
  - `app`: 生命周期、状态刷新、工作模式同步、手动审批 gate。
  - `protocol`: `AhaKeyProtocolTest` 和 protocol fixture。
  - `service`: BLE manager 响应/审批路径、USB HID session、设备同步、OLED/GIF 规则、Hook、Kimi bridge、语音、任务活动。
  - `firmware`: WCHISP runtime/runner/config、固件升级、post verifier、release artifact、Intel HEX。
  - `update`: release client、installer、版本、下载。
  - `view`: 维护页、Inspector voice choices、支持页。
  - `model`/`util`: 状态和持久化。
- 同时存在 PowerShell release validation 脚本。

## UNKNOWN

- 当前仓库没有看到真实固件源码，Firmware responsibility 只能根据 Desktop 命令调用推断为“设备侧处理该命令”，不能证明固件内部实现。
- BLE native driver C#/exe 工程不在本目录内，`BLE_tcp_driver.exe` 的实际 BLE service/characteristic 以 `ble_bridge.py` 和 Java bridge packet 使用事实为证，不能完整代表当前 exe 实现。
