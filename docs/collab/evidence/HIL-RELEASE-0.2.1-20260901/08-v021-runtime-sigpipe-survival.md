# V021-RUNTIME-SIGPIPE-SURVIVAL：legacy `ahakey.sock` 提前关闭不得杀死 Runtime

日期：2026-09-02 20:27–20:55 +08
ACK Codex `d493088` / 诊断 `93bbefa`。产品基线 `0b4b5e1`（已安装 0.2.1 build 361 未覆盖）。未 overlay `/Applications`、未重冻结 DMG、未 kickstart、未刷机、未 push、未继续 Gate-1 BLE。

## 红

旧路径等价：`/tmp/ahakey-sigpipe-red.c` 对已关闭对端 `socketpair` 做裸 `write()`，进程 **exit 141**（128+SIGPIPE）。这与 Gate-1 上 pid 9292 `exited due to SIGPIPE` 同一机制：`replyAndClose` 异步回包直接 `write()`，daemon 入口未 `SIG_IGN`。

不能在 XCTest 进程内用 `SIG_DFL` 复现（会杀死测试 runner），故用独立子进程探针：`SIG_DFL` → `prepareAcceptedClient` → 关对端 → `writeAll`。新实现必须 exit 0，不得 141。

生产 listener 门禁用 **临时** `ahakey.sock` + `enableRuntimeModules: false`，不 spawn 正式 `ahakeyconfig-agent`，不抢已安装 361 的 BLE/`hook.sock`/XPC。

## 行为

- daemon `main.swift`：socket 建立前 `signal(SIGPIPE, SIG_IGN)`（Hook 子进程原本已有）。
- `accept` 后必须 `prepareAcceptedClient`（`SO_NOSIGPIPE`）；失败则 close 并 continue。
- `replyAndClose`：`writeAll`（partial / EINTR / EAGAIN；EPIPE|ECONNRESET → `.peerClosed`；其它 errno 写 stderr）；`defer closeOnce`，fd 只关一次。
- 测试专用 executable `AhaKeyRuntimeLegacySocketProbe`：**不**列入 SPM `products`，并从 `AhaKeyConfig` `Sources` exclude。不进 App 包。

## 门禁

- 红：裸 `write()` **exit 141**。
- 定向：`swift test --filter AhaKeyRuntimeLegacySocketSurvivalTests` **5/5**。
- 既有 Hook / XPC / BLE lifecycle 定向保持全绿（本轮全量套件已覆盖这些 target）。
- 全量 `swift test`：**742 tests / 2 skipped / 0 failures**。
- Release：`swift build -c release --product AhaKeyConfig`、`--product ahakeyconfig-agent` 均 complete。
- 本卡产品 + 协作 + 本证据：`git diff --check` 通过。

100 轮矩阵：10 `status` 立即关、10 `permission` 立即关、40 `unknown` 立即关、20 延迟关、20 正常读回；提前关闭的 `status` 不阻塞后续 `unknown` 回包。

## 审查范围（相对 `639418e`）

白名单：

- `ahakeyconfig-mac/Sources/Agent/main.swift`
- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimeLegacySocketIO.swift`
- `ahakeyconfig-mac/Tests/AhaKeyAgentTests/AhaKeyRuntimeLegacySocketSurvivalTests.swift`
- `ahakeyconfig-mac/Package.swift`（seam + 测试探针 target 登记）

完成定义要求的子进程探针（SIGPIPE 不能在 XCTest 内 `SIG_DFL`）：

- `ahakeyconfig-mac/Sources/AhaKeyRuntimeLegacySocketProbe/main.swift`

协作：本任务卡、`docs/collab/board.md`、本证据。

## 工作区既有 dirty（未纳入本卡）

modified：`docs/collab/taskcards/DEVICE-PERSIST-AND-UPLOAD-UX.md`、`docs/firmware-client-baseline-2026-08-22.md`。
untracked：`append_entry.py`、协作 proposal、`fix_*.py`、`docs/research/**`、若干 evidence raw 二进制/截图。

## 结论

产品修复完成，停手提审。未安装、未继续 HIL。accepted 后再冻结 build **>361**、Gate-0，然后同一 pid 两轮 BLE（不重测 Hook 三态）。
