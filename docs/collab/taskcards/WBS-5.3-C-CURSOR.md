# 任务卡 WBS-5.3-C-CURSOR：Cursor Hook 三态与安装迁移

计划/WBS：5.3-C、§9.4、§15.0-3  
状态：`active`  
执行 owner：Cursor  
独立验收方：Kimi + Codex（Cursor 不自验其业务实现）  
基线：`feat/unified-client` @ `1ac1524`（WBS 5.2 accepted）  
目标：实现“拨杆上推自动批准、下推恢复 Cursor 原生手动批准”，Runtime 离线/超时 fail-open，并永久关闭旧客户端重复 Hook 与硬 deny 问题。

## 允许修改路径

- `ahakeyconfig-mac/Package.swift`（仅新增/接入本卡测试 target 或 Shared 源文件所需）
- `ahakeyconfig-mac/Sources/Agent/CursorHookHandler.swift`
- `ahakeyconfig-mac/Sources/Agent/HookClient.swift`
- `ahakeyconfig-mac/Sources/Agent/HookSupport.swift`
- `ahakeyconfig-mac/Sources/Agent/ClaudeHookHandler.swift`（仅 Cursor 第三方映射来源 no-op/去重）
- `ahakeyconfig-mac/Sources/Agent/CursorCliLeverSync.swift`
- `ahakeyconfig-mac/Sources/Agent/CursorPermissionsJsonLeverSync.swift`
- `ahakeyconfig-mac/Sources/Agent/CursorHookRuntimeClient.swift`（可新建 production adapter）
- `ahakeyconfig-mac/Sources/Utilities/AgentManager.swift`（仅 Cursor Hook 检测、安装、升级、卸载及诊断读取相关段落）
- `ahakeyconfig-mac/Sources/Shared/AhaKeyPaths.swift`（仅新增 production Runtime Hook socket 路径常量）
- 以下 Shared 深模块可新建，名称可在不扩大职责的前提下等价调整：
  - `ahakeyconfig-mac/Sources/Shared/CursorHookDecisionReducer.swift`
  - `ahakeyconfig-mac/Sources/Shared/CursorHookRuntimeQueryPort.swift`
  - `ahakeyconfig-mac/Sources/Shared/CursorHookInstaller.swift`
  - `ahakeyconfig-mac/Sources/Shared/CursorHookHealthStore.swift`
  - `ahakeyconfig-mac/Sources/Shared/CursorHookSourceDeduper.swift`
- 以下测试/fixture 可新建：
  - `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/CursorHookDecisionReducerTests.swift`
  - `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/CursorHookInstallerTests.swift`
  - `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/CursorHookHealthStoreTests.swift`
  - `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/CursorHookRuntimeClientTests.swift`
  - `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/CursorHookRuntimeQueryPortTests.swift`
  - `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/CursorHookSourceDeduperTests.swift`
  - `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyPathsTests.swift`
  - `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/Fixtures/cursor-hooks-v0-nine-events.json`
  - `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/Fixtures/cursor-hooks-v1-single-entry.json`
- `ahakeyconfig-mac/scripts/cursor-hook-smoke.sh`（可新建，无设备 smoke）
- 本卡执行记录与 board 末尾

除上述精确路径与明确可新建文件外不得扩展；如实现证明某个文件不需要修改，应保持不动。

## 禁止事项

- 不修改 libxpc server、Runtime 持久层、BLE/USB、UI、固件或公开 interface v1.1。
- 不修改 `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`、`AhaKeyRuntimeProductionSeam.swift`、`AhaKeyRuntimeHookSocket.swift` 或仓库根 `Sources/**` 旧副本。
- 不写永久 `Write(*)`/`Shell(*)` 白名单；不把 `ask` 伪装成手动批准。
- 不在 Runtime 未知、离线或超时时返回 deny；不覆盖第三方 Hook。

## 完成定义

- 单一 decision reducer 输出 `allow | deferToNative | unavailable`；仅 `allow` 显式放行，后两者均不阻塞 Cursor 原生流程。
- IDE 与 CLI 只保留一条 AhaKey 决策入口；Claude 兼容来源 no-op/去重，一次工具调用最多一次 Runtime 查询。
- marker 版本迁移覆盖安装、覆盖升级、卸载、旧残留和第三方 Hook 保留。
- health/诊断不含 prompt、命令、路径明文；有 timeout 与离线计数。
- fake Runtime 覆盖 Read/Write/Shell/MCP/Task × 自动/手动/离线/超时；真实 Runtime 无设备 smoke 覆盖当前版及上一支持版 Cursor IDE/CLI。
- 相关测试、完整 Swift 测试、Release build、`git diff --check` 全通过；回传后进入 `review`，不得开始 5.3。

## 实施切片与测试 seam

必须按以下垂直切片 red → green，不先批量写实现：

