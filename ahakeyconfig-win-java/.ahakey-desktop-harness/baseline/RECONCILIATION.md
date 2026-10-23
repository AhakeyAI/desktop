# 当前仓库与旧调查核对记录

状态：FIRST_RUN_DLA / BASELINE_ADOPT / DISCOVER 已完成第一轮源码核验；未批准产品基线。

## 当前工程身份

- 采样日期：2026-09-26
- Windows 工程目录：`C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java`
- Git 顶层：`C:\Users\20825\Desktop\windows软件代码\desktop`
- 当前分支/HEAD：`main-anpx...origin/main-anpx` / `0da59ce`
- 当前工作区状态：`AGENTS.md` 已修改；`.agents/`、`.ahakey-desktop-harness/`、`.gitignore`、`AhaKey-Windows-Desktop-Harness-v0.2.0-pilot/` 未跟踪。生产 `src/`、`pom.xml` 在本轮未修改。
- 构建标记：`pom.xml` 存在，artifact `ahakey-studio`，版本 `1.0.0`，Java/JavaFX 17。
- Harness 校验：`desktop.py doctor/status/validate` 已运行；结构 PASS 仅代表记录结构可读，不代表产品、UI 或设备验证。
- 编译验证：默认 `mvn -q -DskipTests compile` 失败，原因是 Maven 当前使用 Java 8 runtime，无法编译目标 17；命令行 `java -version` 为 17，但 `mvn -version` 显示 Java `1.8.0_472`。临时设置 `JAVA_HOME=D:\jdk-17.0.19.10-hotspot` 后，`mvn -q -DskipTests compile` 通过。

## 核对清单

| 领域 | 旧调查线索 | 当前源码/工具证据 | 状态 | 对当前工作的影响 |
|---|---|---|---|---|
| Repository/Build | Java 17 + JavaFX，artifact 版本 `1.5.3`，存在 release/update/firmware 包与大量测试 | `pom.xml` 版本为 `1.0.0`；依赖 JavaFX/Jackson/JNA/SLF4J/Logback/ONNX Runtime；无 `src/test/java`；未见 `firmware`、`update` 包 | 部分 confirmed，部分 stale | 旧测试覆盖和 release/update 结论不能继承；当前基线要按较小工程重建 |
| UI/用户旅程 | 单窗口 `TopBar + CanvasPane + InspectorPane + StatusBar`，设备信息长弹窗含维护/Hook/日志 | `App.java` 组装上述四块；窗口标题 `AhaKey Studio`，默认 1280x820，最小 800x600；`TopBar.showDeviceInfoDialog()` 当前主要是设备摘要、Hook 卡片、日志与连接按钮 | 核心布局 confirmed，维护内容 stale/缩小 | Preserve 主窗口骨架；不要按旧调查假设存在完整维护页 |
| Architecture/状态归属 | `StudioController` 总线，`WorkModeSynchronizer`、`ApprovalService` 等边界 | `StudioController`、`BleManager`、`DeviceSyncService` 存在；未发现 `WorkModeSynchronizer`、`ApprovalService`、`PhysicalStatusFreshness`、`StatusRefreshScheduler` 等类 | 部分 confirmed，部分 stale | 当前状态保护更集中在 `StudioController/BleManager`，不可按旧深层模块名写 Contract |
| USB/BLE/协议/版本 | USB 优先、BLE TCP 9000 兜底；协议含 `0x9F capability` 等 | USB HID 匹配 `VID_413C/PID_2107`，优先 `MI_01/COL02`；BLE bridge `127.0.0.1:9000`；协议帧 `AA BB ... CC DD`；当前 `AhaKeyProtocol` 未定义 `0x9F` capability/version contract | transport confirmed，capability 旧结论 stale/unknown | 旧固件能力门禁不可直接使用；版本/能力关系需 Firmware 正式定义或真机证据 |
| Feature 链路/技术债 | 配置保存、语音、Hook、OLED/GIF、固件更新、更新发布均较完整 | 当前存在配置、语音、Hook、OLED/GIF、BLE driver 打包脚本；未见 Java 侧固件更新服务、应用更新 client、WCHISP 类 | 部分 confirmed，部分 stale | 商品机旅程候选应聚焦当前真实入口：连接、配置保存、语音/AhaType、Hook/OLED；固件更新暂不列为已存在主旅程 |

## Preserve 候选

- 单窗口工作台结构：TopBar 承载连接与模式入口，CanvasPane 做键盘/部件预览，InspectorPane 做局部配置，StatusBar 反馈状态。
- `StudioController` 作为用户动作编排中心，保留其连接、编辑、保存、返回键盘控制的用户流程边界。
- `BleManager` 同时管理 USB HID 与 BLE TCP bridge，当前命名虽偏 BLE，但真实承担 transport 选择与命令响应等待，改动半径大。
- `AhaKeyProtocol` / `AhaKeyResponseParser` / `BleTcpPacket` 集中表达桌面侧协议编码、响应解析和 bridge packet。
- `DeviceSyncService.commandsForModes()` 把本地草稿转为设备命令序列，是配置保存旅程的重要映射点。
- 本地草稿持久化 `StudioStore` 与未连接时保留本地编辑的体验。

## 历史问题与当前缺口

- 旧调查明显来自更大或不同版本：版本号、测试目录、firmware/update 包、能力查询 `0x9F`、维护页内容均与当前源码不完全一致。
- 当前没有运行截图，UI 视觉只基于源码结构推断；不能当作真实视觉验收。
- Firmware path 未绑定；Windows-only baseline 可继续，但任何设备语义、能力支持、ACK 是否代表 applied/persisted 均不能替代固件正式定义。
- BLE driver exe 的真实 GATT 行为仍未知；`ble_bridge.py` 只能作为参考，不代表当前 exe 已验证。
- 机器编译已在临时 JDK 17 环境下通过；默认 Maven/JAVA_HOME 仍需修正，避免后续误用 Java 8。
