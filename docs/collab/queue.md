# AhaKey 顺序执行队列

状态：生效  
更新：2026-08-25  
调度 owner：Codex

本文件只定义正式任务卡的执行顺序、依赖和用户门禁。产品范围以 `docs/unified-firmware-runtime-implementation-plan.md` 为准；执行细节以对应任务卡为准。

规则：任一时刻默认仅一张卡可处于 `ready/active/review`。Codex 接受当前卡后，在同一轮把下一张依赖已满足且不含 `USER-GATE` 的卡晋级为 `ready`；遇到 `USER-GATE` 时暂停并向用户确认。

| 顺序 | 任务卡 | Owner | 覆盖 WBS | 当前状态 | 晋级条件 |
|---:|---|---|---|---|---|
| 0 | `OPS-CURSOR-001` | Kimi | 临时 Cursor 解阻 | accepted | 已完成 |
| 1 | `OPS-DISPATCH-RELIABILITY` | Kimi；Codex 验证 | Kimi/Codex 自动调度 | accepted | interval 自动 run 已验证；condition 为已知平台限制 |
| 1A | `WBS-5.2-XPC` | Kimi | 5.2 | accepted | `1ac1524` 最终验收通过 |
| 1B | `OPS-CURSOR-REARM` | Cursor；Codex 验证 | Cursor 自动调度 | accepted | 两轮真实 Kimi 事件 wake + 无关写入静默已验证 |
| 2 | `WBS-5.3-C-CURSOR` | Cursor；Kimi/Codex 验证 | 5.3-C | accepted | Codex 11:45 裁决：Kimi 有条件通过 + 测试已提交 + IDE 窗口 allow/manual/offline |
| 3 | `WBS-5.3-ORCHESTRATOR` | Kimi | 5.3 | accepted | Codex 16:24 独立验收 `b49e83e`；不宣布产品 5.3 完成 |
| 4 | `HIL-RUNTIME-1` | Kimi；Cursor 验证 | §15.0-4 | accepted | Codex 12:37：CPU/RSS 180/180 连续 12:05:51–12:35:52；F1/矩阵已在 HOOK-SERVER；F2/F3 归 5.4 |
| 4A | `HIL-RUNTIME-1-HOOK-SERVER` | Kimi；Cursor 验证 | §15.0-4 返工 | accepted | Codex 11:50：User 确认 11:38 bootout；listen+三态独立证据；`fa6c02e` |
| 5 | `WBS-5.4-LIFECYCLE` | Kimi | 5.4 | accepted | Codex 17:02：HEAD `762863d`；独立 pmset Agent 64088 持断言；无 Studio UI；双 socket；定向 21 测通过 |
| 6 | `WBS-0-RISK-CLOSURE` | Kimi | 0.2-0.7 | accepted | Codex 19:01：macOS 证据独立复核；Windows 0xEE / USB 枚举 / SDK Link.ld 延期；不启动 WBS-1 直至固件工作树冻结 |
| 7 | `WBS-1-UNIFIED-FIRMWARE` | Cursor | 1.1-1.7 | paused / 1.4 | HIL 真机窗口优先；固件仓 clean @ `9135183`，HIL 收口后恢复 |
| 8 | `WBS-2-PLATFORM-VOICE` | Kimi | 2.1-2.8 | draft | WBS 1 accepted |
| 9 | `WBS-3-LEVER-MACROS` | Kimi | 3.1-3.6 | draft | WBS 2 accepted |
| 10 | `WBS-4-STUDIO-V4` | Cursor | 4.1-4.8 | draft | WBS 3 accepted |
| 11 | `WBS-5.5-DEVICE-OWNER` | Kimi | 5.5 | accepted | Codex 19:51：HEAD `ea770d6`；HIL 归 HIL-RUNTIME-2 |
| 11A | `WBS-5.5-HIL-REWORK` | Kimi | 5.5 | accepted | Codex 22:44：`0bab8af` 解析+回连+身份；v0 为 status 字节误读 |
| 12 | `HIL-RUNTIME-2` | Kimi；Cursor 验证 | §15.0-5 | accepted | Codex 23:46：独立 sock/flock/v3 帧；USB 跳过；UUID 末 4 位身份为例外 |
| 13 | `WBS-5.6-CONFIG-TRANSACTIONS` | Kimi | 5.6 | accepted | 静态实现 accepted @ `19eb4dc`；实机门禁独立归 HIL-CONFIG |
| 14 | `WBS-5.7-STUDIO-CLIENT` | Cursor | 5.7 | accepted | Codex 20:03：`488097d`；R6 序列断言与独立门禁通过 |
| 15 | `HIL-CONFIG-TRANSACTIONS` | Cursor；Codex 只读验收 | §15.0-6 | active / 恢复 C1 | CAPS14 accepted；重新部署临时 HIL Agent、复核协商后续 C1–C6 |
| 15A | `HIL-CONFIG-0x99-CAPS14` | Cursor | HIL 阻塞返工 | accepted | Codex 21:47：`3b08d82`；双轴与独立门禁通过 |
| 16 | `WBS-5.8-PURE-HARDWARE` | Cursor | 5.8 | draft | 5.4 + 4.3 + 5.7 accepted |
| 17 | `WBS-5.9-INSTALL-MIGRATION` | Cursor | 5.9 | draft / USER-GATE | 5.3-5.8 accepted、签名安装窗口 |
| 18 | `WBS-5.10-WINDOWS-SEAM` | Cursor | 5.10 + 4.7 | draft | 5.9 accepted |
| 19 | `WBS-5A-SESSION-ROUTING` | Kimi | 5A.1-5A.11 | draft | 基础版 5.9 accepted；不反向阻塞基础发布 |
| 20 | `WBS-6-QUALIFICATION` | Kimi；Cursor 验证 | 6.1-6.4/6.4A | draft / USER-GATE | WBS 1-5 与适用 5A accepted |
| 21 | `WBS-6-BETA-RELEASE` | Cursor；Kimi 验证 | 6.5-6.7 | draft / USER-GATE | 6.1-6.4 accepted、用户批准 Beta/灰度/发布 |

队列不是一般并行许可。调度 OPS、WBS 5.2、`WBS-5.3-C-CURSOR`、`WBS-5.3-ORCHESTRATOR`、`HIL-RUNTIME-1-HOOK-SERVER`、`HIL-RUNTIME-1`、`WBS-5.4-LIFECYCLE`、`WBS-0-RISK-CLOSURE`、`WBS-5.5-DEVICE-OWNER`、`WBS-5.5-HIL-REWORK`、`HIL-RUNTIME-2`、`WBS-5.6-CONFIG-TRANSACTIONS`、`WBS-5.7-STUDIO-CLIENT` 与 `HIL-CONFIG-0x99-CAPS14` 已 accepted（5.6 有效基线 `19eb4dc`；5.7 有效基线 `488097d`；CAPS14 `3b08d82`）。当前 HIL-CONFIG 恢复 active，固件 WBS-1.4 继续暂停；先续 C1–C6。刷机、远端 push 和量产切换仍需 USER-GATE。

并行例外：用户于 2026-08-23 19:20 明确要求提前启动下一张 Kimi 卡。Codex 证明 WBS-0 静态预研只写 `docs/research/wbs-0-static-preflight.md`、基线文档指定追加段、本卡与 board，不触碰 5.3-C Hook 文件；因此允许该静态子阶段与 5.3-C 并行。WBS-0 实机部分、WBS-1 及正式队列依赖不随之放开。
