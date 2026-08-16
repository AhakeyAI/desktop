# Part 3：桌面端待机时间设置

## 用户入口

Windows JavaFX 客户端：

```text
更多 → 设备信息 · 设置 · Hooks安装 → 自动待机时间
```

可选档位：

- 5 分钟
- 10 分钟
- 15 分钟
- 30 分钟

USB HID 和 BLE 共用同一套 Protocol v2 命令。设备同时可用时，客户端现有传输策略优先使用 USB。

## 打开页面

1. 确认设备已连接。
2. 发送 `0x9F QUERY_CAPABILITIES`。
3. 要求协议主版本不低于 2，且 `CAP_STANDBY_TIMEOUT_V2` 能力位为 1。
4. 发送 `0x95 STANDBY_TIMEOUT` 空载荷查询当前值。
5. 显示当前设备值和实际传输方式。

旧固件、无能力位或无法解析的响应不会回退到冲突命令 `0x86`，设置控件保持禁用。

## 保存事务

用户选择档位并点击“保存到设备”后，客户端持有设备命令锁，按顺序执行：

```text
0x95 设置
  → 等待成功 ACK
0x04 SAVE_CONFIG
  → 等待成功 ACK
0x95 回读
  → 必须与用户选择一致
```

事务运行期间下拉框和按钮禁用，状态轮询不会插入事务中间。失败时客户端会尽力重新读取设备实际值；无法读取时将当前值显示为未知，不会假装保存成功。

## 验收清单

### USB

1. 烧录支持 Protocol v2 的固件。
2. 仅连接 USB 数据线，不连接 BLE 桥。
3. 在桌面端连接设备。
4. 打开设备设置，确认显示“已通过 USB 连接”。
5. 分别设置 5、10、15、30 分钟。
6. 每次设置后关闭并重新打开窗口，确认回读一致。
7. 设备断电重启后再次回读，确认 Flash 持久化成功。

### BLE

重复上述流程，并确认状态显示“已通过 BLE 连接”。

### 异常场景

- 旧固件：显示不支持，控件禁用。
- 保存时拔线：显示失败，不显示虚假的成功值。
- 连续点击：保存期间按钮禁用，只产生一个事务。
- 当前固件值不是四个 UI 档位之一：显示实际值，但不预选任何档位。

## 尚需真机验证

本功能依赖固件 USB HID 命令收发以及重新编译烧录后的 `0x95/0x9F` 实现。只有完成 Java 客户端构建、固件构建和上述 USB/BLE 真机验收后，Part 3 才能进入发布分支。

## 发布基线增量预览

安装版语音使用 `SpeechService` 和以下模型：

- `encoder.int8.onnx`
- `decoder.int8.onnx`
- `silero_vad.onnx`
- `tokens.txt`

不能使用仓库的整套 `target/classes` 或 `target/manual-classes` 覆盖安装版，否则会加载依赖 `models/model_q8.onnx` 的另一套语音实现。

使用发布基线增量预览脚本：

```powershell
cd ahakeyconfig-win-java
.\preview-part3-release-overlay.ps1
```

脚本以已安装的 `ahakey-studio-1.0.0.jar` 为基线，只编译并覆盖：

- `AhaKeyProtocol`
- `AhaKeyResponseParser`
- `BleManager`
- `StandbySettingsPane`
- 发布基线版本的 `TopBar`

脚本会逐项计算 JAR entry 的 SHA-256。`VoiceInputManager`、`SpeechService`、`ModelConfig` 和 `model_config.properties` 必须与安装版逐字节一致，否则构建立即失败。

关闭正在运行的 AhaKey Studio 后，可启动预览：

```powershell
.\preview-part3-release-overlay.ps1 -Launch
```

预览进程以安装版 `app` 目录为工作目录，因此继续使用安装版模型、依赖库和日志目录。
