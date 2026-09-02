# V021-RUNTIME-SIGPIPE-SURVIVAL R1：listener 生命周期、barrier、有界 EAGAIN

日期：2026-09-02 21:34–21:46 +08
ACK Codex `0425fd6` / `lastReviewedCommit=9130cd3`。产品 no-SIGPIPE 方向保留。已安装 0.2.1 build 361 未覆盖。未 overlay `/Applications`、未打包、未 kickstart、未刷机、未 push、未继续 Gate-1。

## R1 行为

- `AhaKeyAgent` 持有 listen fd；`shutdown()` `shutdown+close` 恰一次并 unlink。accept 在 EINTR 以外退出，不再空转。
- `status` / `permission` 在写回前走测试可控 `AhaKeyRuntimeLegacyReplyGate`：handler 已接单 → 客户端关闭或读 → 才放行 `replyAndClose`。
- `writeAll` 对 `EAGAIN/EWOULDBLOCK` 用 `poll` 有界等待，超时 `.failed(ETIMEDOUT)`，不 `sched_yield` 忙等。
- 仓内 probe：`raw` 在 `SIG_DFL` 下裸写；`writer` 为 `SO_NOSIGPIPE` + `writeAll`。`makeUnixStreamPair` 降为 package（测试/探针）。

## 100 轮矩阵

`status`/`permission` 各覆盖立即关闭、延迟关闭、正常读回（20+20+15+15+15+15）。每轮单次 connect，无 retry。结束后再发 `status` 读回仍成功。

## 门禁（原始命令）

```
swift test --filter AhaKeyRuntimeLegacySocketSurvivalTests
# 完整类连续 10 轮，每轮 7/7，零失败（SURVIVAL_10_OK）

swift test --filter CursorHookDecisionReducerTests
# 4/4：allow / defer_to_native / unavailable fail-open / missing never deny

swift test --filter RuntimeXPCServerTests
# 22/22（client 14 + server 8）

swift test --filter 'DeviceTransportCoreTests|AhaKeyBLELifecycleAdapterTests|AhaKeySystemAttachedProbeTests'
# 26/26（Core 19 + Adapter 5 + classifier 2）

swift test
# 744 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
```

仓内红→绿：probe `raw` 为 uncaught SIGPIPE(13)；`writer` exit 0。对端不读 256KB nonblocking 写在 0.2s 内 `.failed(ETIMEDOUT)`。

本卡范围 `git diff --check` 通过。

## 审查范围（相对 `0425fd6`）

- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimeLegacySocketIO.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimeLegacyReplyGate.swift`
- `ahakeyconfig-mac/Sources/AhaKeyRuntimeLegacySocketProbe/main.swift`
- `ahakeyconfig-mac/Tests/AhaKeyAgentTests/AhaKeyRuntimeLegacySocketSurvivalTests.swift`
- 本任务卡、`docs/collab/board.md`、本证据

未改 Hook 决策、XPC/BLE 生产行为、`main.swift` daemon `SIG_IGN`、安装器。

## 工作区既有 dirty（未纳入）

modified：`DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

R1 完成，停手提审。accepted 前不打包、不安装、不继续 Gate-1。
