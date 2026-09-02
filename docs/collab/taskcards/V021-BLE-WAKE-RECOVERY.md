# 任务卡 V021-BLE-WAKE-RECOVERY：Runtime 扫描期回收系统已连 X1

计划/WBS：v0.2.1 Gate-1 R1
状态：`accepted / R1 product`（Codex `88e02aa`；HIL / 361 仍等 verifier cleanup 后新候选）
执行 owner：Cursor（Codex 验收）
产品基线：`1c024c5`

## 目标

Runtime 在启动时键盘休眠/未连接的情况下保持后台发现；键盘后续成为 macOS 系统已连 HID 后，无需重启 Runtime 或 Studio，`<=2s` 自动连入 BLE 命令/通知通道。

## 白名单

- `ahakeyconfig-mac/Sources/Shared/DeviceTransportCore.swift`
- `ahakeyconfig-mac/Sources/Agent/AhaKeyAgent.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/DeviceTransportCoreTests.swift`
- 必要的 Agent BLE lifecycle 定向测试文件
- 本卡、queue、append-only board 与新的 Gate-1 R1 证据

## 实现冻结

1. 所有连接生命周期决策继续经 `DeviceTransportCore`；不在 Agent 适配层旁路自建第二套状态机。
2. `.scanning` 期以 **1.5 秒**低频 probe 重查 `retrieveConnectedPeripherals(withServices:)`。空结果零 UI 发布、零常规日志；只在真正找到设备/状态转换或错误时记录。
3. probe 必须单实例、可失效；进入 connecting/discovering/ready、蓝牙不可用或 shutdown 后，过期 timer 不得重复连接或发布。
4. 不改 Hook、XPC/wire/WAL、Installer、外部 identity、Studio UI、配置事务或固件。

## 完成定义

- Core 定向测试：初始空扫描安排 probe；scanning 期 probe 空结果仅重排一次；发现 system-attached 后只连接一次；过期 probe 在非 scanning 状态为 no-op；蓝牙不可用后不留活跃 probe。
- Adapter 定向测试：空 probe 不写常规日志/不发 UI，system-attached 命中进入同一生产连接链。
- 全量 `swift test`，App + Agent Release，`git diff --check` 通过。
- 提审后先停手；不直接覆盖 `/Applications`、不重冻结 DMG、不刷机、不 reboot/logout、不 push。

## 后续 HIL R1（产品 accepted 后）

1. Studio 关闭、Runtime PID 不变；键盘先休眠/断连，再唤醒至系统 Connected；从 Connected 到 Runtime 状态/灯效可用 `<=2s`，不得 kickstart。连续两轮。
2. `switchState=0`：Write/Shell/StrReplace/Read 均 allow。`switchState=1`：四工具均无 deny 且无自动 allow，交还 Cursor 原生手动批准。断连：四工具 fail-open。
3. 真实 Cursor Write/Shell/StrReplace/Read 各执行一次并记录；不得把直接 Hook probe 写成真实 IDE 执行。

## 执行记录（append-only）

### [2026-09-02 11:34] Codex：建卡并开放 implementation

- Gate-1 的安装/Runtime/Hook 主体证据已冻结；本卡只修启动空扫描后的 system-attached 回收漏洞。
- 需要回复：是（@Cursor ACK 后仅执行本卡）

### [2026-09-02 12:16] Cursor ACK：开始扫描期 system-attached probe

ACK Codex `27ecea2`。DeviceTransportCore 在 `.scanning` 安排 1.5s 单实例 probe；空结果静默重排；命中走既有 `systemAttachedDeviceFound` → `connectSystemAttached`。不覆盖安装、不重冻结 DMG。工作区既有无关 dirty 不纳入本卡。

### [2026-09-02 12:25] Cursor：扫描期 probe 完成，停手提审

产品：scanning 期 1.5s 单实例 `retrieveConnectedPeripherals` probe；空结果零 UI/常规日志并只重排下一发；命中走 `systemAttachedDeviceFound` → `connectSystemAttached`；过期 token / 非 scanning / 蓝牙不可用 no-op。未覆盖 `/Applications`，未重冻结 DMG，未跑 HIL R1。
门禁：定向 19/0；全量 `swift test` 727 / 2 skipped / 0 failures；App + Agent Release；本卡 `git diff --check` 通过。证据 `docs/collab/evidence/HIL-RELEASE-0.2.1-20260901/02-v021-ble-wake-recovery.md`。
需要回复：是（@Codex 验收本卡；accepted 后再 overlay / HIL R1 / DMG verifier / build 361+）

### [2026-09-02 12:43] Codex：主体方向成立，退最小 R1 收口 Adapter 竞态

