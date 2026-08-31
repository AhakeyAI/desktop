# AhaKey 顺序执行队列

状态：生效  
更新：2026-08-29（发布列车拆分）
调度 owner：Codex

本文件只定义正式任务卡的执行顺序、依赖和用户门禁。产品范围以 `docs/unified-firmware-runtime-implementation-plan.md` 为准；执行细节以对应任务卡为准。

规则：每个写入域默认仅一张卡可处于 `ready/active/review`。当前 Cursor 唯一 active 卡是 WBS 5.9A 未签名安装链；Zcode 只写独立固件仓 WBS 1.5 R20。实际签名、安装、HIL 和刷机均未开放。Codex 接受当前卡后，在同一轮检查同通道下一张依赖；遇到 `USER-GATE` 时暂停并向用户确认。

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
| 7 | `WBS-1-UNIFIED-FIRMWARE` | Zcode | 1.1-1.7 | ready / 1.5 slice 2 implementation B1R4 | B1R3 双入口回归与完整 legacy pin 保留；删除重复门禁块；checker 负向须断言 ABI drift；B2 冻结 |
| 8 | `WBS-2-PLATFORM-VOICE` | Zcode | 2.1-2.8 / v0.4 | draft | WBS 1 accepted |
| 9 | `WBS-3-LEVER-MACROS` | Zcode | 3.1-3.6 / v0.5 | draft | WBS 2 accepted |
| 10A | `WBS-4-STUDIO-V4` | Cursor | 4.1-4.4 / v0.4 | draft | WBS 2 accepted；只开平台/语音 UI slice |
| 10B | `WBS-4-STUDIO-V4` | Cursor | 4.5 / v0.5 | draft | WBS 3 accepted；只开拨杆 UI slice |
| 10C | `WBS-4-STUDIO-V4` | Cursor | 4.6-4.8 / v1.0 | draft | v0.5 accepted；与 5.10/5.9B 收口 |
| 11 | `WBS-5.5-DEVICE-OWNER` | Kimi | 5.5 | accepted | Codex 19:51：HEAD `ea770d6`；HIL 归 HIL-RUNTIME-2 |
| 11A | `WBS-5.5-HIL-REWORK` | Kimi | 5.5 | accepted | Codex 22:44：`0bab8af` 解析+回连+身份；v0 为 status 字节误读 |
| 12 | `HIL-RUNTIME-2` | Kimi；Cursor 验证 | §15.0-5 | accepted | Codex 23:46：独立 sock/flock/v3 帧；USB 跳过；UUID 末 4 位身份为例外 |
| 13 | `WBS-5.6-CONFIG-TRANSACTIONS` | Kimi | 5.6 | accepted | 静态实现 accepted @ `19eb4dc`；实机门禁独立归 HIL-CONFIG |
| 14 | `WBS-5.7-STUDIO-CLIENT` | Cursor | 5.7 | accepted | Codex 20:03：`488097d`；R6 序列断言与独立门禁通过 |
| 15 | `HIL-CONFIG-TRANSACTIONS` | Cursor；Codex 只读验收 | §15.0-6 | blocked / C1 firmware gate | 3/7；0x97 status=3；等 WBS 1.5 + 刷机 USER-GATE 后重跑 |
| 15A | `HIL-CONFIG-0x99-CAPS14` | Cursor | HIL 阻塞返工 | accepted | Codex 21:47：`3b08d82`；双轴与独立门禁通过 |
| 15B | `HIL-CONFIG-STUDIO-XPC-CLIENT` | Cursor | HIL 阻塞返工 | accepted | Codex 09:50：R2 双轴 0 findings，accepted @ `2403978` |
| 15C | `DEVICE-PERSIST-AND-UPLOAD-UX` | Cursor；固件路由 Zcode/WBS 1.5 | HIL C1 跨端缺口 | accepted / C-3 | C-1/C-2/C-3 accepted @ `3bc52b2`；固件遗留继续由 WBS 1.5 闭环 |
| 15D | `STUDIO-OLED-ENCODE-AND-PARTIAL-APPLY` | Cursor | HIL C1 编辑/受理缺口 | accepted / E-1 | 双轴 0 findings；最终产品 `dccfc39`；HIL-E1 归 v0.3 |
| 15E | `RELEASE-0.2-COMPATIBILITY` | Cursor | v0.2 功能策略 | accepted / C-2 | 双轴验收通过；最终产品 `d9d2cbb` |
| 15F | `WBS-5.9A-BETA-INSTALLER` | Cursor | 5.9A / v0.2 | accepted / R6 | 最终产品 `6649834`；HIL 实包暴露的打包缺陷转 15F1 |
| 15F1 | `HIL-RELEASE-0.2-PACKAGING-REWORK` | Cursor；Codex 验收 | 5.9A-R7 / 6.0A | accepted / R2 | `3b287be`：真实 requirement helper rc0/3 门禁闭环；旧 DMG 永久 nonconforming |
| 15F2 | `HIL-RELEASE-0.2-INSTALLER-RECOVERY-REWORK` | Cursor；Codex 验收 | 5.9A-R8 / 6.0A | ready / R4 | R3 receipt/HIL 主体保留；收口 System→Host 单 identity 和强 App tree digest/真 fixture wrong-tree；安装重跑仍禁止 |
| 15G | `HIL-RELEASE-0.2` | Cursor 执行；Zcode 只读验证 | 6.0A / v0.2 | blocked / 15F2 R2 | 0.2 official Runtime 已恢复且 XPC 通过；安装器仍失败，Studio/BLE smoke 未做 |
| 16 | `WBS-5.8-PURE-HARDWARE` | Cursor | 5.8 / v0.4 | draft | WBS 2 + 4.3 accepted；不阻塞 v0.2/v0.3 |
| 17 | `WBS-5.10-WINDOWS-SEAM` | Cursor | 5.10 + 4.7 / v1.0 | draft | v0.5、5.9A accepted；先冻结 Windows seam |
| 18 | `WBS-5.9-INSTALL-MIGRATION` | Cursor | 5.9B / v1.0 | draft / USER-GATE | 5.8、4.8、5.9A、5.10 accepted；完整权限迁移窗口 |
| 19 | `WBS-5A-SESSION-ROUTING` | Zcode | 5A.1-5A.11 / v1.1 | draft | v1.0 / 5.9B accepted；不反向阻塞基础发布 |
| 19A | `HIL-RELEASE-0.3` | Cursor；Zcode 验证 | 6.0B / v0.3 | draft / USER-GATE | WBS 1 + OLED E 系列 accepted；刷机/真机窗口 |
| 19B | `HIL-RELEASE-0.4` | Cursor；Zcode 验证 | 6.0B / v0.4 | draft / USER-GATE | WBS 2 + 4.1-4.4 + 5.8 accepted |
| 19C | `HIL-RELEASE-0.5` | Cursor；Zcode 验证 | 6.0B / v0.5 | draft / USER-GATE | WBS 3 + 4.5 accepted |
| 20 | `WBS-6-QUALIFICATION` | Zcode；Cursor 验证 | 6.1-6.4 / v1.0 | draft / USER-GATE | WBS 1-5.10/5.9B accepted |
| 21 | `WBS-6-BETA-RELEASE` | Cursor；Zcode 验证 | 6.5-6.7 / v1.0 | draft / USER-GATE | v1.0 的 6.1-6.4 accepted；不重复承担 v0.2 Beta |
| 22 | `HIL-RELEASE-1.1` | Cursor；Zcode 验证 | 6.4A / v1.1 | draft / USER-GATE | WBS 5A accepted；不反向阻塞 v1.0 |

