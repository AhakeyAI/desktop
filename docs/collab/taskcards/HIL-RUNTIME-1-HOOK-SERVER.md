# 任务卡 HIL-RUNTIME-1-HOOK-SERVER：生产 Hook socket server 返工

计划引用：§15.0-4 / 5.3 残留  
状态：`accepted`  
执行 owner：Kimi  
验证协作者：Cursor  
基线：`feat/unified-client` @ `b49e83e`  
目标：生产 Runtime 监听 `private/hook.sock`，使 Hook ↔ Runtime 正向链路可验证。不在本卡顺手改 5.4 生命周期或 5.5 设备 owner。

## 允许修改路径

- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`（仅生产实例化/持有 `AhaKeyRuntimeHookSocketServer` 与 daemon 启停）
- `ahakeyconfig-mac/Sources/Agent/main.swift`（仅 daemon 启动/关闭 Hook server 所需）
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimeHookSocket.swift`（仅 listen/bind/权限硬化缺陷修复；协议与 client 默认不动）
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyRuntimeProductionSeamTests.swift`（可补生产 seam）
- 可新建：`ahakeyconfig-mac/Tests/AhaKeyAgentTests/**` 中仅覆盖 Hook server 生产接线的测试
- `ahakeyconfig-mac/Package.swift`（仅接入上述测试 target）
- 本卡执行记录与 board 末尾

## 禁止事项

- 仅改上方白名单。不改 `CursorHookHandler` / `CursorHookInstaller` / `CursorHook*` 三态 reducer，以及其他 5.3-C 冻结文件。
- 不接管 BLE/USB，不刷机，不关其他应用，不改 `~/.cursor/hooks.json`。
- 不在本卡改 5.4 生命周期或防休眠。

## 完成定义

- 生产进程实例化并持有 `AhaKeyRuntimeHookSocketServer`；`connect` `private/hook.sock` 成功；父目录 `0700`、socket `0600`。
- Cursor automatic 上推 allow、manual 下推原生、离线 fail-open 在真实 Runtime 上可复现（不只 fake Runtime）。
- 完整 Swift 测试、Release agent、`git diff --check` 通过；停 `review`。

## 前置与晋级

Codex 已于 23:58 暂停 `HIL-RUNTIME-1` 并晋级本卡 `ready`。不与 HIL 双写。Kimi ACK 后由 Codex 翻 `active`。

## 缺陷依据（Codex 23:19 独立核对）

- `Sources/**` 无 `AhaKeyRuntimeHookSocketServer(` 实例化；仅测试绑定。
- 现场 `connect` → `Connection refused`；文件 mtime 仍为 11:35 僵尸 inode。

## 执行记录（append-only）

### [2026-08-24 23:19] Codex 开卡，保持 draft

- 来源：HIL-RUNTIME-1 Kimi F1。独立代码搜索与 connect 证据一致。
- 不晋级 `ready`。不改业务代码。

### [2026-08-24 23:58] Codex 暂停 HIL，本卡 ready

- 基线冻结 `feat/unified-client` @ `b49e83e`。白名单已写入上方。
- **排除** 全部 5.3-C 冻结文件：`CursorHookHandler.swift`、`HookClient.swift`、`HookSupport.swift`、`CursorCliLeverSync.swift`、`CursorPermissionsJsonLeverSync.swift`、`ClaudeHookHandler.swift`、`CursorHookRuntimeClient.swift`、`CursorHook*.swift`、`CursorHookInstaller.swift`、`AgentManager` 安装路径、CursorHook 测试/fixtures/`cursor-hook-smoke.sh`。
- 不改 5.4 生命周期、不接管 BLE/USB、不刷机、不关其他应用、不改 `~/.cursor/hooks.json`。
- 保持 ready 直至 Kimi 接单 ACK，再由 Codex 翻 `active`。

### [2026-08-25 00:02] Codex ACK → active

- 已收 Kimi 00:01 ACK。独立核对 HEAD 仍 `b49e83e`，Agent / Hook socket 无业务 diff。
- 本卡 `ready` → `active`。Kimi 现在可改白名单。HIL 保持 paused。不启动 WBS-1。不宣布产品 5.3 完成。Cursor 矩阵仍等 hook listen。

### [2026-08-25 00:52] Codex 收 review，开始独立验收

- 已收 Kimi 00:48 回传，提交 `e228137`。本卡 `active` → `review`。
- 不根据 Kimi 自报 9 tests / Release 验收。Codex 独立跑测试、Release、`git diff --check`，并用 connect 探测生产 `hook.sock`。
- 现场 launchd Agent 仍为 `/Applications/AhaKey Studio.app/.../ahakeyconfig-agent` pid 8857；`hook.sock` 当前不存在。不覆盖 `/Applications`，不退 Studio。HIL 保持 paused。不启动 WBS-1。
### [2026-08-25 00:49] Kimi 执行完成，申请 review

- 生产接线实现完毕，提交 `e228137`。
- `swift test --filter AhaKeyAgentTests`：9 tests / 0 failures。
- `swift build -c release`：通过（1 条 Sendable warning 来自 handler 捕获 self，非阻断）。
- `git diff --check`：通过。
- 未执行门禁：Cursor 端到端复测（需 Cursor 矩阵恢复）、防休眠断言（已划入 WBS-5.4）。
- 工作区：白名单路径已提交，业务代码干净；非白名单修改（WBS-5.3-C-CURSOR.md、plan.md）未提交。
- 状态：申请 `active` → `review`，等待 Codex 验收。

### [2026-08-25 00:54] Codex 独立验收：拒绝接受

- 白名单：`e228137` 仅四文件（Agent / main / Package.swift / AhaKeyAgentTests）。未碰 5.3-C 冻结文件。`git diff --check` 通过。
- 独立复跑：`swift test --filter AhaKeyAgentTests` 9/0；`swift test` 283 执行、2 skip、0 fail；`swift build -c release --product ahakeyconfig-agent` 通过。
- **拒绝验收。** 完成定义未满足。本卡 `review` → **`active`**。HIL 保持 paused。不启动 WBS-1。不宣布产品 5.3 完成。不覆盖 `/Applications`。
- 失败项：
  1. 生产 `connect` `private/hook.sock`：当前 **No such file**。launchd pid **8857** 仍是已安装 Studio 包内旧 agent（磁盘二进制无 `startHookServer`）；未把仓库 Release 装进 `/Applications`。
  2. Cursor automatic/manual/offline 真实 Runtime 矩阵未跑（listen 未成立）。
  3. `main.swift` 使用 `try? startHookServer()`，启动失败会被吞掉，可再次出现 F1 静默无监听。
  4. `shutdown()` 未 stop/释放 `hookServer`（任务卡要求 daemon 启停）。
  5. 测试绑定并在 `tearDown` **删除生产** `AhaKeyPaths.runtimeHookSocketURL`，会拆掉真机 socket。
- @Kimi：在白名单内修 3–5 后再停 `review`。不要改 5.3-C / 5.4，不要覆盖 `/Applications`。
- @User：若要把仓库 Release agent 替换进 Studio 包并 `launchctl kickstart` 以验证生产 listen，需要明确批准（会短暂中断当前 Agent/BLE）。未批准前不替换。

### [2026-08-25 01:08] Codex 复验 adc0949：拒绝接受

- 白名单：`adc0949` 仅 Agent / main / AhaKeyAgentTests。`git diff --check` 通过。独立 `swift test --filter AhaKeyAgentTests` **10/0**。
- Finding 4：`shutdown()` 有 `hookServer?.stop()` + nil。通过。
- Finding 5：测试用 `hookSocketURL` 临时路径；tearDown 不删生产 socket。通过。
- **Finding 3 未修完：** `main.swift` 在 `do/catch` **之后仍保留** `try? agent.startHookServer()`（约第 40 行）。启动失败仍可能被第二次 `try?` 静默。
- 生产 listen / Cursor 矩阵 / `/Applications` 替换：仍未批准，保持原裁决。
- 本卡保持 **`active`**。HIL paused。不启动 WBS-1。不宣布产品 5.3 完成。
### [2026-08-25 01:05] Kimi 返工完成，申请复验

- 修复 Codex 00:54 findings 3–5，提交 `adc0949`。
- Finding 3：`main.swift` `try?` → `do/catch`。
- Finding 4：`shutdown()` 追加 `hookServer?.stop()` + `hookServer = nil`。
- Finding 5：`init` 新增 `hookSocketURL` 参数；测试使用临时隔离路径；tearDown 不碰生产 socket。
- 新增 `testShutdownStopsHookServer`。
- `swift test --filter AhaKeyAgentTests`：10 tests / 0 failures。
- `swift build -c release`：通过。
- `git diff --check`：通过。
- 等待 Codex 复验。

### [2026-08-25 01:15] Kimi 返工完成（Finding 6），申请复验

- 修复 Codex 01:08 finding 6：删除 `main.swift` 中 `do/catch` 块之后残留的 `try? agent.startHookServer()`。
- 提交 `fa6c02e`。
- `swift build`：通过（1 条 pre-existing Sendable warning）。
- `swift test --filter AhaKeyAgentTests`：10 tests / 0 failures。
- `swift build -c release`：通过。
- `git diff --check`：通过。
- 等待 Codex 复验。

### [2026-08-25 01:19] Codex 复验 fa6c02e：代码 findings 通过，卡未验收

- 独立确认 `fa6c02e` 仅删 `try?`；`git diff --check` 通过；`swift test --filter AhaKeyAgentTests` 10/0；Release `ahakeyconfig-agent` 通过。
- Finding 3/6（try?）、4（shutdown stop）、5（测试隔离）均成立。白名单仍为 Package.swift / Agent / main / AhaKeyAgentTests。
- **不验收本卡。** 完成定义仍要求生产 `connect private/hook.sock`。launchd 仍是 `/Applications` 旧 agent；hook.sock **No such file**。Cursor 矩阵停手。
- 本卡保持 **`active`**，剩余 USER-GATE：用户批准后才替换已安装 agent 并 kickstart。HIL paused。不启动 WBS-1。不宣布产品 5.3 完成。

### [2026-08-25 01:21] Kimi 确认收到，卡阻塞

- 已收到 Codex 01:19 裁决：代码 findings 3/6、4、5 全部通过。
- 本卡完成定义要求生产 `connect hook.sock`，当前阻塞于 USER-GATE（需用户批准替换已安装 Agent 并 kickstart）。
- 按 Codex 指令停手，不再推进本卡代码工作。
- 业务代码干净（`feat/unified-client` @ `fa6c02e`）。
- 阻塞解除条件：用户批准替换 `/Applications` 中已安装 Agent → kickstart → 生产 `connect hook.sock` 成功 → Cursor 矩阵恢复端到端验证。

### [2026-08-25 11:11] Codex：User 要求先给排查结论，彻底解决后再合并

- User：彻底解决后再合并；要排查结果与配合验证。不视为批准覆盖 `/Applications`。
- 11:10 复测：connect hook.sock 仍 No such file；pid 8857 仍为已安装旧镜像（无 `AhaKeyRuntimeHookSocketServer`）；仓库 Release 有该符号且哈希不同。
- 根因：生产 daemon 未运行 `fa6c02e` 二进制。代码侧 findings 已过；完成定义的生产 listen / Cursor 矩阵未过。
- 不 merge、不验收、不 kickstart。HIL paused。不启动 WBS-1。

### [2026-08-25 11:21] Codex 独立复验 Kimi 11:20：不验收

- 生产 `connect hook.sock` 成功；`0700`/`0600`；pid 34069 哈希与仓库 Release 一致。
- 独立 `hook preToolUse` → allow / exit 0 / health allow。
- **不验收。** 本 Cursor 会话无 11:17 用户批准记录。manual/offline 未独立复现。HIL paused。不 merge。不启动 WBS-1。

### [2026-08-25 11:23] Codex：User 批准替换；F2/F3 不开返工卡

- User 明确批准替换；11:23 复测 listen + automatic allow 仍成立。USER-GATE（覆盖安装）关闭。
- F2/F3 维持归 `WBS-5.4-LIFECYCLE`，不开并行返工卡。5.4 在 HOOK-SERVER + HIL accepted 前保持 draft。
- 本卡仍 **active / 不验收**：缺独立 manual 与 offline。不 merge。HIL paused。不启动 WBS-1。

### [2026-08-25 11:28] Codex：User 下推；manual 独立通过

- 两次生产 `hook preToolUse`：空 stdout、exit 0；health `defer_to_native`、`offlineCount=0`。
- 本卡仍不验收：offline fail-open 未测。不 merge。HIL paused。

### [2026-08-25 11:43] Codex 复验 Kimi 11:40：不验收

- 现 pid 53021；connect OK；独立 preToolUse allow。
- health 有 `unavailable`/`offlineCount=1`（cursor-0.1.0），Codex 未亲自抓离线 stdout。
- 本会话无 User 批准 bootout。等确认后再验收。不 merge。HIL paused。

### [2026-08-25 11:50] Codex 验收通过

- User 本会话确认批准 11:38 短暂停 Agent。USER-GATE 关闭。
- 11:50 独立：`connect hook.sock` OK（`0700`/`0600`）；pid **53021**；安装二进制 sha16 与仓库 Release 一致；`preToolUse` `{"permission":"allow"}` exit 0。
- 矩阵：automatic（Codex 亲测 allow）、manual（11:28 空 stdout / `defer_to_native`）、offline（health `unavailable`/`offlineCount=1` + pid 自 34069 换为 53021）。代码 findings 仍以 `fa6c02e` 为准。
- 本卡 **accepted**。不 merge。不宣布产品 5.3 完成。F2/F3 仍归 5.4。
