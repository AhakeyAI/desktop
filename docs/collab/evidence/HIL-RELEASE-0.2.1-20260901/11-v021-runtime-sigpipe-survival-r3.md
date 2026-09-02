# V021-RUNTIME-SIGPIPE-SURVIVAL R3：分片读行、idle client shutdown、setup fail-closed

日期：2026-09-02 22:31–22:44 +08
ACK Codex `8f46d1a` / `lastReviewedCommit=84a17f4`。R2 生产 `SO_NOSIGPIPE + O_NONBLOCK`、monotonic write/poll/EINTR、generation、close-before-write 与加锁测试箱保留。已安装 0.2.1 build 361 未覆盖。未 overlay `/Applications`、未打包、未 kickstart、未刷机、未 push、未继续 Gate-1。未改 `queue.md` / `HIL-RELEASE-0.2.1` 状态。

## R3 行为

- `readLine`：monotonic deadline，循环 read / EINTR / EAGAIN+poll，最多 1024B，只在 newline 后交给 JSON parser。EOF-before-line、overflow、timeout fail-closed。poll 单次切片 ≤50ms，关闭 fd 后 handler 能在 shutdown 时限内退出。
- listener owner 持有 generation、listen fd、active client fds 与统一 `DispatchGroup`。accept 与 `handleClient` 分离；stop 失效代际、shutdown+close listener 与该代 clients、等待 accept+handler。超时不清空仍需回收的 session，也不允许 restart。
- `chmod` / `listen` 检查返回值；失败 close+unlink，不发布 owner、不打「监听」日志。

## 新增门禁

- IO 层分片拼行；overflow / EOF-before-line fail-closed。
- 生产 handler 将 `status` / `permission` 各拆成两次 write，回包后后续 `status` 仍可用。
- idle connect（零字节）→ shutdown <1s → worker/handler 退出 → fd/path 释放，10 轮后 restart 正常。
- `listen` 失败：fd=-1、路径不存在、unlink 计数不变；去掉 hook 后可正常 start/stop。

## 门禁（原始命令）

```
swift test --filter AhaKeyRuntimeLegacySocketSurvivalTests
# 完整类连续 10 轮，每轮 13/13，零失败（SURVIVAL_10_OK）

swift test --filter CursorHookDecisionReducerTests
# 4/4：allow / defer_to_native / unavailable fail-open / missing never deny

swift test --filter RuntimeXPCServerTests
# 22/22（client 14 + server 8）

swift test --filter 'DeviceTransportCoreTests|AhaKeyBLELifecycleAdapterTests|AhaKeySystemAttachedProbeTests'
# 26/26（Core 19 + Adapter 5 + classifier 2）

swift test
# 750 tests / 2 skipped / 0 failures

swift build -c release --product AhaKeyConfig
swift build -c release --product ahakeyconfig-agent
# RELEASE_OK
```

本卡范围 `git diff --check` 通过。

## 审查范围（相对 `8f46d1a` / 产品基线 `84a17f4`）

- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimeLegacySocketIO.swift`
- `ahakeyconfig-mac/Tests/AhaKeyAgentTests/AhaKeyRuntimeLegacySocketSurvivalTests.swift`
- 本任务卡、`docs/collab/board.md`、本证据

未改 Hook 决策、XPC/BLE 生产行为、`main.swift` daemon `SIG_IGN`、探针、`Package.swift`、安装器。

## 工作区既有 dirty（未纳入）

modified：`DEVICE-PERSIST-AND-UPLOAD-UX.md`、`HIL-RELEASE-0.3.md`、`queue.md`、`docs/firmware-client-baseline-2026-08-22.md`、`docs/unified-firmware-runtime-implementation-plan.md`。
untracked：`append_entry.py`、proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw、其他任务卡草稿。

## 结论

R3 完成，停手提审。accepted 前不打包、不安装、不继续 Gate-1。accepted 后再冻结 build >361。
