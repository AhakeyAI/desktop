# 任务卡 V03-STUDIO-OLED-LEGACY-COMPATIBILITY：旧固件 OLED 写入兼容与 Studio 正式路径

计划/WBS：v0.3 客户端 OLED 兼容版
状态：`ready / C1 capability and planner routing`
执行 owner：Cursor
验收：Codex；Zcode 仅只读核对固件协议事实
前置：`V021-RUNTIME-SIGPIPE-SURVIVAL` accepted，`HIL-RELEASE-0.2.1` 完成当前发布收口
产品基线：从最终 v0.2.1 产品提交冻结，不从 HIL 驱动或临时 Runtime 分支起步

## 用户目标

v0.3 作为可对外分发的重构后 macOS 客户端，独立开放图片写入；不得再等待统一固件 WBS 1.6/1.7、刷机或 `HIL-CONFIG` C1-C6。兼容目标是**已登记的全部旧固件基线**；未知、损坏或无法可靠识别的固件必须只读或明确拒绝，禁止猜测协议后写入。

统一固件继续由 Zcode 独立推进，后续用于平台识别和按平台发送不同快捷键，不作为本卡完成条件。

## 已成立的证据基线

- [`runtime-oled-differential.md`](../evidence/RHINO-FLASH-20260902/runtime-oled-differential.md)：Gitee Rhino `53cd0a97e95e3b8b35cd56ed2284970d5a79d1be` 上，新 Runtime 专用 HIL 驱动完成套图 B `5/5`、`102400/102400`；套图 A 未覆盖；A/B 两次切换及断电后均保留；自动重连正常。
- 该证据证明编码、CAS、XPC、planner、事务执行、B 套绑定/激活和持久化底层链路可用，也推翻“新 Runtime 必然无法写图/关机必丢图”的旧归因。
- 键盘端 `0,0` 是旧 Rhino 固件 `0x80` 上传页的显示缺陷，不是 Runtime/WAL 进度事实源。Studio 必须显示 Runtime 的已确认字节进度，并在兼容说明中标注旧键盘屏幕可能不更新。
- 该证据使用专用 HIL desired configuration，**尚未证明正式 Studio UI/assembler 能表达同样的 B-only 写入**；这正是本卡必须补齐的产品缺口。

## 已登记旧固件兼容矩阵

至少覆盖以下冻结基线；每一行必须记录协议探测、所选 planner 路径、命令序列、成功判据和真机结果：

| 固件族 | 冻结基线 | v0.3 要求 |
|---|---|---|
| GitHub Standard | `3e7f900`（与已冻结 master 同树） | 使用其真实 legacy 图片协议；不发送只属于 Rhino/current 的命令；完成单图写入、显示与断电保持 |
| Gitee Rhino | `53cd0a97` | 复现差分证据并改由正式 Studio UI 写 A/B；可只改一套且保留另一套 |
| Local Rhino | `00eb7efc` | 按真实能力/协议选择兼容路径；完成 A/B、切换与断电保持 |
| 向前兼容 current/unified | 仅 host/契约门禁，真机待可刷产物 | 只在能力明确广告时使用新命令；不阻塞 v0.3 旧固件客户端发布 |

“全部旧固件”指上述已登记、可取得且曾发布/冻结的固件族。发现新的历史固件时先登记 SHA/HEX 与能力事实，再加入矩阵；不得用未知固件成功猜测扩大公开承诺。

## 实现切片

### C1：能力识别与 planner 路由

1. 建立单一 `OLEDCompatibilityProfile`（名称可调整）：输入只包含已验证的 capability/协议事实，输出 legacy Standard、Rhino dual-set、current/session-capable 或 unsupported。
2. Standard 路径不得发送 `0x95/0x97/0x98/0x9A/0x9B`，除非该固件事实明确支持；Rhino/current 只发送各自已证明的命令序列。
3. 短帧、缺失 `0x99`、14/22/26B capability 和异常 flag 均须有冻结 fixture。未知组合 fail-closed，不允许以 firmware version 字符串猜测。
4. 每条路径分别定义成功：以 Runtime operation/WAL、设备回复及必要的回读/目视为准；键盘旧上传页的 `0,0` 不参与失败判定。

### C2：正式 Studio scoped assembler

1. 正式 UI 必须能表达“只写当前模式、只写 A 或 B、保留未选择套图”，不得自动镜像 idle/defaultAnimation 或把另一套图塞进 package。
2. 复用已验收的 160×80 编码、抽帧、临时文件清理、字节级进度和 scoped baseline；不得恢复 Studio 直连 BLE。
3. 写入前给出固件兼容路径和影响范围；不支持的组合在 ingest/apply 前失败。
4. 成功后仅更新实际提交范围的同步基线；失败/取消保留可理解的 operation、opcode/status 和恢复建议。

