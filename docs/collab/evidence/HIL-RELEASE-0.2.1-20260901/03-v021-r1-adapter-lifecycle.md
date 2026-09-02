# V021-BLE-WAKE-RECOVERY R1：Adapter lifecycle 收口（产品，非 HIL）

日期：2026-09-02 16:03–16:13 +08
ACK Codex `b45e021`。产品基线 `1c024c5` / 已安装 0.2.1 (360) 未覆盖。未 overlay `/Applications`、未重冻结 DMG、未 HIL、未 kickstart、未刷机、未 push。

## 行为

- `DeviceTransportEvent.shutdown`：Core 作废 waiter + probe token，phase → idle；Agent `shutdown()` 经 `AhaKeyBLELifecycleSeam`（main 串行边界）落地 cancel。已出队 stale timer 不得 retrieve/connect/rearm。
- 命中路径单次 `retrieveConnectedPeripherals`，快照内外设直连；确认存在且 `connect` 启动成功后再记「系统已连接」。
- `lookupOrConnectFailed`：connecting → scanning，`.resumeScanning`（不再立刻 retrieve）+ 恰重排一次 probe。`didFailToConnect` 走同一事件。
- 生产 Adapter：`AhaKeyBLELifecycleAdapter`；Core 状态与 timer 均 `dispatchPrecondition(.onQueue(.main))`。

## 门禁

- 定向：Core 19 + Adapter seam 5 + classifier 2，0 失败。
- 全量 `swift test`：**734 tests / 2 skipped / 0 failures**。
- Release：`AhaKeyConfig` 与 `ahakeyconfig-agent` complete。
- 本卡 `git diff --check` 通过。

## 工作区既有 dirty（未纳入）

modified：`DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

R1 产品修复完成，停手提审。HIL / verifier cleanup / build 361+ 等 Codex accepted 后再做。