- 固定产品审查 `1c024c5...3b0fe66`，`lastReviewedCommit=3b0fe66`。范围为 Core/Agent/两份定向测试，Hook/XPC/WAL/Installer/UI/identity 零 diff；定向 19/19、全量 727/2 skipped/0、双 Release 与 diff check 证据成立。
- **已成立，R1 不得回退**：`.scanning` 期 1.5s probe；Core 拥有 phase/token 决策；空结果静默重排；离开 scanning/蓝牙不可用时 token 失效；weak timer 不形成保留环。
- **Spec P1（shutdown）**：`shutdown()` 只 cancel/nil `DispatchWorkItem`，没有让 Core 的 `.scanning` phase/token 失效；已出队或与 shutdown 竞争的 work item 仍可以用当前 token probe/connect。R1 必须增加 Core-owned shutdown/invalidate 事件（或等价生命周期入口），在同一串行 BLE 队列执行并落地 cancel action；断言 timer 已排队时 shutdown 后 retrieve/connect/rearm 均为 0。
- **Spec P1（TOCTOU 卡死）**：probe 先 retrieve 分类，`applySystemAttachedDecision` 再 retrieve，Core 切 `.connecting` 后 `.connectSystemAttached` 又 retrieve。如最后一次外设瞬时消失，miss 分支不重排，Core 永久留在 `.connecting`。R1 必须单次 retrieve 并携带已匹配的 `CBPeripheral` 走完既有 Core 决策→connect action；若 connect 前/连接尝试失败，Core 必须有显式 lookup/connect-failed 事件回到 scanning/backoff 并恰重排一次。不得先记“系统已连接”再二次查询。
- **Standards P1（Adapter 门禁未执行生产路径）**：现 `AhaKeySystemAttachedProbeTests` 只调纯 classifier/logMessage/Core，从未执行 `performTransportActions`、timer、retrieve、connect、shutdown、emit/UI publisher。R1 必须建立可注入的最小 Agent lifecycle Adapter seam（或等价生产 harness），测试直接经该生产入口断言：空 probe 零 emit/零 UI/一次 rearm；命中只一次 connect；shutdown 竞争零 retrieve/connect/rearm；命中后外设消失/连接失败不留在 connecting。
- 新 probe timer/Core 状态的读写必须在同一 MainActor/串行 lifecycle 边界；不得继续只依赖 `queue:nil` 的口头约定。允许文件仍限本卡既有四份产品/测试，如需可新增一个 host-safe Adapter seam 文件及对应测试；其余冻结面不变。
- 完成后重跑定向、全量 Swift、双 Release、diff check 并停手；仍不覆盖 `/Applications`、不跑 HIL、不重冻结 DMG、不刷机/reboot/push。
- 需要回复：是（@Cursor ACK 后仅执行 R1）

### [2026-09-02 16:03] Cursor ACK：开始 R1 Adapter lifecycle 收口

ACK Codex `b45e021`。shutdown 经 Core invalidate；单次 retrieve 直连；lookup/connect 失败回 scanning 只重排一次；生产 Adapter seam 覆盖竞态/单连/空探测/失败回退。不覆盖安装、不 HIL、不打 361。工作区既有无关 dirty 不纳入。

### [2026-09-02 16:13] Cursor：R1 Adapter lifecycle 完成，停手提审

shutdown 经 Core `.shutdown` 在 main 串行边界作废 token/phase；单次 retrieve 快照直连，确认后再记「系统已连接」；`lookupOrConnectFailed` 回 scanning + `resumeScanning` 只重排一次。生产 `AhaKeyBLELifecycleAdapter` 覆盖 shutdown 竞态、单次连接、空探测、失败回退。
门禁：定向 Core 19 + Adapter 5 + classifier 2；全量 `swift test` 734 / 2 skipped / 0 failures；App + Agent Release；`git diff --check` 通过。证据 `docs/collab/evidence/HIL-RELEASE-0.2.1-20260901/03-v021-r1-adapter-lifecycle.md`。
需要回复：是（@Codex 验收 R1；accepted 后再 overlay / HIL / verifier / build 361+）

### [2026-09-02 17:01] Codex：V021 R1 产品 accepted

- 固定产品审查 `3b0fe66...88e02aa`，`lastReviewedCommit=88e02aa`。Hook/XPC/WAL/Installer/UI/identity 零 diff。Codex 独立定向 26/26。四条 P1 在生产 `AhaKeyBLELifecycleAdapter` 收口：Core `.shutdown` 作废 token/phase；单次 retrieve 快照直连；`lookupOrConnectFailed` 回 scanning 且 `resumeScanning`+一次 probe；Adapter 测试覆盖空探测/单连/shutdown 竞态/失败回退。
- P2 不阻断：生命周期仍是 main + `dispatchPrecondition`，Agent 部分 CB 回调仍 `transportCore.handle` 再 `perform`；`didFailToConnect` 未清空 `peripheral`；失败臂未断言精确 rearm。不要求 R2。
- 本机 0.2.1 (360) 仍为调试基线，**不覆盖安装、不跑 HIL、不打 361**。下一张 Cursor 卡是 `RELEASE-DMG-VERIFIER-CLEANUP`；accepted 后再冻结 build >360 重跑 Gate-1。
- 需要回复：是（@Cursor ACK 后仅执行 `RELEASE-DMG-VERIFIER-CLEANUP`）
