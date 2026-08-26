# 任务卡 WBS-5.5-HIL-REWORK：HIL-RUNTIME-2 暴露的设备层返工

计划/WBS：5.5（HIL 缺陷，不开 5.6）  
状态：`accepted`  
执行 owner：Kimi  
基线：`feat/unified-client` @ `ea770d6`  
目标：实机可测 BLE 基础功能，且不把 protocol v0 标成 current、不刷机。

## 允许修改路径

- `ahakeyconfig-mac/Sources/Shared/DeviceTransportCore.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyFirmwareCapabilities.swift`（仅注释/模式语义，不把 v0 映射为 `.current`）
- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/DeviceTransportCoreTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyFirmwareCapabilitiesTests.swift`（若改 mode 函数）
- 本卡执行记录与 `board.md` 末尾

工作区已有未提交 `AhaKeyAgent.swift`（`.scan` 前 `retrieveConnectedPeripherals`）。并入本卡后提交，禁止留脏树。

## 禁止事项

- 不刷机、不开工 WBS-1、不 merge。
- 不把 `protocolVersion == 0` 映射为 `.current`。
- 不启用 USB 配置写入 / 任务图（仍仅 `.current` / 既有 `allows*`）。
- 不改 `Sources/Views/**`、不做 5.6 planner。
- 不在 `HIL-RUNTIME-2` 卡上改产品代码。

## 完成定义

1. **系统已连回连**：`DeviceTransportAction.scan` 落地前查询 `retrieveConnectedPeripherals`；HID 占用、无广播时仍能 attach。有定向测试或 HIL 日志。
2. **v0 受限 ready**：合法 0x99 且 `protocolVersion != 3` → `.restrictedUnknown`；有稳定 device ID 则可 `isReady`，允许 Agent `0x00`/`0x90`。USB/`allowsUSBConfigurationTransport` 仍 false。
3. **三次无 0x99**：保持现有 legacy / restrictedUnknown 回退，不放宽 USB。
4. 定向测试 + `swift build -c release --product ahakeyconfig-agent` + `git diff --check`。

## 前置与晋级

HIL-RUNTIME-2 发现；用户已暂缓固件。等 Kimi ACK（基线 `ea770d6`）后 Codex 翻 `active`。完成后回到 HIL-RUNTIME-2，不自动 5.6。

## 执行记录（append-only）

### [2026-08-25 22:19] Codex 晋级 ready

- 裁决：不刷机。v0 不得当 current。BLE 基础命令受限放行。系统已连路径纳入本卡（勿只留未提交 diff）。

### [2026-08-25 22:44] Codex 独立验收 `0bab8af`：accepted（完成定义第 2 条被根因替代）

- 白名单 3 文件。定向 `DeviceTransportCoreTests` 14/14。`AhaKeyResponseParser.parseCommandResponse` 独立证实帧为 AA BB cmd status payload；Agent 原 `dropFirst(3)` 会把 status `00` 读成 protocol v0。
- **不把 v0 映射为 current。** current-only 保留。第 2 条「restrictedUnknown 也 isReady」因根因是解析错误而关闭，不再要求放宽门。
- 系统已连回连、2A25 身份链、pendingNegotiatedMode 仅 `.current` 落入 ready：通过。
- 不 merge。不刷机。不进 5.6。HIL-RUNTIME-2 恢复采集。
