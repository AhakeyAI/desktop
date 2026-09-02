# V021-RUNTIME-SIGPIPE-SURVIVAL R2：生产非阻塞有界写与 listener 代际

日期：2026-09-02 22:01–22:16 +08
ACK Codex `3b25edd` / `lastReviewedCommit=10a53ac`。R1 no-SIGPIPE / barrier / 仓内 141→0 方向保留。已安装 0.2.1 build 361 未覆盖。未 overlay `/Applications`、未打包、未 kickstart、未刷机、未 push、未继续 Gate-1。未改 `queue.md` / `HIL-RELEASE-0.2.1` 状态。

## R2 行为

- `prepareAcceptedClient` 在 `SO_NOSIGPIPE` 之外设置 `O_NONBLOCK`。0.2s 对端不读测试不再手工改 fd；EAGAIN/`poll`/deadline 走生产 writer。
- `writeAll` 用 `DispatchTime` monotonic deadline 覆盖 write / poll / EINTR。`POLLNVAL` → `EBADF`；`POLLERR` 经 `SO_ERROR`（EPIPE/ECONNRESET → `.peerClosed`）；仅 `POLLHUP` 无请求事件 → `.peerClosed`；超时 `.failed(ETIMEDOUT)`。
- 生产 `handleClient` 在非阻塞 `read` 前 `waitForReadable`（最多 5s），避免客户端尚未写入时关 fd、测试进程被 SIGPIPE 打死。
- listener 用 generation + worker completion，不再只比裸 fd。`startSocketListener` 先等旧 worker 退出再开新 fd。`stopLegacySocketListener` 原子失效代际、shutdown+close 自有 fd、有界等待 worker、仅 owner unlink。bind 前对残留路径的 unlink 不计 owner 次数。
- close-before-write 等 `waitUntilWriteFinished`；测试 `LockedClientIO` 用 `NSLock`，去掉无锁 `SendBox`。

## 新增门禁

- 20 次 start → status 读回 → stop：代际每次变化、owner unlink 恰 20、worker 已退出。
- 连续两次 `shutdown()`：unlink 计数保持 1。

## 门禁（原始命令）

```
swift test --filter AhaKeyRuntimeLegacySocketSurvivalTests
# 完整类连续 10 轮，每轮 8/8，零失败（SURVIVAL_10_OK）

swift test --filter CursorHookDecisionReducerTests
# 4/4：allow / defer_to_native / unavailable fail-open / missing never deny

swift test --filter RuntimeXPCServerTests
# 22/22（client 14 + server 8）

swift test --filter 'DeviceTransportCoreTests|AhaKeyBLELifecycleAdapterTests|AhaKeySystemAttachedProbeTests'
# 26/26（Core 19 + Adapter 5 + classifier 2）

swift test
# 745 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK
```

对端不读 256KB 写依赖生产 `prepareAcceptedClient` 的 `O_NONBLOCK`，0.2s 内 `.failed(ETIMEDOUT)`。本卡范围 `git diff --check` 通过。

## 审查范围（相对 `3b25edd` / 产品基线 `10a53ac`）

- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimeLegacySocketIO.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimeLegacyReplyGate.swift`
- `ahakeyconfig-mac/Tests/AhaKeyAgentTests/AhaKeyRuntimeLegacySocketSurvivalTests.swift`
- 本任务卡、`docs/collab/board.md`、本证据

未改 Hook 决策、XPC/BLE 生产行为、`main.swift` daemon `SIG_IGN`、探针、`Package.swift`、安装器。

## 工作区既有 dirty（未纳入）

modified：`DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw。

## 结论

R2 完成，停手提审。accepted 前不打包、不安装、不继续 Gate-1。accepted 后再冻结 build >361。
