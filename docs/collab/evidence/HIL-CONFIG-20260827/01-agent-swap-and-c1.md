# HIL-CONFIG 2026-08-27 — CAPS14 Agent 替换与 C1 续测

时间：2026-08-27 21:51–22:14 +08

## 临时 HIL Agent 替换（未覆盖正式包/plist）

- 产品基线：`3b08d82`（HEAD 含 collab `1bfe579`，为其祖先）
- 旧进程：HIL PID **10092** sha `e7c623f5…`；期间正式 KeepAlive 任务曾复活 PID **27278**（`/Applications/.../ahakeyconfig-agent`）
- `launchctl bootout` 正式 `lab.jawa.ahakeyconfig.agent`（**plist 文件未改**，sha 仍 `61da75e0…`）
- `bootout` 临时 HIL → 复制 Release agent 到 `/tmp/ahakey-hil-bin/ahakeyconfig-agent` → bootstrap+kickstart
- 新进程 PID **76134**，sha `392d5e0648e7a54a8eed3f33140cf8c24a52cf345e1988d3972a233e24ff44ca`
- `/Applications/AhaKey Studio.app` mtime 仍 2026-08-21 14:58
- 原始记录：`raw/agent-swap-caps14.txt`

## 0x99 重新协商

- 无需用户按键：新 Agent 立即 `已连接: AhaKey X1`
- 原始应答仍为 compact 14B：`AA BB 99 00 03 04 02 04 3F 00 C8 00 14 01 14 01 1C 01 CC DD`
- `← 0x99 能力帧：protocol v3，mode=current`
- `← 0x99 compact factory：primary 0..<276，factory reserved 276，reclaim 276..<284`
- `current 协议协商完成，开始状态轮询`
- 摘录：`raw/caps14-renegotiate.txt`

## C1 apply（未下发配置包）

- 仓库 5.7 Studio 打到 `/tmp/ahakey-hil-studio/AhaKey Studio.app`（`INSTALL_TO_APPLICATIONS=0`），Developer ID 签名，identifier `lab.jawa.ahakeyconfig`
- 未覆盖 `/Applications`；未在 UI 安装正式 Agent
- libxpc `RuntimeXPCSmokeClient` 对 `lab.jawa.ahakeyconfig.runtime` 正向 handshake+snapshot **exit 0**
- Studio 主界面显示 **「Runtime 离线」**，无法点「写入键盘」走 facade.apply
- 原因（不在本卡修）：Studio 生产传输是 `NSXPCConnection` + `AhaKeyRuntimeXPCServiceProtocol`；Agent 生产 server 是 `AhaKeyRuntimeXPCLibXPCServer`（libxpc dictionary `payload` JSON）。WBS-5.7 集成测试明确省略 MachService/NSXPC 层，改由 5.2 smoke（libxpc client）覆盖。双进程 GUI 路径因此连不上已协商 current 的 Runtime。
- 草稿返工卡：`HIL-CONFIG-STUDIO-XPC-CLIENT`

## 环境保留

- HIL Agent PID 76134 继续跑；正式 launchd 任务保持未加载
- 不断电、未关蓝牙、未刷机、未改产品代码、未写固件仓
