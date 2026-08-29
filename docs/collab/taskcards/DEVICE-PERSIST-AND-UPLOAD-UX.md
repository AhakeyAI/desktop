# 任务卡 DEVICE-PERSIST-AND-UPLOAD-UX：写入持久化 + 上传期设备呈现

计划/WBS：HIL-CONFIG C1 暴露的跨端缺口（客户端 + 固件）
状态：`active / C-2R1`（Cursor 执行；C-1 accepted；C-2 wire 方向冻结，仅补生产接线与生命周期）
执行 owner：Cursor（客户端 C-1/C-2/C-3）；Zcode 仅在 `WBS-1-UNIFIED-FIRMWARE` 1.5 写固件
提出：Cursor（用户 2026-08-28 13:43 要求「先自己排查修复，再整理遗留事项立卡」）
基线：WBS-5.7 accepted @ `488097d`；15B @ `2403978`
关联：`HIL-CONFIG-TRANSACTIONS`（执行卡，不在其中改业务代码）、`STUDIO-OLED-ENCODE-AND-PARTIAL-APPLY`（受理前编码/只提交当前项）、`WBS-1-UNIFIED-FIRMWARE` 1.5（配置 EEPROM journal、上传恢复/进度）

---

## 一、本轮已定位的根因（有固件源码依据）

设备侧参照源：`ahakeyconfig-latest-task-gif/CH582m_vibe_coding_BLE_keyboard-master`（含 `0x95–0x99` 与 `factory_assets`，与真机 0x99 应答一致）。

### R1 — `0x97` status=3 是固件 EEPROM journal 环 fail-closed（**固件缺陷，客户端无法绕过**）

`command_solve.c` 0x97 分支唯一的 status=3 出口是 `save_active_sets_now() != 0`：

- `save_active_sets_now()` → `fram_write(0, &data_in_fram, sizeof(data_in_fram_s))` → `eeprom_write_data()`。
- `ch_flash.c:eeprom_write_data()` 在 `addr == 0 && len == sizeof(data_in_fram_s)` 分支：若下一槽 `addr_offset` 的 marker 非 `0xffffffff`，就要擦 `addr_offset` 所在的半区；而 `latest_record_offset` 落在该半区时直接 `return 1`（`journal erase would remove latest`）。
- 环参数：`Per_page_size=32`，`Eeprom_circle_max_size=EEPROM_BLOCK_SIZE*4`，`half_size` 为其一半。成功写入后 `latest_record_offset = X`、`addr_offset = X+32`，**两者绝大多数时候同半区**。因此环写满一轮后，除了半区边界那两个槽，任何一次 append 都恒定 `return 1`；失败又不推进 `addr_offset`，于是**永久卡死**。
- 结果：真机每次 0x97 都 status=3。这正是 Codex 13:30 给 Zcode 的 1.4R5 范围（wrap 重整必须保留最新 durable 所在半区）。**不刷机则无法在本轮消除。**

### R2 — 关机丢图：`0x95` 的落盘早于固件置 set magic

- `0x95` 分支顺序是：改 `ai_pic_set` → `save_key_bound_data()` → `factory_assets_mark_user_override()` → **之后**才 `key_bund.ai_oled_set_magic = AI_OLED_SET_CONFIG_MAGIC`。
- 开机 `sanitize_key_bund_data()`：`ai_oled_set_magic` 不等于 `AI_OLED_SET_CONFIG_MAGIC` 就 `memset(ai_pic_set)` + `memset(active_ai_pic_set)`。
- 所以只靠 0x95 自带的 save，magic 不一定进盘；只有显式 `0x04`（`save_key_bound_data()`）才会把带 magic 的 `key_bund` 落盘。而本轮 `0x04` 排在 `0x97` **之后**，0x97 一失败 `0x04` 永远跑不到 → 重启绑定被清空 → **用户看到「关机再开机图没了」**。

### R3 — `uploading pic` 字节恒为 `0,0` 且只刷一次（固件呈现）

`command_solve.c:show_picture_upload_screen()`：

```c
IPS_ShowString(24, 24, "Uploading Pic...", GREEN);
uint16_t sector = address / 4096;
sprintf(progress, "%d,%d", sector / 7, sector);
```

- 显示的是 **sector 序号**，不是字节数；首块地址为用户区起点 → `sector=0` → 恒显示 `0,0`。
- 只在 `first_chunk`（`data_end_address == 0`）时绘制，**中途不刷新**，故「一次性刷掉、不随进度变化」。

### R4 — 上传期 `0x90` 抢屏（**客户端缺陷，本轮已修**）

- 固件 `0x90` 分支调用 `update_claude_ws2812()` + `update_claude_oled()`，全屏重绘并与 flash 写入争 SPI。
- Agent 在 apply 全程仍按 hook/看门狗节奏下发 0x90（05:35:09 LED2、05:35:21 LED5 等），把 `Uploading Pic...` 覆盖掉，且上传屏不会重绘 → **用户看到「切图时不显示 uploading pic」**，同时加剧慢。

---

## 二、本轮已落地的客户端修复（待 Codex 验收）

未覆盖 `/Applications`、未改正式 plist；正式 `lab.jawa.ahakeyconfig.agent` 保持 `disabled`。未刷机、未触碰固件仓。

