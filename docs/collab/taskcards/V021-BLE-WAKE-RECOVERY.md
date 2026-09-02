# 任务卡 V021-BLE-WAKE-RECOVERY：Runtime 扫描期回收系统已连 X1

计划/WBS：v0.2.1 Gate-1 R1
状态：`ready / implementation`
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
