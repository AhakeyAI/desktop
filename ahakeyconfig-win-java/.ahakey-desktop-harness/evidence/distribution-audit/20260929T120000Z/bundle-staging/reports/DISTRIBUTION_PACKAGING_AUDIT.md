# AhaKey Windows Distribution / Packaging Audit

时间：2026-09-29T12:00:00+08:00  
角色：固定 Windows DLA  
范围：只读调查 + 新增本报告/导出包；未修改源码、Harness schema、WD-001 封存记录、target 产物或 Git。

## 结论摘要与事实等级

| 结论 | 事实等级 |
|---|---|
| 接收仓当前只有一个 Maven 模块、一个应用名 `AhaKeyStudio`、一个 JAR 坐标 `com.example:ahakey-studio:1.0.0`。两种发行形态不是两个入口类，也不是“接收仓 vs eternal 仓”。 | A/B |
| 接收仓脚本用 `src/main/resources/model_config.properties` 的 `model.enabled` 分支区分打包输入：true 时复制 `models/model_q8.onnx`/`tokens.txt` 并保留 ONNX；false/缺省时从包输入中移除模型和 `onnxruntime`。 | B |
| 接收仓当前配置没有 `model.enabled=true`，只有 `status.poll.period.seconds=5`；代码默认 `model.enabled=false`，所以当前运行时跳过本地模型语音输入。 | A/B |
| “不带模型”仍保留 Windows 系统语音/Win+H 路由相关能力；本地模型按钮/UI会被隐藏或不可用，但 `VoicePreset.WINDOWS_NATIVE` 与 `WindowsVoiceRelayService` 仍在共同源码里。 | B |
| 当前 WD-001 JAR 是 JAR 联调包，不是已完成的轻量 EXE，也不是带模型 EXE。它的 `model_config.properties` 为默认禁用模型，JAR 内无 `models/*`；但 `target/lib` 仍存在 `onnxruntime-1.16.3.jar`，因为它来自普通 Maven package，而不是经过脚本的轻量后处理。 | A |
| 来源仓（eternal，只读）有更正式的发布脚本和 1.5.4 发行链，强制 Sherpa/模型/WCHISP/安装器签名等；这能证明历史/正式发布方向，但不能冒充接收仓 WD-001 当前候选已执行的路径。 | B |
| 当前 Harness 已记录 WD-001 到 OWNER_TEST，已有审阅、Git candidate、构建收据、固件身份和测试包；它还没有结构化记录“发行版 x 交付形式 x 模型包身份 x 批次覆盖”。 | A |

事实等级：
- A：Harness 或当前磁盘稳定记录，后续新对话可读取。
- B：源码/脚本中存在，但 Harness 未结构化绑定为发行事实。
- C：Owner 产品要求，尚未找到完整实现依据。
- D：必须运行构建、安装、启动或真机测试才能确认。

## 当前源码、候选、三仓身份

| 项 | 当前取证 |
|---|---|
| 接收仓 | `C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java`，Git HEAD `666494c358fd5373b27b6213e9f4a35a424dd2c6`。 |
| 来源仓（只读） | `C:\Users\20825\Desktop\windows软件代码-eternal版本\desktop\ahakeyconfig-win-java`，Git HEAD `9d098348f34f9e6f04f1f94bbaa428ff2332115a`。 |
| Firmware（只读） | `C:\Users\20825\Desktop\vibe-code`，Git HEAD `a9db65e2e73bc56b669c312e9fc42f3ee02c3d49`。 |
| WD-001 状态 | `.ahakey-desktop-harness/STATE.json` 为 `BUILD_VERIFY / OWNER_TEST / awaiting_owner_test`，next actor Owner。 |
| 只读工具结果 | `status` 显示 WD-001 OWNER_TEST；`validate` 为 RECORD STRUCTURE PASS；`guard-status --id WD-001` 输出审阅、Git candidate、runnable build receipt、Owner test packet 均 PASS，但这不是产品测试通过。 |

## 两种发行版的代码、UI、模型与运行差异表

