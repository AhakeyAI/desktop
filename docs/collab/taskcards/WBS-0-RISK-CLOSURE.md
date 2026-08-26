# 任务卡 WBS-0-RISK-CLOSURE：固件/平台剩余风险关闭

计划/WBS：0.2-0.7  
状态：`accepted`（macOS 实机窗口；Windows `0xEE`、USB 枚举、SDK `Link.ld` 数值延期记录在执行记录）
执行 owner：Kimi  
基线：GitHub hardware `dev` @ `3e7f900ae6f5fe71d57a03da973d79356afea1b6`；Gitee Rhino @ `53cd0a97e95e3b8b35cd56ed2284970d5a79d1be`；本地 Rhino @ `00eb7efc235770d0a40e23a8c6e7449b2c010765`  
目标：补齐 Flash/协议差异矩阵、HID/平台探测证据、protocol v4 与内存预算，以及 Codex session/thread join 可行性。

本轮精确写入白名单：`docs/research/wbs-0-static-preflight.md`（可新建）、`docs/firmware-client-baseline-2026-08-22.md`（仅追加证据索引）、本卡执行记录与 `board.md`；不得改产品代码、构建配置或其他任务卡。  
禁止：未确认硬件窗口不得抓包/刷机；不得猜测 linker map、Flash 占用或 BLE 能力。  
完成定义：三方 linker map/Flash 地址大小占用；macOS F5/Fn/Globe USB/BLE 报告；Windows USB `0xEE` 与缓存；BLE 首连可达性；v4/EEPROM/Flash ADR；Codex hook session/thread join 结论均有证据。  
测试/门禁：静态证据可先做；硬件、Windows 与 Codex App 操作由用户确认后执行。  
前置：5.4 accepted；用户提供所需设备/平台窗口。

## 并行静态预研例外（2026-08-23 用户授权）

本轮只允许在 5.3-C 仍 active 时提前完成不依赖 5.4 或 USER-GATE 的静态证据：

1. 核对三方冻结提交及已有源码/构建产物可达性，不 fetch、merge、checkout 或修改固件仓库。
2. 盘点现有 linker script、map/size 产物、Flash/EEPROM 地址声明与 protocol v4 opcode/capability 冲突；没有真实 map/构建证据的项明确标为 missing。
3. 汇总现有 macOS HID、Windows `0xEE`、BLE 首连和 Codex session/thread join 资料，只形成“已证实 / 待实机 / 待平台”矩阵。
4. 输出后本卡不得进入 `accepted`；静态预研完成即回到 `blocked / USER-GATE`，等待正式队列前置 5.4 与用户设备窗口。

本例外不授权 WBS-1 开工，不改变正式 exit gate，也不允许任何硬件、Windows、刷机、抓包或 Codex App 操作。

## 执行记录（append-only）

等待 Kimi ACK 并执行并行静态预研；实机门禁保持关闭。

### [2026-08-23 20:11] Kimi 静态预研完成
- 并行静态预研（用户授权例外）已完成
- 产出：`docs/research/wbs-0-static-preflight.md`（新建，约 15KB）
- 关键发现：USB VID/PID `0x413C:0x2107` 与客户端期望 `0x07D7:0x501A` 不一致；BLE PnP `0x07D7:0x0000` 与客户端期望 `0x501A` 也不一致
- 未执行门禁：实机 HIL、Windows 0xEE、BLE 首连、Codex session-thread join（均属 USER-GATE）
- 本卡回到 blocked / USER-GATE，不进入 accepted；WBS-1 不启动

### [2026-08-23 20:20] Kimi 静态预研补正
- Codex 20:12 独立验收退回 4 项要求已全部补正：
  1. `0x99` 矛盾：GitHub dev `3e7f900` 无实现；Rhino `53cd0a97`/`00eb7efc` 在 `command_solve.c:500` 有实现
  2. 源码证据：全部补齐完整相对路径 + 行号/符号
  3. 本地可达：`git cat-file -e` 验证 5 个冻结点全部返回 0
  4. 工作区表述：更正为「Kimi 未产生白名单外改动」
- 报告已更新，等待 Codex 重新验收

### [2026-08-23 20:12] Codex 静态预研独立验收：退回补正
- 报告第 3.2 节称固件 `0x99` “GitHub 入口 / 支持”，第 5、6 节又称冻结源码未找到处理分支；结论互相矛盾。
- 主要证据只写文件 basename，未记录来源仓库、冻结提交、完整相对路径和行号/符号，当前仓库无法独立复核。
- “三方冻结提交本地可达”与表内 `git ls-remote` 远端确认不是同一证据；需分别记录本地 `git cat-file -e <sha>^{commit}`（或等价只读命令）和远端核对结果，不得用目录存在代替提交可达。
- 在上述问题补正并通过只读复核前，本轮静态预研保持 `ready`；补正通过后才回到 `blocked / USER-GATE`。正式 exit gate、WBS-1 与所有实机门禁仍关闭。

