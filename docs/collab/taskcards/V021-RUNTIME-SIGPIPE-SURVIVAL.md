# 任务卡 V021-RUNTIME-SIGPIPE-SURVIVAL：旧 Unix socket 断开不得杀死 Runtime

计划/WBS：v0.2.1 Gate-1 阻塞返工
状态：`ready / implementation`
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