| 维度 | 轻量/不带模型形态 | 带模型形态 | 证据 |
|---|---|---|---|
| 实际名称 | 脚本没有独立品牌名；仍使用 `AhaKeyStudio`。报告中仅称“轻量/不带模型形态”。 | 脚本没有独立品牌名；仍使用 `AhaKeyStudio`。报告中仅称“带模型形态”。 | `build-exe.ps1:10-12`, `build-installer.ps1:10-12`。 |
| 源码入口 | 共同源码、共同 `com.example.ahakey.App`。 | 共同源码、共同 `com.example.ahakey.App`。 | `pom.xml:7-10`, `pom.xml:141-145`, `build-exe.ps1:147-160`。 |
| 当前接收仓区分开关 | `model.enabled` 不存在或不为 true 时，脚本按 false。当前资源文件只有 `status.poll.period.seconds=5`。 | `model.enabled=true` 时脚本复制模型文件并保留 ONNX。 | `src/main/resources/model_config.properties:1`, `build-exe.ps1:70-110`, `build-installer.ps1:70-108`。 |
| 本地模型初始化 | `ModelConfig.DEFAULT_MODEL_ENABLED=false`，`App.start()` 跳过 `VoiceInputManager`。TopBar 隐藏模型语音控件及 AhaType 菜单项。 | `App.start()` 初始化 `VoiceInputManager`；TopBar 加入 AhaType/本地语音控件。 | `ModelConfig.java:37-99`, `App.java:106-143`, `TopBar.java:208-329`。 |
| 系统语音 / Win+H | 仍保留：`VoiceRelayPlatform` 直接封装 Windows Win+H 路由；`VoicePreset.WINDOWS_NATIVE` 是共同模型配置的一部分。 | 同样保留。 | `VoiceRelayPlatform.java:15-49`, `WindowsVoiceRelayService.java:27-30`, `VoicePreset.java:27-35`。 |
| 模型文件 | 接收仓当前没有 `src/main/resources/models` 目录；轻量脚本会移除包输入中的 `models/*` 和 `onnxruntime*.jar`。 | 接收仓脚本期望 `src/main/resources/models/model_q8.onnx` 与 `tokens.txt`。若不存在，实际运行带模型打包会失败；本轮未运行。 | `build-exe.ps1:90-110`, `build-installer.ps1:90-108`。 |
| 来源仓正式模型 | 不适合作为接收仓当前轻量实现依据。 | 来源仓正式 release 链要求 `encoder.int8.onnx`、`decoder.int8.onnx`、`silero_vad.onnx`、`tokens.txt`，并禁止 `model_q8.onnx` 混入正式 release input。 | 来源仓 `build-release-installer.ps1:324-337`, `Test-ReleaseArtifactContents.ps1:92-100`。 |
| 非语音设备功能 | WD-001 的 More/设备信息、BLE/USB 命令、协议 `0x95` 在共同源码，不受 `model.enabled` 分支约束。 | 同左。 | `TopBar.java:998-1000`, `TopBar.java:1117-1223`, `AhaKeyProtocol.java:24,81-97`, `BleManager.java:257-300`。 |

说明：接收仓当前脚本里的“带模型形态”使用 SenseVoice `model_q8.onnx` 命名；来源仓正式链使用 Sherpa streaming Paraformer 多文件模型。二者不能混为同一已验证交付链。

## 两版打包链、参数、输入/输出/安装路径表

### 接收仓当前脚本链

| 入口 | 形式 | 关键参数/默认 | 输入 | 输出 | 副作用/风险 |
|---|---|---|---|---|---|
| `build-exe.ps1` | `jpackage --type app-image`，免安装应用目录，不是安装器 EXE。 | 无发行版参数；用 `src/main/resources/model_config.properties` 推导模型分支。 | `target/ahakey-studio-1.0.0.jar`, `target/lib`, `VibeCodeKeyboard.ico`, 可选 `BLE_tcp_driver.exe`。 | `target/installer/AhaKeyStudio`。 | 会运行 Maven package、删除旧 `target/installer`、清理 `target/jpackage-input` 和 `target/runtime`，可能复制 BLE 驱动；不签名。见 `build-exe.ps1:28-199`。 |
| `build-installer.ps1` | `jpackage --type exe`，安装器 EXE。 | 无发行版参数；同样用 `model.enabled` 分支；`-Dapp.version` 为时间戳。 | 同上，外加 WiX/NSIS 工具链。 | `installer/AhaKeyStudio-<timestamp>.exe`。 | 会运行 Maven package、创建/清理临时目录、复制 BLE 驱动、调用 jlink/jpackage、重命名安装器；不自动签名。见 `build-installer.ps1:40-207`。 |
| `build-exe.bat` | `jpackage --type exe`，旧批处理安装器脚本。 | 无发行版参数；`mvn clean package -DskipTests` 后直接改 `target/lib` 和 JAR。 | `target` 目录、JDK/Maven、BLE 驱动候选。 | `target/installer/AhaKeyStudio-1.0.0.exe`。 | 会执行 `clean`、删除 `target/lib\onnxruntime*.jar`、直接更新 target JAR、删除 jlink/installer 目录；比 ps1 更容易覆盖当前候选。见 `build-exe.bat:46-77,113-167`。 |

