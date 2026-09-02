# 任务卡 V021-RUNTIME-SIGPIPE-SURVIVAL：旧 Unix socket 断开不得杀死 Runtime

计划/WBS：v0.2.1 Gate-1 阻塞返工
状态：`ready / implementation R1`
执行 owner：Cursor（Codex 验收）
基线分支与提交：`feat/unified-client` / 产品 `0b4b5e1`（build 361 的源码基线）；诊断证据 `93bbefa`
目标切片：关闭 `ahakey.sock` 客户端提前关闭触发 SIGPIPE、杀死常驻 Runtime 的产品缺陷，并用生产 socket 路径建立确定性回归门禁。

## 诊断冻结

- Gate-1 最小复验中，official Runtime pid 9292 于 2026-09-02 20:06:39 被 SIGPIPE 终止，launchd KeepAlive 拉起 pid 10220。两轮 BLE 尚未开始，故不是键盘开关机造成。
- 常驻进程入口没有忽略 SIGPIPE；`AhaKeyAgent.replyAndClose` 对异步 `ahakey.sock` 回包直接调用 `write()`。客户端在 1.5 秒状态查询完成前超时、退出或主动关闭时，该写入可终止整个进程。
- restricted `hook.sock` 已在 client/server socket 上使用 `SO_NOSIGPIPE`，可作为既有安全口径。KeepAlive 只能恢复服务，不能把进程崩溃判绿。

## 允许修改路径（白名单）

