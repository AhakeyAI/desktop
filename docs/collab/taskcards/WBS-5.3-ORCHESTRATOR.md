# 任务卡 WBS-5.3-ORCHESTRATOR：Agent 演进为 RuntimeOrchestrator

计划/WBS：5.3  
状态：`accepted`  
执行 owner：Kimi  
基线：`feat/unified-client` @ `b5badce`（含 5.2 `1ac1524` 与 5.3-C；`lastReviewedCommit`：`b49e83e` 切片 1–6）
目标：将 AhaType、AI 检测/批准、动态灯效和防休眠迁入单一后台 Runtime，Studio 退出后继续，且不提前接管 BLE/USB 唯一 owner。

## 允许修改路径

- `ahakeyconfig-mac/Sources/Agent/**`（**排除**下列 5.3-C 已冻结文件）
- `ahakeyconfig-mac/Sources/Shared/**Runtime**`（**排除** `CursorHook*`）
- 对应 `ahakeyconfig-mac/Tests/**`（**排除** `CursorHook*` / `cursor-hooks-*.json` / `cursor-hook-smoke.sh`）
- 本卡执行记录与 board 末尾

### 本卡明确排除（5.3-C 冻结，禁止改）

- `Sources/Agent/CursorHookHandler.swift`
- `Sources/Agent/HookClient.swift`、`HookSupport.swift`（除非为 Orchestrator 增加非 Cursor 调用点且 diff 可证明不改变 Cursor 三态）
- `Sources/Agent/CursorCliLeverSync.swift`、`CursorPermissionsJsonLeverSync.swift`
- `Sources/Agent/ClaudeHookHandler.swift`
- `Sources/Agent/CursorHookRuntimeClient.swift`
- `Sources/Shared/CursorHook*.swift`、`CursorHookInstaller.swift`
- `Sources/Utilities/AgentManager.swift`（安装/升级/卸载路径）
- `Tests/**/CursorHook*`、`Fixtures/cursor-hooks-*.json`、`scripts/cursor-hook-smoke.sh`

## 禁止事项

- 不迁移 BLE/USB ownership（5.5），不改 Cursor 安装器（5.3-C），不改 UI/固件，不做正式登录项/DMG（5.9）。
- 不破坏 interface v1.1，不让 Studio 成为后台功能存活条件。

## 完成定义

- RuntimeOrchestrator 是 AhaType、AI 工具状态、自动批准策略、灯效和防休眠的唯一后台编排入口；Agent 状态仍是独立来源。
- Studio 完全退出后已启用模块继续；全部增强功能关闭时不无条件常驻。
- Snapshot/Event 只在事实变化时发布；正常轮询零 UI 发布、零常规磁盘日志。
- 进程重启、模块启停、策略变化、错误隔离、Hook socket 集成测试通过。
- 完整 Swift 测试、Release build、`git diff --check` 通过；提交后停在 `review`。

## 前置与晋级

依赖 5.2 与 5.3-C accepted。完成后进入第一次真实键盘 HIL，不得直接宣布 5.3 完成。

## 执行记录（append-only）

等待 Codex 晋级 `ready`。

### [2026-08-24 11:45] Codex 晋级 ready

- `WBS-5.3-C-CURSOR` 已 accepted。基线仍为 `feat/unified-client`；5.3-C 实现提交 `e8e8ca5` / `9ed14ce` / `b5badce`。
- 本卡晋级 `ready`，owner Kimi。不自动 active，由 Kimi ACK 后开做。
- 禁止改 Cursor installer；不接管 BLE/USB。

### [2026-08-24 11:47] Codex 冻结基线

- 冻结 SHA：`b5badce`。Kimi ACK 后相对该提交开做，不得改 `CursorHookInstaller` / 安装器白名单文件。
- 卡保持 `ready` 直至 Kimi 接单 ACK 为 `active`。Cursor 不实施。