最小静态配方（未执行，本轮不授权运行）：
- 轻量 app-image：保持当前 `model_config.properties` 无 `model.enabled=true`，运行 `powershell -ExecutionPolicy Bypass -File .\build-exe.ps1`。
- 带模型 app-image：先有合法 `src/main/resources/models/model_q8.onnx` 与 `tokens.txt`，并在 `model_config.properties` 声明 `model.enabled=true`，再运行同脚本。
- 轻量安装器：同轻量配置，运行 `powershell -ExecutionPolicy Bypass -File .\build-installer.ps1`。
- 带模型安装器：同带模型配置，运行 `build-installer.ps1`。

这些配方只是脚本静态推导；本轮没有验证构建、安装、启动或设备。

### 来源仓正式发布链（只读参考）

| 入口 | 形式 | 关键参数 | 输入/输出 |
|---|---|---|---|
| 来源仓 `build-installer.ps1` | 兼容入口，转调 `build-release-installer.ps1`。 | `-FirmwareHex`, `-BaselineInstallDir`, `-AppVersion`, `-FirmwareVersion`, `-WchIspBundleDir`, `-IncludeLicensedWchIsp`, `-PrepareOnly` 等。 | 来源仓 `build-installer.ps1:1-40`。 |
| 来源仓 `build-release-installer.ps1` | 正式 `jpackage --type exe` 安装器。 | 强制 `FirmwareVersion`，校验 `AppVersion` 与 pom，使用 baseline runtime/icon/model/native DLL。 | 输出 `installer\AhaKey-Studio-<version>-Setup.exe` 和稳定副本 `AhaKey-Studio-Setup.exe`；见来源仓 `build-release-installer.ps1:1-15,70-92,383-507`。 |

来源仓正式链说明：
- 使用当前 Maven JAR，不复制旧 Java 类；旧 baseline 只提供 runtime/model/icon/原生 DLL 等非 Java 资源，见来源仓 `build-installer.ps1:28-31` 和 `build-release-installer.ps1:74-80,143-199`。
- 强制正式模型文件：`encoder.int8.onnx`、`decoder.int8.onnx`、`silero_vad.onnx`、`tokens.txt`；这是带模型正式发布路径，见来源仓 `build-release-installer.ps1:324-337`。
- 安装身份固定 `AhaKeyStudio`、安装目录 `AhaKeyStudio`、菜单组 `AhaKey`、upgrade uuid 固定；两版若共用同一身份会有覆盖/升级顺序风险，但是否要共存是产品决策，不自动判定为 bug。见来源仓 `build-release-installer.ps1:383-405`。

## 当前 WD-001 JAR 分类与可复用证据

当前 JAR：
- 路径：`C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\target\ahakey-studio-1.0.0.jar`
- SHA256：`C16F5BAD0F518FB8FEA00F7DEE7F97CAAF7AC6DC3865092442A2BEE260217886`
- Manifest Main-Class：`com.example.ahakey.App`
- Manifest Class-Path 包含 `lib/onnxruntime-1.16.3.jar`
- JAR 内存在 `model_config.properties`，内容为 `status.poll.period.seconds=5`
- JAR 内未发现 `models/*`
- `target/lib` 当前有 17 个依赖 JAR，包含 `onnxruntime-1.16.3.jar`

分类：当前 WD-001 JAR 是“共享 Maven JAR + 当前配置禁用本地模型”的联调包。它不是：
- 已经 post-process 删除 ONNX/runtime 的轻量安装形态；
- 已经携带模型文件/模型 UI 验证结果的带模型安装形态；
- 两版 EXE 验收包。

WD-001 非语音调用链为共同源码：`TopBar.showDeviceInfoDialog()` 把睡眠等待时间控件放在第一个设备信息卡片，调用 `BleManager.readSleepWaitTimeMinutes()` / `setSleepWaitTimeMinutesAndVerify()`，再进入 `AhaKeyProtocol` 的 `0x95` query/set。见 `TopBar.java:998-1000,1117-1223`、`BleManager.java:257-300`、`AhaKeyProtocol.java:24,81-97`。未发现 WD-001 改动触碰本地模型初始化或语音服务逻辑。

## 当前 Harness 认知覆盖与缺口