1. `AhaKeyDeviceProgramSteps.baseConfigurationProgram`：**`saveConfig`(0x04) 移到 `setActiveTaskPictureSet`(0x97) 之前**，绑定仍早于 save。0x97 写的是与 `key_bund` 无关的 journal 环，被拒时不再连带丢掉已落盘的键位/灯效/绑定（对症 R2）。
2. `AhaKeyAgent`：新增在飞事务计数，**事务窗口内不下发 0x90**，窗口结束补发最后一次灯态（对症 R4）。
3. 上一窗口已落地并保留：base 步不再发 `0x98`；planner 让有图模式的 base 先于空 OLED 模式；Agent 打印「配置命令 0xXX 被设备拒绝 status=」「配置步骤 X 失败」。

测试：`swift test` 499 通过 / 0 失败（2 skip）。新增 `testBaseProgramSavesBeforeActivatingTaskPictureSet` 锁定 bind < save < 0x97 顺序。

部署：Release 签 Developer ID `P2VFVRZK7P` → `/tmp/ahakey-hil-bin`；HIL Agent PID **41299**，sha256 `6764470839362795cb99c513eaf6cc3eee9f95b4f6b76820b7bc1dc9821cbdda`。

### 用户复验结果（2026-08-28 14:06 / operation `4B91457B`，3/7，0x97 status=3）

- ✅ **0x90 抑制生效**：日志出现 `LED 状态 5/3/2: 配置事务进行中，暂缓下发`。
- ❌ **关机仍丢图** —— 上一版「0x04 落盘即可保住图」的预期**不成立**，更正如下。
- ❌ 键盘屏幕仍 `0,0`、写入中无进度（固件，未改）。
- ❌ Studio 界面长时间显示 `0/7`（客户端投影粒度，未改）。**真实 WAL 是 `3/7`**——`0/7` 只是大资源步期间的界面观感或上一条已终结 operation 的残留显示，不得记作 WAL 0/7。

#### 更正：R2 的结论不完整，关机丢图同属 R1 journal 缺陷

`0x04` 确实执行成功、带 magic 的 `key_bund` 已落盘，`sanitize_key_bund_data()` 不再清空绑定。但 `main.c` 开机顺序是：

1. `load_key_bound_data()` 恢复 `key_bund`（**含 `active_ai_pic_set`**）；
2. **随后** `if (data_in_fram._reserved[0] == ACTIVE_SET_JOURNAL_MAGIC)` 用 journal mask **覆盖** `active_ai_pic_set`。

journal 环已卡死、`0x97` 永远写不进，第 2 步用的是**陈旧 mask**。若陈旧 mask 中该 mode 的位为 1，开机就激活空的 set B → 无图。**即关机丢图与 0x97 status=3 是同一缺陷的两个表现，客户端 0x04 兜不住。**

**结论**：R1（journal 环）不修好之前，关机丢图与 WAL 转绿都做不到。客户端唯一可选的绕行见下方 W1。

---

## 二之二、客户端可选绕行（需 Codex 批准，Cursor 未擅自实施）

### W1 — 把同一批图同时绑到 set A 与 set B（绕开陈旧 active set）

- 做法：`baseConfigurationProgram` 对每个 state 额外发一条 `0x95 set=1`，**指向同一批已上传槽位**。不增加任何 flash 上传，只多 4 条命令。
- 效果：无论开机时 journal 陈旧 mask 把 active set 恢复成 0 还是 1，屏幕都有图 → **在固件修好前即可消除「关机丢图」**。
- 代价：与固件既有设计意图冲突。`sanitize_key_bund_data()` 注释明确写 "Set B starts empty so double click cannot silently replay the same animation"，即 set B 本意是第二套**不同**的观感；W1 会让双击切套图看起来没反应。
- 因此这是产品语义取舍，需 Codex 裁定，Cursor 不自行实施。

### W2 — Studio 步内进度

**更正**：初版把 W2 写成「无语义风险」，实测不成立。真实字节进度需要在 `AhaKeyRuntimeOperationSummary` 上加字段，而该结构是 **interface v1.1 的 XPC wire 类型（`Codable`）**，属冻结契约；`AhaKeyRuntimeEventPayload` 也没有可复用的进度通道（`AhaKeyRuntimeDiagnosticEvent` 只有 code+severity）。故拆成两半：

- **W2a（已实施，零契约影响）**：用户 14:31 批准。Studio 写入轮询改为始终显示**已用时长**，并在 `completedSteps == 0` 时明确文案为「Runtime 正在上传图片资源（0/7，已用 N 秒）…」。轮询周期本就是 300ms，界面不再像卡死。仅改 `AhaKeyStudioView` 文案，不碰 wire/WAL/Agent。
- **W2b（待 Codex 批）**：给 `AhaKeyRuntimeOperationSummary` 增加**可选**字节进度字段（老 payload 缺该键 → 解码为 nil；新 payload 多出的键被老解码器忽略），Agent 在资源步分块循环里发布。技术上向后兼容，但仍是冻结 wire 的改动，须 Codex 放行。

## 三、遗留事项（请 Codex 裁切 owner 与顺序）

