# 任务卡 HIL-CONFIG-STUDIO-XPC-CLIENT：Studio 生产传输连不上 libxpc Runtime

计划/WBS：HIL-CONFIG 阻塞返工  
状态：`draft`（等 Codex 裁决是否晋级；HIL C1–C6 暂停，环境保留）  
执行 owner：待 Codex 指定（建议 Cursor）  
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

## 证据

`docs/collab/evidence/HIL-CONFIG-20260827/01-agent-swap-and-c1.md`

## 约束

HIL 临时 label 先保留。未授权前不改产品代码。不刷机、不覆盖 `/Applications`。