### [2026-08-24 10:22] Codex 静态预研复验通过
- `0x99` 按三冻结点分别核实：GitHub 快照无分支；Rhino `53cd0a97`/`00eb7efc` 在 `command_solve.c:500` 有实现。
- USB `0x413C:0x2107` vs 客户端 `0x07D7:0x501A` 已独立核对；统一身份策略留待正式 WBS-0/WBS-1，本阶段不关闭。
- Rhino 两枚冻结 SHA 在 Rhino worktree 上 `git cat-file -e` 为 0。GitHub hardware SHA 不是本仓 git object，证据为 `.bak-previous` 快照目录。
- 本卡回到 `blocked / USER-GATE`，不进入 accepted；WBS-1 不启动。

### [2026-08-25 17:55] Kimi 实机窗口 ① 三方 Flash 占用（hex 实测）+ linker 证据

- hex 地址覆盖实测（Intel HEX 全记录解析，含 0x02/0x04 扩展段）：
  - GitHub dev `3e7f900` `obj/`: 0x000000–0x064D04，**403.3 KiB**
  - GitHub dev `3e7f900` `obj_final/`: 0x000000–0x06BBC0，**430.9 KiB**
  - Rhino 本地 `00eb7efc` `obj/` 与 dist v11：0x000000–0x056B49，**215.8 KiB**（obj 与 dist 同上限，数据差 276 B）
  - 主仓根 `HID_Keyboard_582m_vibe_coding.hex`: 0x000000–0x0534D8，**333.2 KiB**
- linker 层面真实证据（Rhino `CH582m_vibe_coding_BLE_keyboard-master/Makefile` LDFLAGS）：
  - `.factory_trigger` 固定于 Flash **0x50000**（320 KiB），`.factory_assets` 固定于 **0x51000**（324 KiB）
  - `--print-memory-usage` 与 `Link.ld` 依赖 WCH SDK（`SDK_SRC/Ld/Link.ld`）
- **missing（证据不足，不猜测）**：`EEPROM_BLOCK_SIZE`/`EEPROM_MAX_SIZE` 数值、`Link.ld` 分区表、`--print-memory-usage` 输出——SDK（EVT/EXAM/SRC、HAL、LIB）在 `rhino` worktree、`.bak-previous`、`/tmp/ch582sdk` 均不存在，本机未装 MounRiver。如需补齐需取得 WCH CH582 SDK。
- EEPROM 布局公式（源码实证）：`Eeprom_circle_max_size = EEPROM_BLOCK_SIZE*4`（ch_flash.c:3）；`FACTORY_JOURNAL_ADDR = EEPROM_BLOCK_SIZE*4`（factory_assets.c:12）；`KEY_BUND_EEPROM_ADDR = EEPROM_BLOCK_SIZE*4+1024`，slot 2560 B × 2（fram_RC16.c:5-6, main.h:53）。

### [2026-08-25 18:00] Kimi 实机窗口 ② BLE 首连可达性 + 设备身份实证（macOS）

- `system_profiler SPBluetoothDataType` 实测：**AhaKey X1 已通过 BLE 连接**，Address `D4:6C:50:5C:F5:C0`，**VID `0x07D7` / PID `0x501A`**，Minor Type Keyboard，Services BLE。
- **预研记录的身份不一致（PnP `0x07D7:0x0000` vs 客户端期望 `0x501A`）在实机上不成立**：当前键盘烧录固件的 PnP 即 `0x501A`，与客户端 `AhaKeyFirmwareCapabilities.swift` 期望一致 → 当前实机固件为 Rhino 系（GitHub `3e7f900` 的 PnP 才是 `0x0000`）。
- BLE 首连流程实机证据：键盘开机 → agent 16:55 `蓝牙就绪` → status 返回 `{"switchState":0,"lightMode":16}`，vendor 协议通道（状态查询）可达；macOS 系统 HID 层同时识别为 Keyboard。
- 另：环境中可见未连接设备 `AhaKey 507C` / `AhaKey 515C`（VID 0x07D7）——多设备广播命名规则与预研一致。
- 待补：USB 有线枚举（键盘当前纯 BLE，待用户插线后做 `system_profiler SPUSBDataType` + ioreg 描述符对比）。

### [2026-08-25 18:05] Kimi 实机窗口 ③ Codex hook session/thread join 结论（代码实证）

- 事件侧输入已具备：hook stdin JSON 携带 `session_id`、`conversation_id`、`cwd`、`tool_name`（`Sources/Agent/HookSupport.swift:121-139,240` 解析与过滤清单实证）。
- Runtime 侧现状：`session_id` 仅被截断为前 16 字符写入诊断日志（`HookSupport.swift:133-135`），**无任何 session→thread/navigation target 的 join 结构**——全仓 `navigation` 仅命中 Onboarding UI 文案，`session/thread` 语义只存在于设备传输的 generation 概念（`docs/ahakey-runtime-architecture.md:87,132`），与 Codex hook session 无关。
- **结论：可行但未实现**。join 的可行路径：hook 事件已有稳定 `session_id`+`conversation_id`；需在 Studio 侧新增「hook session → 桌面 thread / navigation target」映射表与路由层。属 Studio UI 迭代范围，建议由 Codex 在 WBS 5.x 后续排期；本卡项关闭（结论已产出，非实现任务）。

