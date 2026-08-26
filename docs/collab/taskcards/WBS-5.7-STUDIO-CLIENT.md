# 任务卡 WBS-5.7-STUDIO-CLIENT：Studio 纯 Runtime 客户端化

计划/WBS：5.7  
状态：`active`（Kimi 2026-08-26 20:49 接单）
执行 owner：Kimi
基线：WBS 5.6 accepted @ `19eb4dc`；5.2 生产 XPC seam accepted 基线
目标：Studio 仅通过 XPC snapshot/event/operation 管理 Runtime，删除生产直连 BLE/USB。

允许修改：`ahakeyconfig-mac/Sources/AhaKeyConfigApp.swift`、`Sources/Views/**`、`Sources/Models/**`、Studio 侧 `Sources/BLE/**`的退场/诊断改造、Shared 中新建/接入 Studio Runtime client/facade、对应 `Tests/**`，以及本卡/看板/实施计划指定段落。
禁止：不复制设备状态事实源；不保留隐藏生产直连 fallback；不改 Runtime wire v1.1；不改 `Sources/Agent/**` 业务实现、不修固件、不提前做 5.9 正式安装/升级链。
完成定义：snapshot 首屏；event cursor/断档刷新；operation 进度/取消/错误；诊断按需观察；Studio 退出不影响 Runtime；生产目标无 BLE/USB owner。  
测试：UI reducer、重连/重放/断档、Runtime 离线、取消、进程退出；完整 Swift 测试/Release build。  
前置：5.2、5.6 accepted。用户于 2026-08-26 裁决将原“HIL accepted 后开 5.7”改为“先 5.7 真实 UI 接线，再恢复 HIL”，避免依赖环。

## 执行记录（append-only）

等待 Codex 晋级 `ready`。

### [2026-08-25 23:46] Codex 预登记 F-HIL2-1

- HIL-RUNTIME-2：Studio 直连 0x99 三次超时进受限模式（`ble-comm.log` ~23:39）；同固件 Agent 路径 v3 正常。本卡删除 Studio 生产直连时一并关闭。不在 5.6 修。

### [2026-08-26 20:34] Codex：转交 Kimi，晋级 ready

- 用户明确要求：将原 Cursor 的 WBS-5.7 交给 Kimi。Cursor 仅继续独立固件仓 WBS-1 1.2R1，不介入客户端文件。
- 当前真机回归确认 Studio UI 仍走旧直接 BLE 保存；Runtime Store 零写入。该结果只证明旧功能无回归，不算 HIL-CONFIG C1 事务引擎通过。
- 实施切片：
  1. 先建 Studio Runtime client/facade：handshake、snapshot 首屏、event cursor/replay/gap→snapshot、离线/重连状态。
  2. 将现有编辑状态组装为已冻结 `AhaKeyConfigurationPackage`；资源先 `ingestResources`，再 `apply`；用 operation/event 驱动进度、取消、错误和最终 snapshot。
  3. 从生产 UI 保存/连接路径删除 Studio BLE/USB owner 与隐藏 fallback。`Sources/BLE/**` 只可保留非生产诊断/迁移边界，不得在正常 Studio 生命周期扫描、连接或写设备。
  4. 保证 Studio 退出后 Runtime 已受理 operation 继续；诊断日志/RSSI 只按需观察；窗口隐藏无持续 UI 发布/动画。
  5. 先以 reducer/adapter 单测、断线/重放/缺口/取消、完整 Swift tests 和 Release App build 提审。真实 XPC+BLE C1–C6 回到 HIL-CONFIG 执行，不在本卡伪造通过。
- 5.9 安装器/MachServices 正式登记仍不在本卡；本机集成可按既有 runbook 使用可回滚的临时登记。
- Kimi ACK 后将卡翻 `active`；单会话独占客户端白名单。

### [2026-08-26 20:50] Kimi：接单，翻 active

- 基线确认：HEAD `802c618`（含 WBS-5.6 accepted `19eb4dc` 及 HIL 证据文档）。
- 按 20:34 五个切片顺序施工：切片 1 先做 Studio Runtime client/facade（handshake/snapshot/event cursor/replay/离线重连）。
- 本机集成沿用可回滚临时登记（正式 plist 的 MachServices 即为现状）；不动 Agent 业务实现与 wire v1.1。

### [2026-08-26 21:35] Kimi：五个切片完成，整卡提审

- HEAD：`ccab003`（验收范围 `802c618...ccab003`）。
- 切片 1（`5b68f3b`）：`AhaKeyStudioRuntimeFacade`（Shared）——handshake→snapshot 首屏→event cursor 跟随→断档 snapshotRequired 重取快照→离线退避重连；6 项状态机测试。
- 切片 2（`bfc0848`）：`AhaKeyStudioPackageAssembler`（Shared 纯函数）+ Models 薄映射 + facade `apply`/`requestCancellation`。设计要点：资源 ingest 用 GIF 源字节（受理层要求 CGImageSource 可解析源图，RGB565 编码归 Agent 侧）；idle 槽与 defaultAnimation 镜像约束组装期 fail-fast；17 项新测试。
- 切片 3（`4eddb26`）：删除 Studio 生产 BLE/USB owner——`AhaKeyBLEManager`/`AhaKeyUSBHIDTransport` 删除，新建 `AhaKeyStudioRuntimeClient`（Models，@MainActor ObservableObject，包装 facade 投影）作为视图唯一事实源；保存路径改为 `applyDraft`→facade.apply→operation 终态轮询；取消走 requestCancellation；无隐藏直连 fallback；净删约 3000 行。10 项派生单测。
- 切片 4（`ccab003`）：Studio 退出仅断开 facade（不 cancel 已受理 operation）；诊断日志只含 Studio 侧事件、按需观察；窗口移除停 GIF 预览时钟。
- 无法派生字段处置（均删或静态化）：RSSI/型号/设备改名/LED 测试/协议 TX-RX 调试/flash 空间管理 UI。
- 自动门禁：452 tests / 2 skipped / 0 failures；Release `AhaKeyConfig` 与 `ahakeyconfig-agent` 均构建通过；git diff --check 干净。
- 真实 XPC+BLE C1–C6 归 HIL-CONFIG（draft，待用户重新批准真机窗口）。