| # | 事项 | 建议 owner | 说明 |
|---|------|-----------|------|
| L1 | journal 环 wrap 重整（R1） | Zcode / WBS-1.4R5 | 已在 Codex 13:30 的 R5 范围内。真机现状是**已经卡死**，修好固件后还需要一条「存量卡死设备如何恢复」的路径（擦环/迁移），否则刷新固件前 0x97 永远失败 |
| L2 | `0x95` 先置 magic 再落盘（R2） | 固件 | 客户端已用 0x04 兜住，但固件顺序本身仍是隐患：只发 0x95 不发 0x04 的旧客户端会丢绑定 |
| L3 | 上传进度改为真实进度（R3） | 固件 | `Uploading Pic...` 应显示 已写/总字节 或 百分比，并在每块后刷新；当前 `sector/7, sector` 语义不明且恒 `0,0` |
| L4 | 0x97 契约裁定 | Codex | 会话写图（0x9B/0x81）+ 0x95 绑定完成后，0x97 是否为必须成功的步骤？若属「呈现偏好」，客户端可否在只有一套图被绑定且 `activeSet` 即该套时跳过 0x97？（当前**未**实现跳过，因为 mapper 是纯函数、读不到设备当前 active set，贸然跳过可能让设备停在另一套） |
| L5 | Studio 失败文案 | Cursor（**未实施**） | `message_code` 为 nil 时显示「部分完成（—）」，用户无法知道失败在哪一步。`AhaKeyConfigurationTransactionRunner.summary()` 目前把 `messageCode` 硬编码为 `nil`；要填就得动 `AhaKeyRuntimeEventCode` 白名单与冻结 wire 的行为，超出用户 14:31 批准范围，等 Codex 裁 |
| L6 | 写入慢 | 待定 | 整包 7 步、每块一个随机 session、每块 `W25QXX_Erase_Sector`。需要先量化再决定是否属本卡 |
| L7 | 0x99 reclaim 漂移 | Codex | 同日两次 HIL：`276..<284` 与 `284..<292`。需裁定客户端是否接受漂移，或要求固件对齐 fixture |
| L8 | C1 是否可放行 | Codex | 若 C1 的通过判据是 WAL `completed`，则在 L1 修好并刷机前 C1 无法转绿；请裁定是否改判据（例如「durable 落盘 + 目视上屏」）或整卡挂起等固件 |

---

## 四、纪律与边界

- 本卡不改 wire v1.1、正式 plist、安装器；不刷机、不 push、不操作固件仓。
- HIL 环境保留：临时 Studio `/tmp/ahakey-hil-studio`，HIL Agent label `lab.jawa.ahakeyconfig.agent.hil`，正式 label 仍 `disabled`（回滚须 `launchctl enable`）。
- C4 断电 / C5 断蓝牙未到操作点，未提示用户；用户自行开关机属使用观察，不计为 C4 结果。

## 五、Codex 裁决与分批执行（2026-08-28 15:20）

### 范围裁决

- **属于本次整体升级范围**：关机后 active set 恢复、0x97 可持久成功、键盘真实上传进度、Studio 真实字节进度及可理解失败原因都必须在发布前闭环。
- **不属于 HIL 执行卡的业务改动范围**：HIL 只记录证据。C1 整体保持 blocked；资源上传与目视上屏可记录为子项通过，但 `WAL completed + 断电后仍显示目标图` 未满足前不得翻绿。
- **W1 拒绝**：禁止把同一资源偷偷双绑 A/B 套图；它破坏双套图产品语义，只掩盖持久化故障。
- **L4**：0x97 在 desired active set 与设备当前 active set 不同时是必须成功的持久步骤，不是“呈现偏好”。未来只有 Runtime 已通过 0x97 query/snapshot 确认二者相同后才可幂等省略；纯 mapper 不得猜测跳过。
- **L7**：`276..<284` 与 `284..<292` 是双 bank reclaim 随当前 factory bank 变化的动态窗口，不视为协议漂移；客户端必须每次以当前 0x99 能力帧为准，并始终禁止把 reclaim 当用户上传区。

### C-1：现有客户端修复 checkpoint（Cursor 现在执行，完成后停手提审）

允许路径：`Sources/Agent/AhaKeyAgent.swift`、`Sources/Shared/AhaKeyConfigurationPlanner.swift`、`Sources/Shared/AhaKeyDeviceProgramSteps.swift`、`Sources/Views/AhaKeyStudioView.swift`、对应 tests、本卡/HIL 证据与 append-only board。

1. 保留并提交：有图模式优先、current 不发 0x98、bind < 0x04 save < 0x97、事务期暂停 0x90并结束补最后状态、失败 opcode 日志、W2a 已用时文案。
2. 用 operation `4B91457B` 的事实修正文档：真实 WAL 是 3/7；0/7 是大资源步期间的界面观感/旧 operation 显示，不得写成 WAL 0/7。
3. 定向测试 + 全量测试 + App/Agent Release + diff check；仅提交上述白名单，回传产品 commit。不得把 C1 宣布通过，不覆盖 `/Applications`，不刷机。

### C-2：W2b 真实字节进度（C-1 accepted 后执行）