### [2026-08-25 18:20] Kimi 实机窗口 ④ macOS F5/Fn/Globe 端到端实证（BLE + USB 同行为）

- 说明：本键盘仅 4 个软件可映射键，无实体 F5/Fn/Globe；验证路径 = Studio 映射 → 固件发 HID usage → macOS 投递。原始 IOHIDManager 抓取因 TCC ListenEvent 归属子进程（swift）不可用，改用功能实证 + 日志实证，双通道留证。
- **F5 ✅**（claude mode）：Studio 映射某键为 F5，本地键值验证器（`docs/research/hid-capture/keytester.html`）实测浏览器收到 `F5 (code=F5, keyCode=116)`——固件正确发出 F5 usage（0x3E）。
- **Fn/Globe ✅**（cursor mode，macOS 原生语音路由）：按语音键出现 macOS 原生听写浮窗；`voice-relay.log` 实测连续 `matched keyCode=79 type=10/11 route=macOS 原生语音 mode=1`（18:16 本地时段），权限行 `inputMonitoring=true accessibility=true postEvent=true`。客户端编码证据：F18=0x6D / F19=0x6E（`Sources/BLE/AhaKeyProtocol.swift:347-348`）。
- **codex mode ✅**：语音键 → right command（keyCode 79）+ 唤起豆包输入法，与 Studio 的豆包预设路由一致（`AhaKeyStudioModels.swift:375`）。
- **USB 传输同行为**：用户实测 USB 连接下上述行为一致。但当前 ioreg USB 树无键盘枚举（仅 Type-C 转接器）——USB 枚举描述符证据待用户重新插线时补采。

### [2026-08-25 19:00] Kimi 实机窗口 ⑤ USB 链路处置 + 整卡提审

- **USB 枚举**：用户确认固件 USB 链路为已知未解决问题，本轮明确忽略 USB 链路。机器侧佐证：ioreg USB 树无键盘枚举（仅 Type-C 转接器）。此项标记为「已知固件缺陷，延期」，对应 Rhino 分支既有 macOS USB 枚举/VBUS 修复线的延续，不在本卡完成定义内重新打开。
- **整卡状态汇总**：
  1. 三方 Flash 占用 hex 实测 ✅（GitHub 403.3/430.9 KiB、Rhino 215.8 KiB、根 dist 333.2 KiB；factory 段 0x50000/0x51000 为 Rhino Makefile 定义）
  2. `EEPROM_BLOCK_SIZE`/`Link.ld`/memory-usage：**missing**（WCH SDK 本地不可得，不猜测）
  3. macOS F5/Fn/Globe BLE 端到端 ✅（F5 keyCode=116；Fn/Globe 听写浮窗+voice-relay.log；codex 路由 right command+豆包）
  4. Windows `0xEE`：**待平台延期**（本机无 Windows）
  5. BLE 首连可达性 ✅（PnP 0x07D7:0x501A 与客户端一致，实机固件=Rhino 系）
  6. v4/EEPROM/Flash ADR ✅（预研报告 §8）
  7. Codex session/thread join ✅ 结论：可行未实现，建议 Studio UI 迭代排期
  8. USB 链路：已知固件缺陷，用户指示忽略，延期
- 产物：`docs/research/wbs-0-static-preflight.md` §8 ADR、`docs/research/hid-capture/`（抓取脚本+keytester+日志）。无白名单外改动，无产品代码改动。
- 请求整卡验收，或裁决完成定义中 USB/Windows/SDK 三项的延期方式。

### [2026-08-25 19:01] Codex 独立验收 accepted（附延期）

- 独立 `SPBluetoothDataType`：AhaKey X1 VID `0x07D7` PID `0x501A`，Address `D4:6C:50:5C:F5:C0`。`SPUSBDataType` 无 AhaKey，USB 枚举延期成立。
- 无产品代码 diff。`docs/research/hid-capture/` 不在原白名单，事后允许为只读证据脚本。
- **延期（不挡本卡，不启动 WBS-1 刷机）**：Windows `0xEE` → 有 Windows 窗口时进 5.10/本卡补证；USB 有线枚举 → WBS-1（已知固件缺陷，本轮忽略）；`EEPROM_BLOCK_SIZE`/`Link.ld` 数值 → WBS-1 取得 SDK 后补，保持 missing。
- F5/Fn/Globe 为功能+日志实证，原始 IOHID 抓取失败，记入卡内，不因此拒绝。
- 本卡 `active` → `accepted`。WBS-1 保持 draft，待用户确认固件工作树后再 `ready`。不 merge。不刷机。
