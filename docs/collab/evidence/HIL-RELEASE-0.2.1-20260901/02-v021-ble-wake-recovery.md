# V021-BLE-WAKE-RECOVERY：扫描期 system-attached probe（产品，非 HIL）

日期：2026-09-02 12:16–12:25 +08
ACK Codex `27ecea2`。产品基线 `1c024c5` / 已安装 0.2.1 (360) 未覆盖。未 overlay `/Applications`、未重冻结 DMG、未 kickstart、未刷机、未 push。未执行 HIL R1（断开→唤醒两轮、`switchState=1`、真实 Cursor 四工具）。

## 行为

`DeviceTransportCore` 在无 `lastUUID` 进入 `.scanning` 时同时 `.scan` 并安排 **1.5s** 单实例 `systemAttachedProbe`。适配层到点回调 `systemAttachedProbeFired`；token 不匹配或非 scanning 为 no-op。空 `retrieveConnectedPeripherals` 回 `systemAttachedProbeEmpty`，只重排下一发 probe，**不 emit / 不写常规日志**。命中走既有 `systemAttachedDeviceFound` → `connectSystemAttached`。离开 scanning、蓝牙不可用、shutdown 时作废 probe。

Agent 判定集中在 `AhaKeySystemAttachedProbe.decide` / `logMessage`：miss 的 logMessage 为 `nil`。

## 门禁

- 定向：`DeviceTransportCoreTests` 17 + `AhaKeySystemAttachedProbeTests` 2，0 失败。
- 全量 `swift test`：**727 tests / 2 skipped / 0 failures**。
- Release：`swift build -c release --product AhaKeyConfig`、`--product ahakeyconfig-agent` 均 complete。
- 本卡产品 + 协作 + 本证据：`git diff --check` 通过。
- 顺手语义不变：Gate-1 已入库 raw 的行尾空格（`pmset`/`ps` 捕获）。未改正文结论，未把 Hook probe 写成真实 IDE 执行。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`。
untracked：`append_entry.py`、协作 proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw 二进制/截图。

## 结论

产品修复完成，停手提审。HIL R1 / `RELEASE-DMG-VERIFIER-CLEANUP` / build 361+ 等 Codex accepted 后再做。