### C3：兼容回归与公开产品收口

1. host 测试冻结三类旧固件的命令序列，覆盖 A-only、B-only、覆盖当前套、保留另一套、取消/重连、超限与未知能力。
2. 全量 Swift、App+Runtime Release、签名 XPC、Hook 三态、安装器升级/回滚不得回退。
3. 形成公开兼容清单与已知限制；HIL driver 不进入 App、Runtime、DMG 或用户文档。

## 路径白名单（C1 开工前由 Codex 按最终 v0.2.1 基线细化）

- `ahakeyconfig-mac/Sources/Shared/**` 中 OLED capability/planner/assembler/facade 的最小文件集
- `ahakeyconfig-mac/Sources/Models/**`、`Sources/Views/**` 中 scoped OLED 写入与兼容提示的最小文件集
- 对应 `ahakeyconfig-mac/Tests/**`
- 本卡与 append-only board

禁止在 ACK 前自行扩大到 Agent BLE lifecycle、Hook、安装器、外部 identity、固件仓或 HIL 环境。

## 完成定义

- 正式 Studio UI（不是专用 HIL 驱动）在三类已登记旧固件上走正确协议，真机矩阵全部通过。
- Gitee Rhino 上复现 B-only：`5/5`、完整字节进度、A 保留、A/B 断电后保留、自动重连。
- Standard 上图片写入、显示和断电保持通过，且日志证明未发送不支持的 Rhino/current opcode。
- Local Rhino 上 A/B scoped 写入、切换、断电保持通过。
- 未知/畸形 capability 在写入前 fail-closed；不覆盖现存图、不产生部分写入。
- 旧固件键盘端 `0,0` 明确列为固件 UI 限制；Studio 的 Runtime 字节进度必须正确且单调。
- 产出可签名、可公证候选所需的代码与兼容文档；签名/安装仍由 `HIL-RELEASE-0.3` USER-GATE 执行。

## 禁止事项

- 不刷机；不以统一固件特性代替旧固件兼容测试。
- 不把 `HIL-CONFIG` C1-C6 或 WBS 1.6/1.7 设为本卡依赖。
- 不恢复 Studio 直连 BLE，不绕过 Runtime/WAL，不隐藏失败。
- 未经用户批准不得签名、公证、覆盖安装、push 或切换公开渠道。

## 执行记录（append-only）

等待 v0.2.1 收口。满足前置后由 Codex 把本卡翻为 `ready / C1`，Cursor ACK 后仅执行能力识别与 planner 路由切片。

### [2026-09-02 23:34] Codex：v0.2.1 前置闭环，开放 C1

- `HIL-RELEASE-0.2.1` accepted @ `a9ad5a2`；最终产品基线为 `1ed560b`，已安装候选为 `0.2.1 (362)`。本卡翻 `ready / C1`，Cursor 为唯一客户端写者。
- C1 只建立单一 OLED 兼容 profile 与 planner/program-step 路由：`legacy Standard`、`Rhino dual-set`、`current/session-capable`、`unsupported`。输入只能是已验证的 capability/协议事实；未知或畸形组合在 ingest/apply 前 fail-closed。
- Standard 严禁 `0x95/0x97/0x98/0x9A/0x9B`；Rhino/current 只生成各自冻结序列。成功判据用 Runtime operation/WAL + 设备回复；旧固件键盘端 `0,0` 不判失败。
- C1 白名单：新增 `ahakeyconfig-mac/Sources/Shared/AhaKeyOLEDCompatibilityProfile.swift`（名称可等价调整）；`AhaKeyFirmwareCapabilities.swift`、`AhaKeyConfigurationPlanner.swift`、`AhaKeyDeviceProgramSteps.swift`、`AhaKeyTaskPictureProtocolPlan.swift`；精确对应的 `Tests/AhaKeyConfigSharedTests/*Capabilities*`、`*Planner*`、`*StepMapper*`、`*TaskPictureProtocolPlan*`、`*OLEDCompatibility*`；本卡与 append-only board。
- 测试必须冻结：无 `0x99`、短帧、14/22/26B、异常 flags；三类 profile 的精确 opcode 序列；未知能力零 ingest/apply。既有 caps14/current、planner、wire、OLED 编码、Hook/XPC 定向与全量 Swift/Agent+App Release 不得回退。
- C1 不改 Studio View/Models/facade scoped assembler（归 C2），不改 Agent BLE lifecycle、Hook、WAL/XPC wire、安装器/签名 identity、固件仓或 HIL 环境。不签名/公证/安装/刷机/push。完成后停手提审，不自动进 C2。
- 需要回复：是（@Cursor ACK 后只执行 C1）
