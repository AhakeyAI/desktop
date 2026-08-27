# 任务卡 HIL-CONFIG-STUDIO-XPC-CLIENT：Studio 生产传输连不上 libxpc Runtime

计划/WBS：HIL-CONFIG 阻塞返工  
状态：`review`（生产 libxpc client 已提审；HIL C1 仍暂停）
执行 owner：Cursor
基线：HIL-CONFIG active；CAPS14 accepted @ `3b08d82`；5.7 accepted @ `488097d`  
目标：让 Developer ID 签名的 Studio 能对 `lab.jawa.ahakeyconfig.runtime` 完成 handshake+snapshot，从而恢复 HIL C1 apply。

## 现象

临时 HIL Agent（PID 76134，sha `392d5e06…`）已重新协商：

- 0x99 compact 14B → protocol v3 / **current**
- primary `0..<276`，reclaim `276..<284`

同机 libxpc `RuntimeXPCSmokeClient` 正向 handshake+snapshot **exit 0**。  
仓库 5.7 Studio（`/tmp/ahakey-hil-studio`，identifier `lab.jawa.ahakeyconfig`，Team `P2VFVRZK7P`）主界面为 **「Runtime 离线」**，无法「写入键盘」。

## 原因

- Agent 生产路径：`AhaKeyRuntimeXPCLibXPCServer`（C libxpc，dictionary 字段 `payload` 承载 JSON wire）。
- Studio 生产路径：`AhaKeyStudioRuntimeXPCTransport` → `AhaKeyRuntimeXPCConnectionTransport`（`NSXPCConnection` + `AhaKeyRuntimeXPCServiceProtocol.exchange`）。
- WBS-5.7 真实 endpoint 测试写明省略 NSXPC/MachService 层，由 5.2 libxpc smoke 覆盖。双进程 GUI 因此从未在 HIL 上接通过。

## 建议最小切片（待 Codex 授权，勿在 HIL 卡内施工）

1. Studio 生产 transport 改为与 5.2 smoke 相同的 libxpc client（`payload` JSON），保留 peer 签名要求。
2. 定向：libxpc 正/负 smoke 不回归；新增或对齐「Studio 标识签名客户端 handshake+snapshot」。
3. 禁止改 planner、wire 字段、固件、安装器、正式 plist。

## Codex 诊断与授权（2026-08-27 22:21）

### 可重复红灯

在临时 Studio 连接当前 HIL Agent 后运行：

`/usr/bin/log show --last 5m --style compact --predicate 'process == "AhaKeyConfig"' | rg 'received an undecodable message.*no exported object'`

已实际复现：`NSXPCConnection` 消息到达 PID 76134，但 libxpc server 没有 NSXPC exported object，系统丢弃消息并取消连接。相同 service 上 libxpc 正向 smoke handshake+snapshot 成功，因此 BLE、能力协商、MachServices 登记、同 UID 与 Studio Developer ID 签名均不是本轮根因。

### 冻结方案

只允许把 **Studio 客户端** 对齐到已经 accepted 的 libxpc server，不允许反向给 Agent 增加第二个 NSXPC listener：

1. 在 Shared 增加可复用的 `AhaKeyRuntimeXPCLibXPCClient`（名称可等价），使用持久 Mach service connection；每个 dictionary 仅使用既有 `payload` JSON wire，单条上限继续 8 MiB。
2. 客户端必须保证单连接最多一个 in-flight request；并发 facade 操作应有界串行，不能触发 server `busy`、回复错配或无界排队。超时、取消、XPC error、`error` dictionary、缺失/超限 payload 必须明确失败；失效连接不得继续复用，后续 facade 重连从新 connection + handshake 开始。
3. `AhaKeyStudioRuntimeXPCTransport` 改为持有上述 libxpc client；`AhaKeyStudioRuntimeTransport`、请求/响应 Codable wire、facade 状态机与 UI API 不变。旧 `AhaKeyRuntimeXPCConnectionTransport` 可保留给既有 NSXPC 单元 seam，但不得再是 Studio 生产入口，注释必须纠正。
4. `AhaKeyConfigShared` 可依赖既有 `CLibXPC`；不得复制私有 XPC 声明。现有 peer signing requirement 仍由 Agent server 在 resume 前强制，禁止放宽 Team ID、signing identifier、UID 或 malformed/oversize 拒绝逻辑。
5. 正向 signed smoke 必须调用与 Studio 相同的生产 transport 完成 handshake+snapshot；负向 ad-hoc 仍须在业务 payload 前被拒绝。可重构现有 `RuntimeXPCSmokeClient` 正向路径复用生产 client，禁止再保留一份只在 smoke 能成功的独立实现。