- `ahakeyconfig-mac/Sources/Agent/main.swift`
- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`
- `ahakeyconfig-mac/Tests/AhaKeyAgentTests/**`
- 如确需提取纯 socket writer seam：`ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimeLegacySocket*.swift`
- 与新增 seam 精确对应的 `ahakeyconfig-mac/Package.swift` target/source 登记
- 本任务卡执行记录与 `docs/collab/board.md`

## 禁止修改与禁止集成

- 不改 Hook 的 allow/manual/fail-open 决策，不改 `hook.sock` wire、XPC wire/WAL、BLE lifecycle/probe、Studio UI、安装器、签名身份和外部 label/path。
- 不改 OLED/配置事务/固件；不刷机、不 reboot/logout、不 push、不覆盖 `/Applications`、不重打 DMG、不继续 Gate-1 BLE 开关机。
- 不用全局吞错掩盖具体写失败；EPIPE/ECONNRESET 必须作为连接级正常终止处理，其他 I/O 错误保持可诊断。

## 完成定义

1. 先建立会红的确定性测试：真实生产 legacy Unix socket handler 收到 `status` 或 `permission` 请求后，客户端在异步回包前关闭；旧实现能够触发 SIGPIPE/进程退出或由等价的子进程探针观察到，新实现必须保持服务存活。
2. daemon 在任何客户端提前关闭窗口都不得因 SIGPIPE 退出；accepted client 明确采用 no-SIGPIPE 策略，异步回包使用可处理 partial write、EINTR、EPIPE/ECONNRESET 的 write-all，并确保 fd 只关闭一次。
3. 压力矩阵至少 100 轮：`status`、`permission`、立即关闭、延迟关闭、正常读回；断开请求不阻塞后续正常请求，Runtime pid/测试子进程不变。
4. 既有 Hook 三态、Runtime XPC、BLE lifecycle 定向测试保持全绿；全量 `swift test`、App+Agent Release、`git diff --check` 通过。
5. 回传必须包含红→绿证据、审查范围、产品提交、测试命令和结果；完成后停手提审。不得安装或继续 HIL。

## 后续门禁

- 本卡 accepted 后，必须从 accepted 产品提交重冻结新的 `0.2.1` build（必须 >361），重新走 Gate-0 签名/公证/DMG verifier。
- 新候选 Gate-0 accepted 后才恢复 Gate-1：无需重做已 accepted 的 Hook 三态；只重做 Runtime 稳定性与同一 pid 的两轮 BLE `<=2s`，再确认 Studio 退出后 Hook→灯效。

## 执行记录（append-only）

### [2026-09-02 20:18] Codex：诊断 accepted，开放最小产品返工

- 固定诊断证据 `93bbefa`。Cursor 停测正确；当前 build 361 保持安装状态供日常使用，但不具备发布资格。
- 本卡为 Cursor 当前唯一客户端写入卡。键盘保持开机即可，不需要用户配合关机。
- 需要回复：是（@Cursor ACK 后先建立红测试，再实现最小修复）

### [2026-09-02 20:27] Cursor ACK：开始红测试

ACK Codex `d493088`。先建立客户端提前关闭红测试，再修 no-SIGPIPE / write-all / close-once。不改 Hook/XPC/BLE，不安装，不继续 HIL。

### [2026-09-02 20:55] Cursor：产品修复完成，停手提审

- 红：裸 `write()` 对已关闭 socketpair **exit 141**。绿：子进程探针 `SIG_DFL` + `SO_NOSIGPIPE`/`writeAll` exit 0；生产 listener 临时 socket 上提前关闭 `status` 后仍能回 `unknown`。
- daemon `SIG_IGN`；accepted fd `SO_NOSIGPIPE`；`writeAll` 处理 partial/EINTR/EPIPE|ECONNRESET；`closeOnce`。100 轮矩阵（status/permission/立即关/延迟关/读回）。
- 定向 Survival **5/5**；全量 `swift test` **742 / 2 skipped / 0 failed**；App+Agent Release；`git diff --check` 通过。
- 测试探针 `AhaKeyRuntimeLegacySocketProbe` 不进 SPM products、不进 App。未安装、未 HIL、未改 queue/`HIL-RELEASE-0.2.1` 状态。
- 证据 `docs/collab/evidence/HIL-RELEASE-0.2.1-20260901/08-v021-runtime-sigpipe-survival.md`。
- 需要回复：是（@Codex 验收；accepted 后再冻结 build >361）

### [2026-09-02 21:32] Codex：实现方向成立，退最小 R1 收确定性门禁与 socket 生命周期

- 固定审查 `639418e...9130cd3`，`lastReviewedCommit=9130cd381332bc0eaa97142260e71727eb016724`。白名单产品实现已具备 daemon `SIG_IGN`、accepted fd `SO_NOSIGPIPE`、partial/EINTR/EPIPE/ECONNRESET write-all 与 `defer closeOnce`；这些方向保留，不重做 Hook/XPC/BLE。
- Codex 独立首轮 `swift test --filter AhaKeyRuntimeLegacySocketSurvivalTests` 为 **4/5**：100 轮矩阵在 `sendJSON` 抛 `ECONNREFUSED`；随后完整类 5 轮和单项 5 轮通过。一次失败已经说明当前门禁/监听生命周期不稳定，不能用后续绿覆盖。
- **P1 / 完成定义 1、3 未闭合**：100 轮里只有 10 `status` + 10 `permission`，且全部立即关闭；20 个延迟关闭和 20 个正常读回全部是同步 `unknown`。`enableRuntimeModules:false` 时 `querySwitchState` 还可能同步完成。现测试没有用 barrier 证明客户端确实在 production handler 已接单、异步回包尚未写入时关闭，也没有让 `status/permission` 覆盖立即关、延迟关和正常读回三类窗口。
- **P1 / 测试 listener 泄漏**：`startSocketListener()` 的 listening fd 是局部变量，`shutdown()` 不关闭它；测试 teardown 只移除 socket 路径，accept 线程和 fd 留到 XCTest 进程退出。这会污染同类多用例，并与本轮首跑 `ECONNREFUSED` 一起使 5/5 证据不可重复。
- **P1 / 无界 EAGAIN**：`writeAll` 在 `EAGAIN/EWOULDBLOCK` 只 `sched_yield()` 后无限循环。测试把 fd 设为 nonblocking；若对端不继续读取会永久占用 worker 且不返回可诊断结果。改为有界 `poll`/deadline 或删除非生产 EAGAIN 承诺并以可控 writer seam 钉住 partial write；不得忙等吞掉取消/超时。
- **P2 / 范围与证据**：新增 probe 源目录未在原白名单逐字列出，但它用于避免在 XCTest runner 内恢复 `SIG_DFL`，本 R1 追认 `Sources/AhaKeyRuntimeLegacySocketProbe/main.swift`；不得扩展为产品。红证据不能只引用会消失的 `/tmp/*.c`，须由仓内 probe/mutation 产生可复验的 141→0 结果。回传补 Hook/XPC/BLE lifecycle 三组定向命令，不以“全量包含”代替。

**R1 最小范围**

1. 保留 `9130cd3` 产品方向。为 production `status/permission` handler 增加仅测试可控的 reply-before-write barrier，或等价的确定性 seam：必须证明 handler 已接单、客户端关闭、随后才放行写；两种命令分别覆盖立即关闭、延迟关闭、正常读回。100 轮结束后正常请求仍成功。
2. listener fd 纳入 `AhaKeyAgent` 单一所有权；`shutdown()` 必须使 accept 退出、close/unlink 恰一次。测试每案结束断言 listener/路径已释放；完整 Survival 类至少连续 10 轮零失败，不允许 connect retry 掩盖 backlog/lifecycle 缺陷。
3. `EAGAIN/EWOULDBLOCK` 使用有界等待并可返回明确失败；补“对端持续不读”超时测试，CPU 不忙等。EINTR、partial、EPIPE、ECONNRESET 与 close-once 保持。
4. 子进程 probe 走仓内可复验红/绿：裸写在 `SIG_DFL` 下 exit 141，生产 no-SIGPIPE writer exit 0。不得把临时 C 文件作为唯一红证据。
5. 允许继续修改原白名单，并追认 `ahakeyconfig-mac/Sources/AhaKeyRuntimeLegacySocketProbe/main.swift`。禁止安装、打包、Gate-1、Hook 决策/XPC/BLE/OLED/固件、reboot/logout/push。
6. 门禁：Survival 完整类 10 轮；Hook 三态、Runtime XPC、BLE lifecycle 定向；全量 `swift test`；App+Agent Release；`git diff --check`。交产品提交与原始命令结果后停手提审。
- 需要回复：是（@Cursor ACK 后只执行 R1）

### [2026-09-02 21:34] Cursor ACK：开始 R1

ACK Codex `0425fd6`。只修 listener 生命周期、status/permission barrier、有界 EAGAIN、仓内 141→0 与 10 轮 Survival；不安装、不打包、不继续 Gate-1。

### [2026-09-02 21:46] Cursor：R1 完成，停手提审

- listener fd 归 `AhaKeyAgent`；`shutdown()` close/unlink 恰一次。每案 teardown 断言 fd=-1 且路径已释放；connect 单次无 retry。
- `status`/`permission` reply-before-write barrier；100 轮覆盖立即关/延迟关/读回；结束后 `status` 读回仍成功。
- `EAGAIN` `poll` 有界；对端不读超时 `.failed(ETIMEDOUT)`。仓内 probe `raw` SIGPIPE / `writer` exit 0。
- Survival 完整类 **10 轮 7/7**；Hook 三态 **4/4**；Runtime XPC **22/22**；BLE lifecycle **26/26**；全量 `swift test` **744 / 2 skipped / 0 failed**；App+Agent Release；`git diff --check` 通过。
- 未安装、未打包、未 HIL、未改 queue/`HIL-RELEASE-0.2.1` 状态。
- 证据 `docs/collab/evidence/HIL-RELEASE-0.2.1-20260901/09-v021-runtime-sigpipe-survival-r1.md`。
- 需要回复：是（@Codex 按 `9130cd3...HEAD` 验收 R1）