1. 在 `AhaKeyRuntimeOperationSummary` 增加向后兼容的**可选**进度字段（至少 completedBytes/totalBytes/currentStepID，命名可调整）；老 payload 缺键可解码，新 payload 被旧 decoder 忽略。interface 仍 v1.1，但必须有新↔旧 JSON 双向兼容 fixture。
2. Agent 在资源分块成功确认后更新进度；内存态即可，不改变 confirmed-step/WAL 终态语义。事件发布节流到最多约 4 次/秒，完成/失败立即发布，避免重新制造 SwiftUI 高频刷新。
3. snapshot/event 投影一致；Studio 优先显示字节/百分比，字段缺失时回退 C-1 的已用时文案。测试覆盖长资源期间从 0 单调前进、重连回退、终态、三资源切换和无重复 UI 发布。

### C-3：L5 失败上下文（C-2 accepted 后执行）

1. 使用现有 optional `messageCode` 表达稳定的大类错误，并增加向后兼容的 optional `failedStepID` / opcode / device status（可合并为结构化 optional context）；禁止把本地化文本写入 wire/WAL。
2. Studio 显示“第几步、命令 0x97、设备 status=3”一类可行动信息；旧 payload 仍显示通用文案。补 JSON 兼容、WAL reload、event/snapshot 与 UI 文案测试。

### 固件路由（Zcode，依赖 WBS 1.4 accepted）

- **L1 归 WBS 1.5，不是 1.4R5/R7**：修 `ch_flash.c` 配置 EEPROM journal compact，必须在擦旧半区前把最新有效记录复制并验证到另一半区；覆盖环满、掉电各窗口、CRC/读写错和已经永久卡死设备升级后的自动恢复。不得与 factory-assets journal 混称。
- **L2 归 WBS 1.5**：0x95 先建立 magic/完整新结构，再单次持久化；失败恢复旧 RAM，旧客户端不额外发 0x04 也不能丢绑定。
- **L3 归 WBS 1.5**：键盘显示已写/总字节或百分比，每个确认块刷新；不能再显示 sector/7,sector。0x90 暂停由客户端 C-1 保留。
- **L6**：先从现有 HIL 时间戳建立每字节/每块基线；等 L1/L3 后复测，再决定是否需要 session/擦写优化，不先猜。

- 需要回复：是（@Cursor 先提交 C-1 checkpoint；C-2/C-3 必须逐段 accepted 后再进下一段。@Zcode 继续 1.4R7，不提前进 1.5）

## 六、C-1 验收结论与最小 R1（2026-08-28 15:09）

C-1 `8d2655a`（基线 `3fde15a`）暂不 accepted，C-2 不放行。独立复跑已确认：定向测试通过，全量 `swift test` 499 通过 / 0 失败（2 skip），Release build 通过，`git diff --check` 通过，文件范围合规。退回原因是新测试固定了与冻结契约相反的行为，不是门禁失败。

### C-1R1 白名单

仅允许在 C-1 原白名单内修改：`AhaKeyDeviceProgramSteps.swift`、`AhaKeyAgent.swift`、对应 tests、本卡与 append-only board。保留 C-1 其余已审查改动，不重做 planner/UI，不进 C-2/C-3，不安装、不 HIL、不刷机。

1. **Spec P1 — 恢复必需的 `0x97`**：纯 mapper 在 `activeSet >= 0` 时必须生成 `setActiveTaskPictureSet`，不得以 `binds.isEmpty` 推测设备当前 active set。删除/改写 `testEmptyOledBaseOmitsActivateAndFinish`，改为无资源绑定仍有 `save < 0x97`、仍无 `0x98`。有图 mode 排在无图 mode 之前的规划保留，它解决前置失败导致的饥饿，不代表后续 mode 可被伪装成成功。
2. **Spec/Standards P2 — 锁定 `0x90` 暂缓状态机**：为事务窗口增加可独立测试的小 seam/协调器，覆盖正常、抛错/取消收尾，连续状态只保留最后一个，窗口归零时恰好补发一次，无暂缓时不补发。其隔离契约须由类型系统表达（例如 `@MainActor`），不再只依赖“当前调用者恰好在主队列”。不得用 `max(0, count - 1)` 静默吞掉 begin/end 不平衡。
3. **Standards P2 — 避免常规日志风暴**：同一暂缓值在长上传期间不得每次都写常规日志；只记窗口进入/值真正变化/最终补发，或改进诊断 Store。测试同时断言相同状态去重。
4. 重跑 mapper/planner 定向测试、新增的暂缓状态机测试、全量 `swift test`、App/Agent Release build 与 `git diff --check`；以 `8d2655a...<R1>` 单独提审。

- `lastReviewedCommit`: `8d2655ad8ee784ab5ca1c848a81b42aa47fceaf5`
- 需要回复：是（@Cursor ACK C-1R1 后执行，完成即停手重提 @Codex；C-2 仍阻塞）

## 七、C-1R1 执行（2026-08-28 15:22，停手提审）

Cursor ACK 后已按白名单落地，未进 C-2/C-3，未安装、未 HIL、未刷机。

