# WD-001 Owner 交测简报预览（不替代封存测试包）

本预览只重新表达现有 WD-001 `OWNER_TEST.md/json` 与本轮发行版调查结论；不是新的测试授权，不修改现有测试包，也不声称 Owner 已测试通过。

## 这次只验证什么

本轮 WD-001 只验证 CP3A “睡眠等待时间” Windows 联调：
- 入口：AhaKey Studio 顶部 More -> “Hawk 安装分发工具” -> 第一个“设备信息”卡片。
- 功能：读取/设置 `永不 / 30 分钟 / 60 分钟 / 120 分钟`。
- 协议：Windows 发送 `0x95 set`，等待 `0x95 OK`，再 `0x95 query` 回读匹配。
- 明确不验证：官网发布、双 EXE、安装/升级/卸载、完整语音模型、本地模型加载、全产品回归、旧固件兼容。

当前是 JAR 联调，不是双 EXE 或官网发布验收。

## 当前 JAR 身份与限制

Windows 联调包：
- 工作目录：`C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java`
- JAR：`C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\target\ahakey-studio-1.0.0.jar`
- JAR SHA256：`C16F5BAD0F518FB8FEA00F7DEE7F97CAAF7AC6DC3865092442A2BEE260217886`
- 依赖目录：`C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\target\lib`
- Main-Class：`com.example.ahakey.App`

发行版身份：
- 该 JAR 的 `model_config.properties` 只有 `status.poll.period.seconds=5`，没有 `model.enabled=true`。
- 代码默认本地模型关闭，因此运行时会跳过本地模型语音输入初始化。
- JAR 内未发现 `models/*`。
- `target/lib` 仍有 `onnxruntime-1.16.3.jar`，所以它不是已经通过轻量打包脚本后处理的最终轻量包。
- 结论：这是“共享 Maven JAR + 当前配置禁用本地模型”的 WD-001 联调包；不能代表轻量 EXE 或带模型 EXE 均已通过。

## 核验过但未启动的命令

在 PowerShell 中：

```powershell
cd "C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java"
$env:JAVA_HOME="D:\jdk-17.0.19.10-hotspot"
$env:Path="$env:JAVA_HOME\bin;$env:Path"
java -version
java -jar ".\target\ahakey-studio-1.0.0.jar"
```

已核对：
- `D:\jdk-17.0.19.10-hotspot\bin\java.exe` 存在。
- `java` 当前可报告 17.0.19。
- 默认 `mvn -v` 仍绑定 Java 8；不要用默认 Maven 输出判断这次 JAR 启动命令。

本轮没有实际启动应用。若启动失败，请返回 PowerShell 输出和 `logs\ahakey-studio.log`。

## Firmware HEX 身份

Firmware 由固件侧生产，Windows 只读引用，不生成 HEX、不烧录设备。

- Firmware 根：`C:\Users\20825\Desktop\vibe-code`
- Firmware Git HEAD：`a9db65e2e73bc56b669c312e9fc42f3ee02c3d49`
- HEX 原始路径：`C:\Users\20825\Desktop\vibe-code\.ahakey-harness\evidence\builds\ws1-cp3a-host-configurable-quiet-sleep-timeout\HID_Keyboard_582m_vibe_coding.hex`
- HEX SHA256：`9AABCE5F015FD44D980FF6818D825B6BAB34F6E4B4F7AC277E942272D700444C`
- 固件门禁来源：`.ahakey-harness\evidence\checkpoints\X1-CONNECTIVITY-POWER\CP3A\candidate-readiness\20260928T164508\candidate-readiness.md`
- 协议决定来源：`.ahakey-harness\evidence\owner-decisions\X1-CONNECTIVITY-POWER-CP3A-HOST-CONFIGURABLE-SLEEP-TIMEOUT-PROTOCOL-20260928.md`

文件核验不等于设备已经刷入。Owner 测试前需要确认物理键盘确实是目标 X1 / CP3A 测试单元，并已刷入上述 HEX；若不是，请报告实际固件身份。

## 实际操作步骤与预期

1. 启动 AhaKey Studio。
   - 预期：应用打开；仅启动不应写设备。

2. 连接 X1 / CP3A 测试键盘。
   - 预期：应用显示已连接。若 BLE 桥/驱动是你的测试环境所需，请按平时方式启动；本测试包不会安装或启动驱动。

3. 打开 More -> “Hawk 安装分发工具” -> 第一个“设备信息”卡片。
   - 预期：原有连接状态、电量、设备名、拨杆等仍在；同一卡片内出现“睡眠等待时间”行；不需要新增卡片或新页面。

4. 记录初始睡眠等待时间。
   - 预期：显示 `永不`、`30 分钟`、`60 分钟` 或 `120 分钟`。若当前值异常，应用应显示异常提示，并允许选择合法值保存。

5. 设置 `30 分钟` 并保存。
   - 预期：只有在固件返回 `0x95 OK` 且后续 `0x95 query` 回读为 30 后，应用才显示保存成功。
   - 预期：Windows 不应要求或追加 `0x04 save_config`。

6. 断电/重启键盘，重新连接，再打开同一位置查询。
   - 预期：仍回读 30。注意：不重启前的即时回读不能替代持久化检查。

7. 重复设置并回读 `永不`、`60 分钟`、`120 分钟`。
   - 预期：每个合法值都能保存并回读为选中值。

8. 快速检查同一弹窗的保留行为。
   - 预期：连接状态、电量/设备名/拨杆、Hook/驱动/日志区域、More 弹窗原有行为仍可用。

9. 断开键盘或在未连接状态查看。
   - 预期：睡眠等待时间控件禁用或提示“请先连接键盘”，不能声称保存成功。

10. 可选：如果你已经有平时使用的协议/固件测试工具，可在 UI 外发送非法 `0x95` 值。
    - 预期：固件返回非 0 错误，原值不变。普通 UI 本来只暴露四个合法值，不做非法值入口。

## 快速验证与实际睡眠验证要分开

- 快速读取/设置验证：步骤 3-5、7、9。
- 持久化验证：步骤 6。
- 实际睡眠/唤醒验证：设置 30/60/120 后等待到达条件，观察睡眠后唤醒、屏幕亮、连接/按键恢复，不能把未执行写成通过。

## 停止、恢复与反馈方式

这项测试会写设备的睡眠等待时间设置。请先记录初始值，测试结束后按需恢复初始值。

如果出现启动、连接、读取、保存、回读不匹配、断连或持久化失败：
- 停止当前失败子项，不要继续把后续项填通过。
- 保持设备供电状态。
- 返回失败截图、PowerShell 输出、`logs\ahakey-studio.log`。

请回传：
- 物理设备是否确认已刷上述 HEX SHA。
- 实际连接路径。
- 每个编号步骤的 `通过 / 失败 / 未执行`。
- More -> 设备信息卡片截图。
- 若失败，返回自然语言现象、截图和日志。