### [2026-08-24 11:50] Kimi 接单 ACK

- 核验 `b5badce`（仅测试文件）与 Codex 11:45 裁决；基线冻结 `b5badce`。
- 本卡 Kimi 接单开做。白名单与禁止事项已确认：不碰 Cursor 安装器、不接管 BLE/USB、不改 UI/固件、不破坏 interface v1.1。
- 第一步：通读 Agent 现状（AhaType、AI 检测/批准、动态灯效、防休眠的当前归属与生命周期），产出切片设计后按 red→green 实施。

### [2026-08-24 11:50] Codex ACK → active

- 已收到 Kimi 11:50 接单 ACK。本卡 `ready` → `active`。
- Codex 本轮只读：HEAD 仍为 `b5badce`，无新业务提交。不改 Agent/**。
- 提交后停 `review`；不得宣布 5.3 完成；不启动 HIL/WBS-1。

### [2026-08-24 11:51] Codex 收紧白名单

- `Agent/**` 含已 accepted 的 Cursor Hook 实现。本卡不得改上列 5.3-C 冻结文件。
- Orchestrator 对 Hook socket 只做 Runtime 侧编排/集成测试入口，不重写 installer 或三态 reducer。

### [2026-08-24 11:58] Kimi 切片设计（ Slice 1 开工前）

现状盘点（只读）：
- **防休眠**：`PowerProtectionManager`（Shared）已被 Agent 持有，由 processDetector + hook 活动双源驱动。
- **AI 检测/批准**：`ProcessDetector`（Shared）+ Agent socket `state/permission/approval_status` 命令链；拨杆查询走 `AhaKeyRuntimeHookSocket` seam。
- **动态灯效**：Agent `sendState`（0x90 LED/OLED）路径；Studio 侧另有预览逻辑（不在本卡白名单）。
- **AhaType**：实现在 `Sources/Utilities`（`NativeSpeechTranscriptionService`、`AhaTypeTextOptimizer` 等），**不在本卡白名单内**。

切片计划（每片 red→green）：
1. **Orchestrator 核心（纯逻辑）**：`Sources/Shared/RuntimeOrchestratorCore.swift`——`AhaKeyRuntimePolicy → 模块集合` 映射、常驻判定（全关不常驻）、变更才发布的 transition 计算。不动现有进程行为。
2. **模块生命周期协议**：`RuntimeModule` 契约（start/stop/status）+ 错误隔离（单模块失败不影响其他）+ 进程重启/模块启停测试。
3. **防休眠接入**：Agent 内 `PowerProtectionManager` 挂到 orchestrator 下，行为不变。
4. **AI 状态/批准接入**：socket 状态链与拨杆查询挂到 orchestrator。
5. **灯效接入**：`sendState` 路径挂到 orchestrator。
6. **AhaType 接入**：仅做生命周期控制 seam；**代码实体迁移需扩大白名单至 `Sources/Utilities` 或新 target，需 Codex 裁决**（切片 6 开工前提出）。

完成定义对齐：Snapshot/Event 只在事实变化时发布（切片 1 transition 即此语义）；正常轮询零 UI 发布零常规磁盘日志（切片 3-5 保持现有 coalescer 语义）。

### [2026-08-24 11:52] Codex 切片裁决

- **切片 1–5：批准**。立即从切片 1 red→green 开工。`PowerProtectionManager.swift` 文件名不含 Runtime，**不在** `Shared/**Runtime**` 内；切片 3 只在 Agent 侧挂接，不改该文件。不扩大 Shared 全局白名单。
- **切片 6：驳回整包 `Sources/Utilities`。** `NativeSpeechTranscriptionService` / `AhaTypeTextOptimizer` 含 HUD/UserDefaults，属 UI。本卡只允许 Orchestrator 生命周期 seam（模块 id + start/stop 端口，代码放 `Shared/**Runtime**` 或非冻结 Agent 文件）。实体迁移留到后续带精确文件名单的卡（5.4/后续），切片 6 开工前再申请。
- 不宣布 5.3 完成；不启动 HIL。

### [2026-08-24 11:55] Codex 切片 1 只读核验

- 工作区未提交：`Sources/Shared/RuntimeOrchestratorCore.swift`、`Tests/AhaKeyConfigSharedTests/RuntimeOrchestratorCoreTests.swift`。白名单内，未碰 5.3-C 冻结文件。
- `swift test --filter RuntimeOrchestratorCoreTests`：6 tests，0 failures。
- 非整卡验收。提交、切片 2+ 与 `review` 仍归 Kimi。HEAD 仍为 `b5badce`。

### [2026-08-24 11:56] Codex 切片 1 提交核对

- `bf9dd86` 仅含 `RuntimeOrchestratorCore.swift` + `RuntimeOrchestratorCoreTests.swift`；相对 `b5badce` 的 `git diff --check` 通过。
- `lastReviewedCommit` = `bf9dd86`。切片 2+ 未验收。切片 6 维持 11:52 裁决（生命周期 seam，不放开 Utilities）。

### [2026-08-24 12:53] Codex ACK 阶段汇报

- 确认切片 1 已提交 `bf9dd86`；切片 2 进行中。
- 切片 6 无需再等：生命周期 seam only，不放开 Utilities。

### [2026-08-24 12:55] Codex 切片 2 中途只读核验

- 未提交：`RuntimeModule.swift`、`RuntimeModuleRegistry.swift` + 测试。白名单内。
- `swift test --filter RuntimeModule` 编译失败：旧 `RuntimeModuleLifecycleTests` 与 async 协议/`failed(Error)` 不一致；`TestModule` actor 隔离。
- 提交前须修绿。不改 Kimi 文件。非整卡验收。

### [2026-08-24 12:59] Codex 切片 2 验收退回

- `8ed6ca7` 路径白名单通过；独立 `swift test --filter RuntimeModule` **编译失败**（`TestModule.stop` 重复体 + `throws` 与协议不符）。
- `lastReviewedCommit` 仍为 `bf9dd86`。切片 3 不得开工，直至定向测试绿。

### [2026-08-24 13:07] Codex 切片 2 核对通过

- `1fc1862` 仅修 `RuntimeModuleRegistryTests.swift`；`git diff --check 8ed6ca7..1fc1862` 通过。
- HEAD 上 `swift test --filter RuntimeModule`：9 tests，0 failures。
- `lastReviewedCommit` = `1fc1862`。非整卡。切片 3 可开：Agent 挂接 `PowerProtectionManager`，不改该文件。切片 6 仍为生命周期 seam。

### [2026-08-24 13:31] Codex 切片 3 核对通过

- `7e3bf47`：`AhaKeyAgent.swift` + `PowerProtectionRuntimeModule.swift` + 测试。未改 `PowerProtectionManager.swift` / Cursor Hook。
- 独立 `swift test --filter PowerProtectionRuntimeModule --filter RuntimeModule`：12/12。`git diff --check` 通过。全量 264 项本轮未复跑。
- `lastReviewedCommit` = `7e3bf47`。非整卡。切片 4 可开。残留：`init` 内异步 `Task` 启动。切片 6 仍为生命周期 seam。

### [2026-08-24 13:44] Codex 切片 4 核对通过

- `78e0d6e`：`AhaKeyAgent.swift` + `AIIntegrationRuntimeModule.swift` + 测试。未改 Cursor Hook / `PowerProtectionManager.swift`。socket 命令分发仍在 Agent 原位。
- 独立 `swift test --filter AIIntegrationRuntimeModule --filter RuntimeModule`：15/15。`git diff --check 7e3bf47..78e0d6e` 通过。全量 267 项本轮未复跑。
- `lastReviewedCommit` = `78e0d6e`。非整卡。切片 5 可开（灯效 `sendState` 挂接）。残留：`Task { applyTransition }` 异步启动；`residencyChanged: nil` 未被 registry 消费。切片 6 仍为生命周期 seam。

### [2026-08-24 13:45] Codex 切片 5 开工门禁

- 范围：`DynamicLightingRuntimeModule`（Shared 闭包委托）+ Agent 将 `sendState`（0x90 LED/OLED）启停挂到 `RuntimeModuleRegistry`。提交须含 Agent 接线，不得只交适配器。
- 冻结：0x90 帧、`StateCommandWritePolicy`、live-state 文件协议、Studio 预览、`PowerProtectionManager.swift`、Cursor Hook 文件。策略化 gating 仍待后续装配。
- 切片 6 仍只做 AhaType 生命周期 seam，不放开 `Sources/Utilities`。Cursor 不实施。

### [2026-08-24 13:50] Codex 切片 5 语义裁决

- `sendState` 是按次 0x90 写入，不是会话。禁止把每次调用做成 module start/stop。
- 正确形状：`DynamicLightingRuntimeModule` 启停「发送能力」；Agent 注册并 `applyTransition`；`sendState` 留在 Agent 并受 running 门控。0x90 帧 / 命令分发 / live-state 协议冻结。
- 提交须含 Agent 接线；只交适配器退回。策略化 gating 可仍 always-on。切片 6 仍为生命周期 seam。

### [2026-08-24 13:52] Codex 切片 5 中途只读核验

- 未提交：`LightingRuntimeModule.swift`；Agent 仅空字段，`sendState` 未门控，无测试。`lastReviewedCommit` 仍 `78e0d6e`。
- 提交前：registry 接线；`sendState` 留 Agent 并门控 `.running`；勿迁移 `lastSentState` / reset / live-state；idle 不得 apply。Cursor 不改。

### [2026-08-24 13:59] Codex 切片 5 催办

- 工作区自 13:52 无新写入。已在 board 对 @Kimi 发 `需要回复：是`。卡保持 `active`。Cursor 不实施。

### [2026-08-24 16:22] Kimi 整卡回传（六切片完成，请求 review）

- 切片 6 完成：`AhaTypeRuntimeModule` 生命周期 seam（引擎实体留 Studio/Utilities 未动，onStart/onStop 注入点文档化，Agent registry 登记），3 项测试通过。
- 切片链：1 核心 `bf9dd86` → 2 Registry `8ed6ca7` → 3 防休眠 `7e3bf47` → 4 AI 集成 `78e0d6e` → 5 灯效门控 `a8a5a5b` → 6 AhaType seam `b49e83e`。
- 整卡门禁：`swift test` 274 项 0 失败；release agent 构建通过；`cursor-hook-smoke.sh` PASS；`runtime-xpc-signed-smoke.sh` 双向通过；`git diff --check` 通过。
- 禁止事项自查全过；详细回传包见 board 16:22 条目。请求 Codex 翻 review 独立验收。

### [2026-08-24 16:24] Codex 整卡验收 accepted

- 独立复验 `b5badce..b49e83e`：14 文件，白名单内，无 Cursor Hook / Utilities / `PowerProtectionManager.swift`。`git diff --check` 通过。
- 独立 `swift test`：**274** 项、2 skip、0 失败。独立 `swift build -c release --product ahakeyconfig-agent` 通过。
- `lastReviewedCommit` = `b49e83e`。本卡 `accepted`。
- 残留（不挡本卡、不宣布产品 5.3 完成）：Agent 仍 always-on，未调用 `RuntimeOrchestratorCore.plan`（策略化装配属 5.4）；`init` 内异步 `Task` 启动；AhaType isolation 测试未真正注册失败模块。
- 下一张 `HIL-RUNTIME-1` 为 USER-GATE，不晋级 `ready`。不启动 WBS-1。Cursor 不 commit。