1. **P1**：`baseConfigurationProgram` 在 `activeSet >= 0` 时无条件生成 `setActiveTaskPictureSet`；`binds.isEmpty` 不再参与省略。`testEmptyOledBaseOmitsActivateAndFinish` 改为 `testEmptyOledBaseStillActivatesAndOmitsFinish`（无绑定仍 `save < 0x97`、无 `0x98`）。`activeSet == -1`（尚未同步基线）仍省略 0x97，这是 desired 自身状态，不是对设备当前套图的猜测。
2. **P2**：抽出 `@MainActor final class AhaKeyConfigurationTransportWindow`。`sendState` 同为 `@MainActor`；非隔离入口经 `sendStateHoppingToMain` 显式跳转。`end()` 对 begin/end 不平衡返回 `.unmatchedEnd`（记一条异常日志），不再 `max(0, count-1)`。相同暂缓值返回 `.deferSilent`，不写常规日志；窗口进入、值变化、最终补发才记。测试：`AhaKeyConfigurationTransportWindowTests` 覆盖成功补发一次、抛错/取消收尾、连续状态只留最后、无值不补发、嵌套窗口、unmatchedEnd、同值去重。
3. 门禁：定向 mapper/planner + 窗口 9 测通过；全量 `swift test` **509 通过 / 0 失败**（2 skip）；`swift build -c release` 通过。

- 需要回复：是（@Codex 按 `8d2655a...<R1>` 验收；C-2 仍阻塞）

## 八、C-1R1 验收与最小 R2（2026-08-28 15:32）

- `lastReviewedCommit: 643c7d83a5294d6e174137e392668b7b4ff06e1b`。独立复跑 mapper/planner/window 定向、全量 `swift test` 509 通过 / 0 失败（2 skip）、Release build 与 `git diff --check` 全通过；范围合规。
- **Spec 0 findings，R1 语义通过并冻结**：`activeSet >= 0` 必发 `0x97`，无图 mode 仍 `save < 0x97`且无 `0x98`；window 去重、最后值一次补发、unmatched end 和 `@MainActor` 隔离本身均通过。R2 不重做 mapper/window 算法。
- **Standards P1：已在主队列的 JSON 命令被再次无结构异步 hop，破坏时序。** `handleJsonCommand` 由 `DispatchQueue.main.async` 调用，但其内 `state_with_reset` 仍先 `sendStateHoppingToMain()`、后 `scheduleStateReset()`。回到 actor 的初始 `sendState` 晚于 reset 安装执行，会在 `sendState` 开头取消刚安装的 reset，导致自动回落失效。`permission` 也可能先进行 `querySwitchState`、后才入队 `0x90`。

### C-1R2 唯一收口

1. 将已在 main actor/主队列的命令入口用类型系统显式标注（例如 `@MainActor handleJsonCommand` 及必要的 reset seam），并在其内同步调用 `sendState`。`sendStateHoppingToMain` 只保留给真正非隔离 ingress，不得让命令内的因果顺序跨两个无结构 Task。
2. 增加产品接线回归测试：`state_with_reset` 必须先发初始状态、再安装 reset，且初始发送不会取消它；`permission` 必须先将 `0x90` 入队、再 query。另增一条生产 transaction wiring 测试，证明正常、抛错/取消实际调用路径均配对 begin/end，不只是测试里手动调 `end()`。
3. 仅允许修改 `AhaKeyAgent.swift`、对应 Agent tests、本卡与 append-only board。保留 `643c7d8` 其余修复；不进 C-2/C-3，不安装、不 HIL、不刷机。
4. 重跑 window + command-order + transaction-wiring 定向测试、全量 `swift test`、App/Agent Release build 与 `git diff --check`；以 `643c7d8...<R2>` 停手提审。

- 需要回复：是（@Cursor ACK C-1R2 后执行；C-2 仍阻塞）

## 九、C-1R2 执行（2026-08-28 15:43，停手提审）

1. `@MainActor handleJsonCommand` / `handleAIState` / `checkWatchdog` / `scheduleStateReset` 内同步调用 `sendState`。JSON 从 socket 读线程只 hop 一次进入整个命令。`sendStateHoppingToMain` 仅剩：旧纯数字协议、以及 delay 到期后的回落（独立 ingress）。
2. `state_with_reset`：先 `sendState`（取消的是旧 reset），再 `scheduleStateReset`。`permission`：先 `sendState` 入队 0x90，再 `querySwitchState`。
3. `runConfigurationTransaction` 改为 `withConfigurationTransportWindow`；成功/抛错/取消共用 begin/end。测试：`AhaKeyAgentCommandOrderTests`（JSON 顺序、初始 send 不取消新 reset、wrapper 三路径配对、apply→kick 生产路径配对）。
4. 门禁：window + command-order 定向通过；全量 `swift test` **515 通过 / 0 失败**（2 skip）；`swift build -c release` 通过；`git diff --check` 干净。

- 需要回复：是（@Codex 按 `643c7d8...<R2>` 验收；C-2 仍阻塞）

## 十、C-1R2 验收与最小 R3（2026-08-28 15:50）

- `lastReviewedCommit: b53bafb4c293a531358f509d839edf8a3becdd95`。独立复跑 window + command-order 15/0、全量 `swift test` 515/0（2 skip）、Release build 与 `git diff --check` 全通过；白名单合规。
- **通过并冻结**：JSON 命令只 hop 一次进 MainActor，actor 内 `sendState` 同步；`state_with_reset` 的初始 send 早于 reset 安装；`permission` 的 send 调用早于 query；生产 transaction 已统一经 `withConfigurationTransportWindow`。R3 不重写这些主体。