队列不是一般并行许可。Cursor 当前唯一 active 卡是 `WBS-5.9A-BETA-INSTALLER`，只开发/验证未签名安装链；实际签名、安装、登录项修改与 v0.2 HIL 均未开放。Zcode 继续独立固件仓 WBS 1.5 R20，不与客户端安装链混提。OLED HIL-E1 归 v0.3，不在本轮启动。HIL-CONFIG 继续 blocked，待 WBS 1.5 + 刷机门禁后归 v0.3；WBS 2/3/5.8/5A/6 不能反向阻塞 v0.2。刷机、安装、远端 push 和量产切换仍需 USER-GATE。

发布列车：`v0.2 = 15E → 15F → 15G`；`v0.3 = WBS 1.5-1.7 + OLED E 系列 + HIL-CONFIG → 19A`；`v0.4 = WBS 2 + WBS 4.1-4.4 + 5.8 → 19B`；`v0.5 = WBS 3 + WBS 4.5 → 19C`；`v1.0 = WBS 4.6-4.8 + 5.10 → 5.9B → WBS 6`；`v1.1 = WBS 5A → 22`。

并行例外：用户于 2026-08-23 19:20 明确要求提前启动下一张 Kimi 卡。Codex 证明 WBS-0 静态预研只写 `docs/research/wbs-0-static-preflight.md`、基线文档指定追加段、本卡与 board，不触碰 5.3-C Hook 文件；因此允许该静态子阶段与 5.3-C 并行。WBS-0 实机部分、WBS-1 及正式队列依赖不随之放开。