1. **Decision seam**：`CursorHookDecisionReducer` 以 Runtime `automatic | manual | unavailable` 和查询结果为输入，以 `allow | deferToNative | unavailable` 为输出。先覆盖 auto 显式 allow，再覆盖 manual/offline/timeout 空 stdout。
2. **Query seam**：`CursorHookRuntimeQueryPort` 每次工具事件只允许一次 query；fake adapter 证明 Read/Write/Shell/MCP/Task × 四态，production adapter 再接 `AhaKeyRuntimeHookSocketClient`。
3. **Routing seam**：只有 Cursor `preToolUse` 进入决策链；旧 `beforeShellExecution` / `beforeMCPExecution` 在迁移残留场景必须中性 no-op。Claude `PreToolUse` 在 `CURSOR_VERSION` 存在时零查询 no-op。
4. **Installer seam**：fixture 驱动 install / v0 九事件升级 / reinstall / uninstall；断言第三方条目保留、AhaKey 决策入口唯一、旧重复事件清除。
5. **Health seam**：只记录 event 分类、decision、latency bucket、timeout/offline 计数和版本；禁止 prompt、command、cwd、完整路径或环境变量明文。验证 5 MB × 3 轮转及详细模式 15 分钟自动关闭。
6. **真实 smoke seam**：在隔离的临时 HOME/fixture 上运行 agent hook；随后才安装到测试 Cursor 环境，分别验证 IDE/CLI auto、manual、offline、timeout 与旧残留。不得在单元测试阶段覆盖真实 `~/.cursor`。

## 前置与晋级

依赖 WBS 5.2、`OPS-DISPATCH-RELIABILITY` 与 `OPS-CURSOR-REARM` accepted。晋级时 Codex 提供真实 Runtime socket 路径、支持的 Cursor 版本和精确文件白名单。

## 已冻结的晋级输入

- 生产 Runtime Hook socket：`~/Library/Application Support/AhaKeyConfig/private/hook.sock`，由 `AhaKeyPaths` 生成；父目录必须 `0700`，socket 必须 `0600`。legacy `ahakey.sock` 仅可作为迁移期 adapter，不得成为新 interface。
- 当前 Cursor IDE/CLI：`3.17.8`（本机 App 与 bundle CLI 已核实）。
- 上一支持版：`3.7.27`。本机 `20260822T111828/main.log` 证明它是升级至 3.17.8 前最后运行版本；官方 `downloads.cursor.com` production build `e48ee6102a199492b0c9964699bf011886708ba3` 与 Homebrew 历史 cask 提供可校验 arm64 产物（SHA-256 `3ec727cbf471a40b03f564b4f67fd26a39a78b14418ba0c718fb7d69b35fbc16`）。进入最终 review 前仍须下载校验并实际运行 N-1 IDE/CLI smoke。
- `deferToNative` / `unavailable` 的标准输出形态冻结为：消费 stdin、stdout 为空、exit `0`、`failClosed: false`。官方没有定义 `defer` 权限值；`preToolUse` 的 `ask` 当前不执行，`beforeShellExecution` / `beforeMCPExecution` 的 `ask` 会主动改变 Run Mode，二者均不得用于中性委托。
- `allow` 才输出 `{"permission":"allow"}`；业务路径不得用非零退出、无效 JSON 或超时冒充 fail-open。
- Claude `PreToolUse` 在 Cursor 环境的 no-op 判定使用 `CURSOR_VERSION`；不得用兼容别名 `CLAUDE_PROJECT_DIR` 判断。no-op 必须零 Runtime 查询、零权限输出、零诊断并 exit `0`。
- 上述契约仍须分别在 3.17.8 IDE 与 bundle CLI 做真实 smoke；官方统一 schema 不替代双端证据。
- 当前 `~/.cursor/hooks.json` 无 AhaKey 条目；历史 9 条备份仅作为迁移 fixture 输入，测试不得覆盖真实用户配置。

## 执行记录（append-only）

等待 Codex 晋级 `ready`。

### [2026-08-23 19:02] Codex 晋级 / Cursor ACK

- 前置 WBS 5.2、`OPS-DISPATCH-RELIABILITY`、`OPS-CURSOR-REARM` 均已 accepted。
- 基线冻结为 `feat/unified-client` @ `1ac1524`；精确路径白名单、production Hook socket、Cursor 3.17.8 与中性 stdout 契约已冻结。
- 本卡晋级并由 Cursor ACK 为 `active`。Cursor 按垂直 TDD 切片实施；Kimi + Codex 独立验收，Cursor 不自验。
- N-1 Cursor 产物不阻塞 fake Runtime 和 3.17.8 实现，但进入最终 accepted 前必须补齐。

### [2026-08-23 19:35] Cursor 本地实现与验证

- decision/query/routing/installer/health 五个深 seam 已实现；真实 agent 改走 restricted Runtime Hook socket，manual/offline/timeout 均为空 stdout + exit 0。
- v0 九事件真实备份形态与 v1 单入口 fixture 已覆盖 upgrade/reinstall/uninstall、第三方保留和 marker 迁移。
- 隔离 HOME 的真实 agent + fake Runtime 进程 smoke 覆盖 Read/Write/Shell/MCP/Task × automatic/manual，以及 offline/timeout；旧 Cursor 事件和 Cursor 中 Claude `PreToolUse` 为零查询 no-op。
- 常开 health 仅输出有界字段；5 MB × 3、跨进程锁、timeout/offline 计数和详细模式 15 分钟到期均有测试。
- `swift test`：245 tests，1 个显式 process-smoke skip，0 failures；随后脚本单独运行该 process smoke 通过。Release build、`git diff --check` 通过。
- 当前 Cursor `3.17.8` 已由 bundle CLI 核实。N-1 `3.7.27` arm64 官方产物已下载，SHA-256 与历史 cask 一致，解包后 CLI 输出 `3.7.27`。
- 尚缺：需要登录/可回滚的测试 Cursor profile，实际触发 3.17.8 与 3.7.27 IDE/CLI 工具事件；当前独立 CLI 状态为 `Not logged in`。未获用户明确授权前不覆盖真实 `~/.cursor/hooks.json`，也不创建 git commit。