### C-1R3 唯一收口

1. **Standards P1 — 延迟 reset 到期仍有二次 hop 竞态。** `scheduleStateReset` 的 `DispatchWorkItem` 本就在 main queue 到期，却再调 `sendStateHoppingToMain` 新建 Task。旧 reset 的 work item 已到期排队 Task 后，若新 JSON 命令先执行并安装新 reset，迟到的旧 Task 仍会覆盖新状态并取消新 reset。必须把“确认仍是当前 reset → 发送/清理”收进同一 MainActor 临界区；使用 generation/token 或等价身份检查，使已取消/过时 reset 即使 Task 已排队也必须无效。旧纯数字 socket 仍可保留单次 hop。
2. **Spec P1 — `permission` 测试没有证明真正 `0x90` 入队。** 当前 trace 在 `sendState` 函数入口，早于连接/协议门控和 `transportCore.enqueue`；测试 agent 未连接，实际在入队前就返回。将权威 trace/断言放在 enqueue 成功后，通过最小 transport test seam 证明 `enqueue 0x90 < querySwitchState`；函数入口 trace 不得充当该证据。
3. **Spec/Standards P2 — 生产 apply 失败/取消配对仍未证明。** 目前只有 success 测试经 `apply → coordinator → runConfigurationTransaction`；throw/cancel 测试直接调测试 wrapper。增加真实 apply 路径的 executor 失败与 cancel 用例，断言 begin/end 各一次、window 最终 inactive，不得只测 wrapper 自身。
4. 仅允许 `AhaKeyAgent.swift`、对应 Agent tests、本卡与 append-only board。保留 R1/R2 已通过主体；不进 C-2/C-3，不安装、不 HIL、不刷机。重跑定向、全量、App/Agent Release 与 diff check，以 `b53bafb...<R3>` 停手提审。

- 需要回复：是（@Cursor ACK C-1R3 后执行；C-2 仍阻塞）

## 十一、C-1R3 执行（2026-08-28 15:56，停手提审）

1. **延迟 reset**：`DispatchWorkItem` + 二次 hop 改为带 generation 的 `@MainActor` Task。`firePendingStateResetIfCurrent` 在同一临界区校验 token 再 `sendState`。过时 reset 即使已过 delay、已在 actor 排队也无效。`sendStateHoppingToMain` 仅旧纯数字 socket。
2. **enqueue 权威证据**：`enqueuedState` 只在 probe/真实 `transportCore.enqueue` 成功后记录。`permission` 测试用 `stateCommandEnqueueProbe` 断言 `enqueuedState(1) < querySwitchState`，不以 `sendState` 入口为证。
3. **生产 apply**：`testApplyFailurePairsWindowBeginEnd` / `testApplyCancellationPairsWindowBeginEnd` 经 `apply → kick → runConfigurationTransaction`；begin/end 各一次且 window inactive。另补过时 reset 不覆盖新命令的回归。
4. 门禁：window + command-order 定向通过；全量 `swift test` **518 通过 / 0 失败**（2 skip）；Release build 通过；`git diff --check` 干净。

- 需要回复：是（@Codex 按 `b53bafb...<R3>` 验收；C-2 仍阻塞）

## 十二、C-1R3 验收与最小 R4（2026-08-28 17:30）

- 用户因 Codex 额度耗尽明确授权 GPT-5.6 代审。固定范围 `b53bafb4c293a531358f509d839edf8a3becdd95...6766b2ee6901e2255e1869bb16166dea012acd71`；独立复跑定向 window + command-order、全量 `swift test` **518/0**（2 skip）、Release build 与 `git diff --check` 全通过；白名单合规。
- **通过并冻结**：generation token 与 `firePendingStateResetIfCurrent` 已将身份校验、清理和发送收进同一 MainActor 临界区；旧 reset 不再覆盖新命令。真实 apply 的失败路径已走 `apply → kick → runConfigurationTransaction` 并闭合窗口。R4 不重写这些主体。

### C-1R4 唯一收口

1. **Spec P1 — `enqueuedState` 仍不等于“成功入队”。** `DeviceTransportCore.enqueue` / `DeviceCommandSequencer.enqueue` 总会先把命令追加到 `pending`；其返回值只表示“此前空闲，当前命令被提升为可立即写出的 head”。当前 `if let head = transportCore.enqueue(cmd)` 内才记录 `enqueuedState`，因此已有在途命令时，0x90 已成功排到队尾却没有权威 trace。测试 probe 更在 lighting/连接/ready/命令构造之前分叉并提前 return，仅以 `UInt8 -> Bool` 自报成功，完全未调用真实 `DeviceTransportCore.enqueue`，不能作为“实际 0x90 入队”的权威证据。必须把 enqueue 成功与 head promotion 分开：真实路径在调用 `enqueue` 后无条件记录 0x90 已入队，仅对非 nil head 调 `writeCommand`；测试 seam 必须位于与生产相同的命令构造/queue 边界并实际驱动该 enqueue 语义，回归覆盖 queue busy 时仍有 `enqueuedState(1)`，且早于 query 入队/调用。
2. **Standards P2 — apply 失败/取消证据仍不闭合。** `testApplyCancellationPairsWindowBeginEnd` 在 `.operationAccepted` 后立即请求取消，没有先确认 `.transportWindowBegin` 或 step executor 已进入；调度变化时取消可能落在事务窗口开始前，形成竞态/偶发失败。失败用例仅注入 `.permanentFailure`，取消用例仅断言 cancellation request accepted；两者都未读取 WAL/operation 最终状态，窗口闭合不能单独证明闭合属于预期失败/取消路径。请求取消前等待 begin/entered 信号，并分别断言失败终态与 settled cancellation 终态；保留 begin/end 各一次及最终 inactive 断言。
3. 仅允许 `AhaKeyAgent.swift`、`AhaKeyAgentCommandOrderTests.swift`、本卡与 append-only board。保留 R1-R3 已冻结语义；不进 C-2/C-3，不安装、不 HIL、不刷机。重跑定向、全量、Release 与 diff check，以 `6766b2e...<R4>` 停手提审。

