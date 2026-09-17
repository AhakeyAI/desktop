# AhaKey 顺序执行队列

状态：生效  
更新：2026-09-10（DSH 接替 Cursor 未完成及未来客户端执行卡）
调度 owner：Codex

本文件只定义正式任务卡的执行顺序、依赖和用户门禁。产品范围以 `docs/unified-firmware-runtime-implementation-plan.md` 为准；执行细节以对应任务卡为准。

规则：每个写入域默认仅一张卡可处于 `ready/active/review`。Cursor 因额度不足停止承接新卡；其历史 accepted owner 不改写。DSH 接管未完成及未来客户端执行卡。v0.3 C5ABR4 已执行但未通过，当前等待 Codex 形成最小返工卡；旧 R4 USER-GATE 已消费。独立固件域继续由 Zcode 执行 WBS 1.7BR5。刷机、reboot/logout、push、其他覆盖安装和量产切换仍未开放。

| 顺序 | 任务卡 | Owner | 覆盖 WBS | 当前状态 | 晋级条件 |
|---:|---|---|---|---|---|
| 0 | `OPS-CURSOR-001` | Kimi | 临时 Cursor 解阻 | accepted | 已完成 |
| 1 | `OPS-DISPATCH-RELIABILITY` | Kimi；Codex 验证 | Kimi/Codex 自动调度 | accepted | interval 自动 run 已验证；condition 为已知平台限制 |
| 1A | `WBS-5.2-XPC` | Kimi | 5.2 | accepted | `1ac1524` 最终验收通过 |
| 1B | `OPS-CURSOR-REARM` | Cursor；Codex 验证 | Cursor 自动调度 | accepted | 两轮真实 Kimi 事件 wake + 无关写入静默已验证 |
| 1C | `OPS-DSH-REARM` | DSH；Codex 验收 | DSH 自动调度 | blocked / manual handoff | DSH 平台 resume 接口与两轮独立重唤尚未验证；不阻塞人工打开会话后的已授权执行 |
| 2 | `WBS-5.3-C-CURSOR` | Cursor；Kimi/Codex 验证 | 5.3-C | accepted | Codex 11:45 裁决：Kimi 有条件通过 + 测试已提交 + IDE 窗口 allow/manual/offline |
| 3 | `WBS-5.3-ORCHESTRATOR` | Kimi | 5.3 | accepted | Codex 16:24 独立验收 `b49e83e`；不宣布产品 5.3 完成 |
| 4 | `HIL-RUNTIME-1` | Kimi；Cursor 验证 | §15.0-4 | accepted | Codex 12:37：CPU/RSS 180/180 连续 12:05:51–12:35:52；F1/矩阵已在 HOOK-SERVER；F2/F3 归 5.4 |
| 4A | `HIL-RUNTIME-1-HOOK-SERVER` | Kimi；Cursor 验证 | §15.0-4 返工 | accepted | Codex 11:50：User 确认 11:38 bootout；listen+三态独立证据；`fa6c02e` |
| 5 | `WBS-5.4-LIFECYCLE` | Kimi | 5.4 | accepted | Codex 17:02：HEAD `762863d`；独立 pmset Agent 64088 持断言；无 Studio UI；双 socket；定向 21 测通过 |
| 6 | `WBS-0-RISK-CLOSURE` | Kimi | 0.2-0.7 | accepted | Codex 19:01：macOS 证据独立复核；Windows 0xEE / USB 枚举 / SDK Link.ld 延期；不启动 WBS-1 直至固件工作树冻结 |
| 7 | `WBS-1-UNIFIED-FIRMWARE` | Zcode | 1.1-1.7 | active / 1.7BR16 @ `8c362a1` | BR15 rejected；BR16 收完整 OwnedArtifact lifecycle、typed record backup plan、preserved exact proof 与 helper 零手工清理；刷机/HIL/push 未开放 |
| 8 | `WBS-2-PLATFORM-VOICE` | Zcode | 2.1-2.8 / v0.4 | draft | WBS 1 accepted |
| 9 | `WBS-3-LEVER-MACROS` | Zcode | 3.1-3.6 / v0.5 | draft | WBS 2 accepted |
| 10A | `WBS-4-STUDIO-V4` | DSH | 4.1-4.4 / v0.4 | draft | WBS 2 accepted；只开平台/语音 UI slice |
| 10B | `WBS-4-STUDIO-V4` | DSH | 4.5 / v0.5 | draft | WBS 3 accepted；只开拨杆 UI slice |
| 10C | `WBS-4-STUDIO-V4` | DSH | 4.6-4.8 / v1.0 | draft | v0.5 accepted；与 5.10/5.9B 收口 |
| 11 | `WBS-5.5-DEVICE-OWNER` | Kimi | 5.5 | accepted | Codex 19:51：HEAD `ea770d6`；HIL 归 HIL-RUNTIME-2 |
| 11A | `WBS-5.5-HIL-REWORK` | Kimi | 5.5 | accepted | Codex 22:44：`0bab8af` 解析+回连+身份；v0 为 status 字节误读 |
| 12 | `HIL-RUNTIME-2` | Kimi；Cursor 验证 | §15.0-5 | accepted | Codex 23:46：独立 sock/flock/v3 帧；USB 跳过；UUID 末 4 位身份为例外 |
| 13 | `WBS-5.6-CONFIG-TRANSACTIONS` | Kimi | 5.6 | accepted | 静态实现 accepted @ `19eb4dc`；实机门禁独立归 HIL-CONFIG |
| 14 | `WBS-5.7-STUDIO-CLIENT` | Cursor | 5.7 | accepted | Codex 20:03：`488097d`；R6 序列断言与独立门禁通过 |
| 15 | `HIL-CONFIG-TRANSACTIONS` | DSH；Codex 只读验收 | §15.0-6 | blocked / C1 firmware gate | 3/7；0x97 status=3；等统一固件可刷候选 + 刷机 USER-GATE 后重跑 |
| 15A | `HIL-CONFIG-0x99-CAPS14` | Cursor | HIL 阻塞返工 | accepted | Codex 21:47：`3b08d82`；双轴与独立门禁通过 |
| 15B | `HIL-CONFIG-STUDIO-XPC-CLIENT` | Cursor | HIL 阻塞返工 | accepted | Codex 09:50：R2 双轴 0 findings，accepted @ `2403978` |
| 15C | `DEVICE-PERSIST-AND-UPLOAD-UX` | Cursor；固件路由 Zcode/WBS 1.5 | HIL C1 跨端缺口 | accepted / C-3 | C-1/C-2/C-3 accepted @ `3bc52b2`；固件遗留继续由 WBS 1.5 闭环 |
| 15D | `STUDIO-OLED-ENCODE-AND-PARTIAL-APPLY` | Cursor | HIL C1 编辑/受理缺口 | accepted / E-1 | 双轴 0 findings；最终产品 `dccfc39`；HIL-E1 归 v0.3 |
| 15E | `RELEASE-0.2-COMPATIBILITY` | Cursor | v0.2 功能策略 | accepted / C-2 | 双轴验收通过；最终产品 `d9d2cbb` |
| 15F | `WBS-5.9A-BETA-INSTALLER` | Cursor | 5.9A / v0.2 | accepted / R6 | 最终产品 `6649834`；HIL 实包暴露的打包缺陷转 15F1 |
| 15F1 | `HIL-RELEASE-0.2-PACKAGING-REWORK` | Cursor；Codex 验收 | 5.9A-R7 / 6.0A | accepted / R2 | `3b287be`：真实 requirement helper rc0/3 门禁闭环；旧 DMG 永久 nonconforming |
| 15F2 | `HIL-RELEASE-0.2-INSTALLER-RECOVERY-REWORK` | Cursor；Codex 验收 | 5.9A-R8 / 6.0A | accepted / R5 | 最终产品 `5c4f440`；R4 P1 关闭；残留 Fake 默认名即内容 / 双编码器排序 P2；安装重跑仍 USER-GATE |
| 15G | `HIL-RELEASE-0.2` | Cursor 执行；Zcode 只读验证 | 6.0A / v0.2 | accepted / Gate-2 same-session | build 359；KeepAlive/故障回滚/卸载重装全绿；整机重启 POST 仍为独立 USER-GATE |
| 15H | `RUNTIME-NAMING-AND-LEGACY-UI-CLEANUP` | Cursor；Codex 验收 | post-v0.2 / v0.2.1 | accepted / U2 closed | 最终产品 `95b775d`；U3 延后 v1.0/5.9B |
| 15I | `HIL-RELEASE-0.2.1` | Cursor；Codex 验收 | v0.2.1 增量发布 | accepted / Gate-1 R2 | build 362；同 pid 65466 两轮 BLE 1.321s/1.249s；XPC/socket/Hook→灯效全绿 |
| 15I-R1 | `V021-BLE-WAKE-RECOVERY` | Cursor；Codex 验收 | v0.2.1 BLE lifecycle | accepted / R1 product | `88e02aa`；P2 残留不阻断；HIL 归新候选 |
| 15I-R2 | `V021-RUNTIME-SIGPIPE-SURVIVAL` | Cursor；Codex 验收 | v0.2.1 Runtime 稳定性 | accepted / R3 | `1ed560b`；独立 Survival 10×13/13、Hook 4/4、XPC 22/22、BLE 26/26、全量 750/0、双 Release |
| 15J | `RELEASE-DMG-VERIFIER-CLEANUP` | Cursor；Codex 验收 | release tooling hygiene | accepted / product | `0b4b5e1`；失败路径 detach 收口；不再阻断重冻结 |
| 15K | `V03-STUDIO-OLED-LEGACY-COMPATIBILITY` | Cursor；Codex 验收 | v0.3 客户端 OLED C1-C4 | accepted / C4 @ `30cfeb8` | C1–C4 已验收；用户已开启 C5，执行转 15L preflight |
| 15K-P | `V03-C5-RELEASE-FEATURE-POLICY` | Cursor；Codex 验收 | v0.3 C5P 生产图片面发布策略 | accepted / C5PR9 @ `99a5b01` | v0.3 policy、sealed-fact Facade admission、generation-bound Runtime CAS/WAL 与 causal publication ticket 已验收 |
| 15K-B | `V03-C5-FIRST-PAGE-AUTHORITY-BOOTSTRAP` | Cursor；Codex 验收 | v0.3 首次页面 field-baseline CAS | accepted / C5BR3 @ `5d1fe1d` | schema3 Store-owned field CAS、live/scoped/full page-resource contract closure 已验收 |
| 15K-D | `V03-C5-STUDIO-DUAL-SET-PICKER` | Cursor；Codex 验收 | v0.3 密封双套 Studio 选择 | accepted / C5DR1 @ `adfe2a6` | sealed Rhino A/B picker、nil→Rhino saved-B 恢复、单一 transition/builder 已验收 |
| 15K-E | `V03-C5-STUDIO-OVERWRITE-CONFIRMATION` | Cursor；Codex 验收 | v0.3 页面覆盖确认生命周期 | accepted / C5ER1 @ `fe984e8` | exact frozen identity + single-use attempt/revision；历史/迟到/重放结果不再误消费确认 |
| 15K-F | `V03-C5-STUDIO-ACTIVE-SET-EDIT-INTENT` | Cursor；Codex 验收 | v0.3 active-set 用户编辑意图 | accepted / C5F @ `f2b4622` | typed picker intent 进入 frozen mapping；无用户事件不反写，显式 A 仅发 activeSet |
| 15K-G | `V03-C5-STUDIO-PAGE-COMMIT-COORDINATOR` | DSH；Codex 验收 | v0.3 页面两击提交编排/可观测性 | accepted / C5GR8 @ `e5a2f8f` | 双轴 0 findings；init 无副作用、typed trace、跨 coordinator single lease 与 owner lifecycle 闭合 |
| 15K-H | `V03-C5-PAGE-BASE-OVERWRITE-SEMANTIC` | DSH；Codex 验收 | v0.3 schema=3 页面覆盖语义 | accepted / C5HR1 @ `85e193e` | overwriteSemantic exact confirmation、typed rejection、R5 0x97 与 key/light schema3 矩阵闭合 |
| 15K-I | `V03-C5-ACTIVE-SET-READBACK-DIAGNOSTICS` | DSH；Zcode 只读核对；Codex 验收 | v0.3 active-set 设备事实 | accepted / C5IR8 + C5IR8R1 @ `5963fcd` | deep-module audit、48项机器交叉、typed delimiter 与全门禁已验收 |
| 15K-J | `V03-CODEX-APPROVAL-POLICY-COMPATIBILITY` | DSH；Codex 验收 | 5.3-C / v0.3 线上兼容 | accepted / C5JR2 @ `53c2220` | 用户追认；typed locator、namespace/Unicode、两 Hook 行为门与独立验证通过 |
| 15L | `HIL-V03-STUDIO-OLED-COMPATIBILITY` | DSH；Zcode 只读验证；Codex 验收 | v0.3 OLED C5 HIL | blocked / R7 USER-GATE not opened | 15K-J 已 accepted；下一步仅可另请纯只读 R7 gate，旧授权不可复用 |
| 16 | `WBS-5.8-PURE-HARDWARE` | DSH | 5.8 / v0.4 | draft | WBS 2 + 4.3 accepted；不阻塞 v0.2/v0.3 |
| 17 | `WBS-5.10-WINDOWS-SEAM` | DSH | 5.10 + 4.7 / v1.0 | draft | v0.5、5.9A accepted；先冻结 Windows seam |
| 18 | `WBS-5.9-INSTALL-MIGRATION` | DSH | 5.9B / v1.0 | draft / USER-GATE | 5.8、4.8、5.9A、5.10 accepted；完整权限迁移窗口 |
| 19 | `WBS-5A-SESSION-ROUTING` | Zcode | 5A.1-5A.11 / v1.1 | draft | v1.0 / 5.9B accepted；不反向阻塞基础发布 |
| 19A | `HIL-RELEASE-0.3` | DSH；Zcode 验证 | 6.0B / v0.3 | draft / USER-GATE | 最终 v0.2.1 + 15K + 15L accepted；客户端签名/安装窗口，不刷固件 |
| 19B | `HIL-RELEASE-0.4` | DSH；Zcode 验证 | 6.0B / v0.4 | draft / USER-GATE | WBS 2 + 4.1-4.4 + 5.8 accepted |
| 19C | `HIL-RELEASE-0.5` | DSH；Zcode 验证 | 6.0B / v0.5 | draft / USER-GATE | WBS 3 + 4.5 accepted |
| 20 | `WBS-6-QUALIFICATION` | Zcode；DSH 客户端证据协作；Codex 验收 | 6.1-6.4 / v1.0 | draft / USER-GATE | WBS 1-5.10/5.9B accepted |
| 21 | `WBS-6-BETA-RELEASE` | DSH；Zcode 验证；Codex 验收 | 6.5-6.7 / v1.0 | draft / USER-GATE | v1.0 的 6.1-6.4 accepted；不重复承担 v0.2 Beta |
| 22 | `HIL-RELEASE-1.1` | DSH；Zcode 验证；Codex 验收 | 6.4A / v1.1 | draft / USER-GATE | WBS 5A accepted；不反向阻塞 v1.0 |

