# Flash Readiness Redesign Review

## 结论

当前 `WCHISPTool -c <ini> -u get` 的 stdout 不能作为可靠 UID 来源。UID 只提供设备信息，不参与 HEX 选择、flash 命令、flash 结果解析或 post verify，因此本轮将其从烧录硬门禁拆出。

新的准备条件为：

```text
RuntimeValid && ISP_PRESENT && CHIP_MATCHED
```

现阶段 Windows PnP 入口只得到 `VID_4348&PID_55E0`，不能证明真实 CH582 型号。新增 `ChipMatched` 接口，默认返回 `CHIP_MATCH_STATUS=UNKNOWN` 并 fail closed。开发期可显式设置 `ahakey.dev.allow-isp-flash-with-unknown-chip=true`，以便进行一次真实硬件闭环；jpackage/release 运行不会接受该开关。该开发开关是临时测试例外，不会把 UNKNOWN 伪装成 MATCHED。

## 状态机变化

```text
IDLE
  -> PREFLIGHT (HEX、版本策略、runtime)
  -> WAITING_ISP (等待 VID_4348&PID_55E0)
  -> DETECTING (ChipMatched 结果)
  -> READY (MATCHED，或开发期 UNKNOWN override)
  -> FLASHING (原有 -o download -f <hex>)
  -> WAITING_RECONNECT
  -> VERIFYING (原有 FirmwarePostVerifier)
  -> SUCCESS
```

UID 查询仍可在 `DETECTING` 中运行并保存 stdout/stderr/console 证据。UID 成功时显示增强信息；UID 空输出、exit 非 0、超时或 parser 失败时写入 `uid-warning.txt`，不会改变 `READY`/`FLASHING`。如果芯片状态为 `MISMATCH`，立即以 `CHIP_MISMATCH` fail closed；如果为 `UNKNOWN` 且未开启开发开关，以 `CHIP_UNKNOWN` fail closed。

## 修改范围

- `FirmwareUpdateService`：新增 ChipMatched 依赖；在 UID 查询前执行芯片 gate；UID 失败改为 warning；保留原 flash command、workspace、HEX、DataFlash、flash parser、reconnect 和 post verify。
- `DeviceMaintenancePane`：`DiagnosticResult.ready()` 由 runtime+ISP+chip gate 决定；UID 独立显示，并追加 `CHIP_MATCH_STATUS`/`CHIP_GATE_ALLOWED`。
- `ChipMatched`：可替换的结构化芯片身份接口和 MATCHED/MISMATCH/UNKNOWN 结果。
- `FirmwareUpdateError`：增加 `CHIP_MISMATCH`、`CHIP_UNKNOWN`。
- 发布 allowlist/artifact test：纳入 `ChipMatched.class`。

未修改 Firmware、BLE、GATT、`WchIspRunner`、flash command、HEX 处理、DataFlash 策略、`FirmwarePostVerifier`。

## 测试覆盖

- UID 空输出仍可走到 `READY` 并完成 flash；flash 参数保持 `-c flash-config.ini -o download -f <hex>` 结构。
- UID 查询失败仍可执行 flash，最终 detail 保留 `UID_QUERY_WARNING`。
- runtime resolve 失败在 ISP/WCHISP 之前阻止 operation。
- `ChipMatched.MISMATCH` 在 UID/flash 之前阻止 operation。
- `ChipMatched.UNKNOWN` 未启用开发开关时 fail closed。
- 既有诊断过程证据仍保存，UID 只影响 `uidConfirmed` 展示，不影响已匹配芯片的 `ready()`。

## 真实硬件准备

见 `hardware-flash-test-checklist.md`。真实测试必须显式选择当前 rewrite JAR 和 runtime，并启用开发期 UNKNOWN override；日志中的 `CHIP_MATCH_STATUS=UNKNOWN` 必须如实保留。该开关不能用于正式发布包，也不能替代后续实现可靠的 CH582 官方控制模式/native 芯片检测。