### 白名单

- `ahakeyconfig-mac/Package.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyRuntimeXPCTransport.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyStudioRuntimeFacade.swift`
- Shared 下新增一个 libxpc client 文件
- `Sources/RuntimeXPCServer/SmokeClient/main.swift`（仅为复用生产 client）
- 对应 `Tests/AhaKeyConfigSharedTests/**`、`Tests/RuntimeXPCServerTests/**`
- `scripts/runtime-xpc-signed-smoke.sh` 仅在确有必要时调整验收调用，不得弱化签名
- 本卡、HIL 卡、evidence 与 append-only board

禁止修改 Agent/server 业务实现、peer policy、wire v1.1、planner/配置事务、Studio UI、固件仓、安装器、正式 plist、`/Applications`。

### 完成定义

1. 旧实现上的生产 transport 双进程测试先红，修复后同一测试绿；不能只测内存 fake 或 anonymous NSXPC listener。
2. libxpc client 单测覆盖 handshake→snapshot 会话、单 in-flight 并发串行、server busy 不出现、超时/取消/连接失效、error/missing/oversize payload。
3. `scripts/runtime-xpc-signed-smoke.sh` 正向使用生产 Studio transport通过；ad-hoc 负向仍被拒绝。
4. 定向 facade + XPC server/client 测试；完整 Swift；App+Agent Release；`git diff --check`。
5. 提交后先停手提审。Codex accepted 后才重新构建临时 Studio，要求 UI 从「Runtime 离线」变为 online，系统日志不再出现本卡 undecodable-message 红灯，然后恢复 HIL C1。当前不得执行 apply、断电或断蓝牙。

### [2026-08-27 22:21] Codex：任务卡晋级 ready

- 根因已由真实进程日志和源码双向确认，采用“客户端对齐 server”的唯一生产 transport 方案。
- Cursor ACK 后翻 `active` 并执行；Zcode 固件 1.4 的独立仓并行不受影响。HIL Agent PID 76134 与环境继续保留，不在返工中操作设备。

## 证据

`docs/collab/evidence/HIL-CONFIG-20260827/01-agent-swap-and-c1.md`

## 约束

HIL 临时 label 先保留。未授权前不改产品代码。不刷机、不覆盖 `/Applications`。

### [2026-08-27 22:24] Cursor ACK：按冻结方案施工生产 libxpc client

- ACK 22:21。本卡 `ready` → `active`。只改白名单：Shared libxpc client、Studio 生产 transport、smoke 复用该 transport、对应测试。
- 不改 Agent/server、peer policy、wire v1.1、planner、UI、固件、安装器、正式 plist。不替换 HIL Agent，不 apply，不断电/关蓝牙。
- Zcode 1.4 并行不受影响。

### [2026-08-27 22:32] Cursor：生产 libxpc client 完成，停手提审

- Shared 新增 `AhaKeyRuntimeXPCLibXPCClient`：持久 Mach/`endpoint` 连接、`payload` JSON、单 in-flight、有界排队、超时/取消/失效后不复用连接。
- `AhaKeyStudioRuntimeXPCTransport` 改持该 client；NSXPC `AhaKeyRuntimeXPCConnectionTransport` 仅保留单元 seam。Agent/peer policy/wire/UI 未改。
- `RuntimeXPCSmokeClient` 正向复用 Studio 生产 transport；ad-hoc 仍 exit 3。
- 门禁：client 单测 7/7；定向 facade+XPC 43/43；全量 **489 / 2 skipped / 0 failures**；Release App+Agent；`scripts/runtime-xpc-signed-smoke.sh` 正/负通过；`git diff --check` 干净。
- 未重建临时 Studio、未替换 HIL Agent、未 apply。等 Codex accepted 后再验证 UI online 并续 C1。