队列不是一般并行许可。客户端当前没有获准的产品施工或 HIL 重跑：C5ABR4 已失败并回滚，下一步必须先由 Codex 基于 `27-c5abr4-gitee-rhino-ab-switch.md` 发最小产品返工卡，owner 为 DSH；旧授权不可复用。DSH 自动 rearm 在 `OPS-DSH-REARM` accepted 前也不得声称成立。固件当前授权切片为 1.7BR5；clean commit `9fe4d5d` 不等于 accepted，必须正式提审并由 Codex 审查。1.7B host combined image 仍不代表可刷镜像；刷机、HIL、签名、正式发布和 push 继续关闭。

发布列车：`v0.2/v0.2.1 = 15E → 15F → 15G → 15H → 15I`；`v0.3 = 15K(C1→C2→C3→C4) → 15L(C5) → 19A`（客户端页面级 OLED，独立于固件）；`v0.4 = WBS 1 → WBS 2 + WBS 4.1-4.4 + 5.8 → 19B`（统一固件与平台快捷键）；`v0.5 = WBS 3 + WBS 4.5 → 19C`；`v1.0 = WBS 4.6-4.8 + 5.10 → 5.9B → WBS 6`；`v1.1 = WBS 5A → 22`。

并行例外：用户于 2026-08-23 19:20 明确要求提前启动下一张 Kimi 卡。Codex 证明 WBS-0 静态预研只写 `docs/research/wbs-0-static-preflight.md`、基线文档指定追加段、本卡与 board，不触碰 5.3-C Hook 文件；因此允许该静态子阶段与 5.3-C 并行。WBS-0 实机部分、WBS-1 及正式队列依赖不随之放开。