| 分类 | 本轮结论 |
|---|---|
| A. Harness 已稳定记录 | v0.4.0 + hf01；WD-001 owner task/approval/Contract/References/start/builder submission/review/candidate/build receipt/firmware identity/OWNER_TEST/test_packet；STATE 指向 OWNER_TEST。 |
| B. 源码/脚本里有但 Harness 未绑定 | 接收仓 `model.enabled` 双分支；app-image vs installer EXE；target/lib 模型/ONNX差异；来源仓正式 release 链；安装身份/输出目录/覆盖风险。 |
| C. Owner 产品要求但实现依据不足 | “每个最终/批次打包分别提供轻量版和带模型版”目前没有接收仓内的正式批次字段、发行版字段或双产物命名规则。 |
| D. 需运行确认 | 两版脚本实际是否成功、带模型资源是否齐全、EXE安装/升级/卸载行为、应用启动、模型加载、语音 UI 体验、设备真机 UAT。 |

现有 `BUILD_RECEIPT.json` / `test_packet.json` 缺口：
- 只绑定 `target` 和当前 JAR/runtime 文件，不区分轻量版/带模型版。
- 不区分 JAR、app-image、安装器 EXE、正式发布 EXE。
- 不记录模型包身份、模型文件列表、原生 DLL/JNI 身份或是否 post-process 删除 ONNX。
- 不记录双版输出路径、批次覆盖、安装身份冲突或两版测试结果。

最小新版设计建议（本轮未实现）：
- `distribution_variant`: `jar-default`, `lite-no-local-model`, `model-bundled`, `formal-release-model`。
- `delivery_form`: `jar_classpath`, `jpackage_app_image`, `jpackage_installer_exe`, `msi/unknown`。
- `model_bundle`: enabled flag、model type、model files、native runtime files、source paths、hashes、missing policy。
- `package_batch`: batch id、variant matrix、artifact paths、per-variant test scope/result。
- `install_identity`: app name、install dir、menu group、upgrade uuid、config dir、coexistence/overwrite note。

## WD-001 升级接续必须保持的状态和证据

- 不重置 `start-fingerprint.json`、`guard-origin.json`、`change.json`、Contract、approval、review、candidate、build receipt、firmware identity、OWNER_TEST、test_packet。
- 当前 OWNER_TEST 资格保留；未收到真实 UAT，不得 close。
- 后续若只做两版打包机制升级，应作为独立 Harness/交付治理改进，不把 WD-001 改成 NONE，也不要求 DIB 重写现有实现。
- 若后续要把 WD-001 合并进某个最终 EXE 批次，应生成新的批次/发行版打包收据和两版测试结果，而不是改写当前 JAR 测试包的指纹。

## 未决问题与验证边界

| 项 | 结论 |
|---|---|
| 脚本存在 | 接收仓有 `build-exe.ps1`、`build-installer.ps1`、`build-exe.bat`；来源仓有正式 release 链。已静态核验。 |
| 产物存在 | 当前 WD-001 JAR 和 `target/lib` 存在；未发现当前 app-image/installer EXE 作为 WD-001 候选。 |
| 构建验证 | WD-001 已有 Maven package 构建收据；本轮未运行构建。 |
| 运行验证 | 本轮未启动应用、未加载模型、未连接设备、未执行 Owner 测试。 |
| 两版发行验证 | 当前没有两版 EXE 产物和测试结果；JAR 通过不代表两版 EXE 通过。 |
| 工具链 | `java` 当前为 `D:\jdk-17.0.19.10-hotspot\bin\java.exe`；`mvn -v` 默认绑定 Java 8；WD-001 收据使用临时 `JAVA_HOME=D:\jdk-17.0.19.10-hotspot`。WiX 3.14 存在于 `C:\Program Files (x86)\WiX Toolset v3.14\bin`。 |

## 受保护内容核对

调查前核对：
- JAR SHA256 与 BUILD_RECEIPT 一致：`C16F5BAD0F518FB8FEA00F7DEE7F97CAAF7AC6DC3865092442A2BEE260217886`。
- Firmware HEX 存在，SHA256 与 `FIRMWARE_IDENTITY.json` 一致：`9AABCE5F015FD44D980FF6818D825B6BAB34F6E4B4F7AC277E942272D700444C`。
- `target/lib` 当前 17 个 JAR，包括 `onnxruntime-1.16.3.jar`。

本轮新增文件限定在 `.ahakey-desktop-harness/evidence/distribution-audit/20260929T120000Z/`。未运行构建、打包、clean、安装、产品启动、联网下载、模型加载、设备操作、烧录或 Git 写动作。