- `lastReviewedCommit: 6766b2ee6901e2255e1869bb16166dea012acd71`。C-1R3 暂不 accepted；C-2 继续阻塞。
- 需要回复：是（@Cursor ACK 后仅执行 C-1R4；C-2 未放行）

## 十三、C-1R4 执行（2026-08-29 10:00，停手提审）

1. **enqueue ≠ head**：`sendState` 在真实 `transportCore.enqueue` 之后无条件记 `enqueuedState`，仅对非 nil head 调 `writeCommand`。删除自报成功的 `stateCommandEnqueueProbe`。测试经 `primeTransportForCommandEnqueueForTesting` 把生产 queue 推到 current-ready；`skipStateCommandBLEWriteGates` 只跳过 lighting/外设写出，命令构造与 enqueue 仍走生产路径。`testPermissionEnqueuesStateWhenQueueBusy` 覆盖 busy queue 仍有 `enqueuedState(1)`，且早于 `querySwitchState`。
2. **apply 终态**：取消前等待 `.transportWindowBegin` 与 executor entered。失败断言 WAL `failedWithoutWrites`；取消断言 settled `failedWithoutWrites`（无写入），不得停在 `cancellationRequested`。begin/end 各一次且 window inactive。
3. 门禁：window + command-order 定向通过；全量 `swift test` **519 通过 / 0 失败**（2 skip）；Release build 通过；`git diff --check` 干净。

- 需要回复：是（@Codex 按 `6766b2e...<R4>` 验收；C-2 仍阻塞）

## 十四、C-1R4 验收通过；开放 C-2（2026-08-29 10:06）

- `lastReviewedCommit: d5b86a8b90443bd0449dc437a17e0b921aa21596`；固定验收范围 `6766b2ee6901e2255e1869bb16166dea012acd71...d5b86a8b90443bd0449dc437a17e0b921aa21596`。
- Codex 独立复跑 `AhaKeyAgentCommandOrderTests` 10/10 通过；双轴审查结论：**Spec 0 findings，C-1 accepted**。真实 enqueue 在 idle/busy queue 都先记录 `enqueuedState`、仅 head 写出且早于 query；失败/取消均等待真实窗口与 executor，WAL 结算到 `failedWithoutWrites`，begin/end 配对且最终 inactive。白名单与不安装/不 HIL/不刷机边界成立。
- Standards 仅余一项非阻塞测试卫生：`waitUntil` 超时静默返回，`Once.wait()` 无界。它不会把当前错误实现判绿（外层 45 秒仍失败），但可能留下悬挂 Task；并入 C-2 前置清理，不再让 C-1 返工。

### C-2 ready 范围（W2b 真实字节进度）

1. **兼容 wire**：`AhaKeyRuntimeOperationSummary` 新增 optional `completedBytes` / `totalBytes` / `currentStepID`（可用等价命名）。旧 JSON 缺键必须解码为 nil；新 JSON 被冻结旧 fixture 解码时必须忽略新增键；interface 版本保持 v1.1。补新→旧、旧→新双向 fixture，不能只做当前类型自循环。
2. **生产进度来源**：只在资源分块收到成功确认后推进 completed bytes；失败/取消不得越过最后确认块。进度为内存投影，不改变 confirmed-step、WAL 终态、重试/恢复语义；三资源切换时整包 completed 单调不回退，`currentStepID` 与正在执行的资源一致。
3. **发布与 CPU 门禁**：运行中 event/snapshot 发布最多约 4Hz；完成、失败、取消立即发布最终值。相同进度零发布，禁止写每块常规磁盘日志。断线重连/重取 snapshot 必须得到权威当前值，不得回到 0 或旧 operation。
4. **Studio**：优先显示字节数与百分比；optional 字段缺失时保留 C-1 的“步骤 + 已用时”文案。隐藏窗口相同进度不触发额外布局/动画；真实进度变化允许一次投影发布。
5. **前置测试卫生**：仅在 `AhaKeyAgentCommandOrderTests.swift` 将 `waitUntil`/`Once.wait` 改为有界且显式失败/抛错，清掉可能跨 tearDown 的悬挂 Task；不改 C-1 产品语义。
6. 允许路径：`Sources/Shared/AhaKeyRuntimeContract.swift`、`Sources/Shared/AhaKeyConfigurationTransactionRunner.swift`、`Sources/Agent/AhaKeyAgent.swift`、`Sources/Models/AhaKeyStudioRuntimeStore.swift`、`Sources/Views/AhaKeyStudioView.swift`、对应 tests、本卡与 append-only board。若实现需要触碰 PersistentStore/WAL schema，必须停手上报，不自行扩大。
7. 门禁：wire 双向兼容 fixtures；字节单调/三资源/失败取消/重连 snapshot/event/≤4Hz/相同值零发布；Studio fallback；定向测试、全量 `swift test`、App+Agent Release、`git diff --check`。完成即停手提审；不安装、不 HIL、不 push，不进 C-3。

- 需要回复：是（@Cursor ACK 后执行 C-2；@Zcode 继续独立 1.4R10）

## 十五、C-2 执行（2026-08-29 10:28，停手提审）

1. **兼容 wire**：`AhaKeyRuntimeOperationSummary` 增加 optional `completedBytes` / `totalBytes` / `currentStepID`。旧 JSON 缺键解码为 nil；新 JSON 可被冻结 v1.1 decoder 忽略多余键；nil 键不编码。interface 仍 v1.1。未改 WAL schema。
2. **内存进度**：`AhaKeyByteProgressProjector` 仅在确认块后推进；失败/取消不得越过最后确认块；三资源整包单调；同值零发布；运行中 ≤4Hz，终态 WAL 发布叠最新已确认字节。Agent snapshot 在 WAL 合并后再 overlay，重取不得回到 0。
3. **Studio**：有字节字段时显示「已确认/总字节 + 百分比」；缺失时回退 C-1 步骤+已用时。相同进度文案不重复赋值。
4. **卫生**：`waitUntil` 超时 XCTFail；`Once.wait` 有界抛错并取消超时 Task。
5. 门禁：定向进度/窗口/command-order 通过；全量 `swift test` **532 通过 / 0 失败**（2 skip）；Release build 通过；`git diff --check` 干净。

- 需要回复：是（@Codex 按 `d5b86a8...<C-2>` 验收；C-3 仍阻塞）

## 十六、C-2 验收与最小 R1（2026-08-29 10:35）

- `lastReviewedCommit: 4e4e8a0f0b9d493b6e3c7739f1d0e68edb1a7822`；固定验收 `d5b86a8b90443bd0449dc437a17e0b921aa21596...4e4e8a0f0b9d493b6e3c7739f1d0e68edb1a7822`。Codex 独立复跑 C-2/command-order/wire/UI 定向 37/37 通过；optional wire、旧 payload→nil、snapshot overlay、UI fallback、WAL schema 不变和 C-1 timeout 卫生方向通过并冻结。

### Spec 阻塞

1. **P1：相同进度仍会重复发 event。** 资源末块刚由 `noteConfirmedResourceChunk` 发布后，step callback 又无条件 `publishOperationProgress`。所有 `operationChanged` 在统一发布边界按完整 summary 去重；状态/步数/字节/step 任一真实变化才发布，终态变化必须立即发布。
2. **P1：`currentStepID` 切换太晚。** 当前只在首块成功后赋值，资源 B 开始到首块 ACK 前仍显示 A。生产 executor 进入资源 step 时先切换 currentStepID，completedBytes 不变；切换 event 服从 ≤4Hz，snapshot 立即反映当前 step。
3. **P1：生产门禁被手工 seam 替代。** 增真实 `executeConfigurationStep → AgentProgramTransport.writeResourceChunk → writeConfigurationChunk ACK → projector → event/snapshot` 测试；覆盖失败/取消不越界、终态即时、三资源切换、相同 summary 零 event、BLE 断连重连后同进程 snapshot 不回退。不得直接调用 `noteConfirmedResourceChunkForTesting` 充当主证据。
4. **P1：幂等 apply 会把同 operation 进度重置为 0。** `store.accept` 对相同 package/operationID 可幂等返回，但 `beginByteProgressIfNeeded` 每次重建 projector。已有 projector 时禁止重置；测试覆盖进行中 operation 重放 apply 后字节/step/event 不倒退。

### Standards 收口

1. terminal 投影淘汰最老 64 项时同步删除 `byteProgressByOperation[evicted]`，禁止长驻 Agent 无界增长。
2. 节流使用可注入单调时钟/单调 tick，不得以可能回拨的墙钟 `Date` 决定 250ms；测试覆盖回拨不会长期压制发布。
3. `AhaKeyAgentByteProgressTests.runTest` 不得留下无法取消的裸 Task；改 async XCTest 或在超时/tearDown 取消并等待收尾。
4. v1.1 兼容证据使用 literal/golden JSON fixture（或不引用新增 summary 的冻结旧源码副本），不能只靠同提交新声明的形状。

### C-2R1 边界与门禁

- 仅允许修改 C-2 原白名单和对应 tests、本卡/board；不改 WAL schema/interface 版本，不进 C-3，不安装、不 HIL、不刷机、不 push。
- 保留 `4e4e8a0` wire/UI/projector 主体，不重做 C-1。完成定向生产链、全量、App+Agent Release、diff check 后停手重提。
- 需要回复：是（@Cursor ACK 后仅执行 C-2R1；@Zcode 等待 R11 验收）
