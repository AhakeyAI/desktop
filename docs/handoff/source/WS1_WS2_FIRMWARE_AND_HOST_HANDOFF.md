# WS1/WS2 固件改动与上位机配合交接说明

日期：2026-10-08

范围：

- WS1：X1 Connectivity & Power，最终接受到 CP3A。
- WS2：X1 Input & Control，最终接受到 CP4D。
- 最终 WS2 固件基线：`8167ba13049c781da2f975bc803eccfe0e6ea2aa`。
- 最终 WS2 HEX：`.ahakey-harness/evidence/builds/ws2-cp4d-ordinary-key-readback/HID_Keyboard_582m_vibe_coding.hex`。
- 最终 HEX SHA256：`6F9759EB912EC067564C4E63558589AB9732126344D52C2D2A278383119516BE`。

本文面向接手固件和上位机的同事，说明两件事：

1. 相较于原始 X1 固件框架，WS1/WS2 具体改了哪些东西。
2. 哪些改动必须由上位机一起配合，不能只看固件。

## 一句话总结

WS1 把原来分散在 BLE、USB、按键、电源、屏幕、灯效里的“设备生命周期”收拢成可判断的产品状态；WS2 在这个基础上补齐输入控制、模式同步、Voice 引导、侧边开关配置、固件身份识别和普通键只读回读协议。上位机需要把固件当成配置事实源，按固件读回结果更新 UI，而不是只维护本地草稿。

## 1. 相较于原始固件框架的主要改动

### 1.1 新增设备生命周期所有者

原始框架里，BLE 连接、USB 状态、按键、电源、屏幕、灯效各自直接影响用户看到的状态，容易出现“电脑显示已连接但键盘不能打字”“USB 已能打字但还在闪配对灯”“关机/待机/充电状态互相覆盖”等问题。

WS1 新增并接入：

- `APP/services/device_lifecycle.c`
- `APP/services/device_lifecycle.h`

它把用户旅程抽象成固件内部 phase，例如：

- `SEEKING_HOST`
- `WAITING_RECONNECT`
- `LINK_UP_GETTING_READY`
- `HID_READY`
- `JUST_DISCONNECTED`
- `QUIET`
- `SLEEP`
- `SHUTDOWN_PENDING`
- `USB_POWERED_OFF`
- `FORGETTING_HOSTS`
- `POST_FORGET_GUIDANCE`

核心变化：

- BLE link 和 BLE HID ready 仍由 `connectivity_link` 作为事实源。
- `device_lifecycle` 不重新拥有 BLE 事实，只根据 BLE/USB/按键/电源事实推导产品状态。
- 屏幕和灯效不再应该各自猜用户状态，而是消费生命周期状态。

### 1.2 新增稳定身份与忘记电脑封装

新增：

- `APP/services/connectivity_identity.c`
- `APP/services/connectivity_identity.h`

原始固件的忘记电脑路径曾经倾向于通过 BLE 地址偏移、清名称、重启等方式绕开主机旧配对问题。WS1 改成：

- Forget Computer 只清本机保存的配对记录。
- 保留 BLE 名称和身份。
- 保留按键配置、GIF、图片、模式等用户数据。
- 不再用 `mac_offset + 1` 作为默认方案。
- 忘记后进入引导重新配对，而不是做等同恢复出厂的动作。

这对上位机含义很重要：Forget Computer 不是 Restore Factory，也不是清空用户配置。

### 1.3 新增电源生命周期封装

新增：

- `APP/services/power_lifecycle.c`
- `APP/services/power_lifecycle.h`

主要改动：

- Power 键短按仍用于模式切换。
- Power 长按到阈值后执行关机；提前松手取消。
- 单独长按 Power 不再触发忘记电脑。
- 忘记电脑必须是关机/红灯语境下的 Power + Key3 路径。
- USB 插着时的关机进入 fake-off/充电中状态，不应被任意按键直接恢复成正常工作。
- Quiet/Sleep 是“显示/交互层面的安静或睡眠状态”，不是简单等同 MCU 深睡。

### 1.4 新增待机时间配置所有者

新增：

- `APP/services/standby_config.c`
- `APP/services/standby_config.h`

WS1 CP3A 把上位机可配置的 sleep wait time 正式收敛到 `0x95`：

- 支持值：`0`、`30`、`60`、`120` 分钟。
- `0` 表示不因空闲自动进入 Quiet/Sleep。
- `0x95` set 是自持久化命令，固件必须更新运行值、刷新计时、写入 EEPROM/Flash 后才返回 OK。
- 上位机不需要也不应该再为这个设置额外发送 `0x04 save_config`。
- `0x86` 从这个用途里退役，不应作为睡眠时间别名继续存在。

### 1.5 修正 Power 键误走普通按键路径

原始框架里 Power 键同时挂到了普通按键回调和电源回调，Power index 可能被普通键逻辑夹到 K4，造成 Power 键误触发普通 HID/macro 的风险。

WS2 CP1 修正方向：

- Power 仍保留 WS1 电源生命周期行为。
- Power 不再作为普通可配置键进入 K1-K4 的 HID/macro dispatch。
- 原来普通按键路径里对本地活动、亮屏、刷新 idle timeout 的副作用需要保留或迁移。

### 1.6 普通键短按/长按安全基础

WS2 CP2 建立普通键 short/long 的基础：

- K1-K4 支持 short slot 和 long slot。
- factory 默认 short/long 镜像同一个动作时，表现仍像原始普通按键，无长按延迟。
- short/long 不同时，短按释放触发 short，越过阈值触发 long 并抑制 short。
- long 支持 `one_shot` 和 `hold_until_release`。
- 默认长按阈值为 500ms。
- 模式切换、断连、关机、Reset/Restore、timeout 等场景必须 force-release 活跃 hold 动作。

### 1.7 固件身份与能力识别

WS2 CP3 新增固件目录 key：

- 命令：`0x9F`
- 请求：`AA BB 9F CC DD`
- 成功响应：`AA BB 9F 00 <ASCII catalog key> CC DD`
- 当前 key：`x1-c582-hw1-p1-1.0.0-r001`

目的：

- 上位机不再只靠旧 `0x00` status 里的 main/sub version 判断能力。
- `p1` 表示当前协议/能力 profile 仍保持旧桌面支持的兼容基础。
- 新上位机可以根据 catalog key 决定哪些 UI 功能可用。
- 旧固件没有 `0x9F` 时，上位机退回 legacy version 兼容模式。

BLE 侧曾修过 `0x9F` 长响应问题：BLE 默认 notify 20 字节装不下完整 catalog key，所以固件支持把 BLE `0x9F` 响应拆成多个 notify，直到上位机重组成完整 `AA BB ... CC DD` 帧。

### 1.8 模式同步与状态显示

WS2 CP4A 采用现有命令，不新增命令号：

- `0x00`：状态查询，包含当前 mode、battery、side switch 等状态。
- `0x92`：上位机设置当前 mode。

改动要点：

- 键盘是当前 mode 的事实源。
- 上位机发 `0x92` 后，必须等待 OK，并再用 `0x00` 读回确认 mode 已变更。
- 如果 ACK 失败、读回失败、超时或读回不是目标 mode，上位机 UI 要回到键盘事实源状态。
- 成功的上位机 mode 切换是真实当前模式，后续重启应恢复。
- 断开时，上位机可以本地浏览/编辑草稿，但不能假装已经写入键盘。

固件显示也做了适配：

- mode summary 显示四个键的用户可读 label。
- 状态显示包含电量、充电、连接状态。
- 第一版允许使用 ASCII/短 label，例如 `BT OK`、`USB OK`、`Charge`、`Recon`、`Pair`、`Sleep`、`Quiet`。

### 1.9 Voice onboarding / 快速引导

WS2 CP4B 增加无上位机场景下的 Voice 快速引导：

- 只在 `BT OK` 或 `USB OK` 且 onboarding state 未设置时出现。
- 流程：先问 `Mac?`，拒绝后问 `Win?`。
- check 确认，cross 拒绝/进入下一步/退出。
- onboarding 可见时，除 check/cross 外其他键都被消费，不发送 HID/macro。
- 完成后显示 `Try Voice` 约 3 秒，不自动触发 Voice。
- 5 分钟超时只退出本次显示，不写入 preset，也不永久拒绝。
- 上位机进入 AhaKey 配置流程后，可通过 `0x96` suppress beginner onboarding。

持久化：

- onboarding state 存在 `key_bund_s` 中，走原有 EEPROM 路径。
- 状态包括 `unset`、`completed_windows`、`completed_mac`、`suppressed_by_desktop`、`declined_by_user`。

Voice 动作：

- Windows preset：`Ctrl + Win`，走普通键 `0x73` shortcut/modifier 路径，`hold_until_release`。
- Mac preset：最终选择 Owner 实测通过的 Consumer Voice Command，Usage Page `0x0C`，Usage `0x00CF`，映射到 K1/Voice，单次 press/release toggle。
- 为了 Mac 真实设备验证，阶段中曾做过四键诊断，但最终产品不能保留 K2/K3/K4 的诊断劫持。

HID 层也因此做过 Windows/Mac 兼容修正：

- Windows 不能接受 malformed top-level Consumer descriptor。
- Mac 需要 descriptor-clean Consumer Control array + 实际 report value `0x00CF`。
- 最终要同时保留 Windows `Ctrl+Win` 和 Mac Consumer Voice Command 路径。

### 1.10 侧边开关配置

WS2 CP4C 增加 side switch 配置，命令号：

- `0x97`

产品语义：

- 上 = `sw_state 0` / Auto。
- 下 = `sw_state 1` / Manual。
- `sw_state 2` = unknown / mid / abnormal / transitional，不触发策略或动作。

每个位置有一种 binding type：

- Factory Auto。
- Factory Manual。
- Custom Shortcut/Macro。
- Disabled/None。

核心变化：

- factory Auto/Manual 是上位机/AI 工作流的策略输入，固件只报告，不直接发 HID/macro。
- Custom Shortcut/Macro 由固件执行，但只在真实物理拨动进入该位置时触发一次。
- boot、reconnect、readback、post-save sync、restore/rebaseline 都只能建立事实或同步，不能触发动作。
- 新增 action gate 概念：`running_data.sw_state` 仍是物理事实；是否允许触发 custom action 由独立 gate 决定。
- 配置需要固件持久化，并由上位机读回确认。

### 1.11 普通键只读回读

WS2 CP4D 增加普通键配置只读回读命令：

- `0x87`

请求：

```text
AA BB 87 mode key_index CC DD
```

成功响应：

```text
AA BB 87 00 mode key_index action_type action_len action_payload desc_len desc_payload CC DD
```

错误：

- `AA BB 87 01 CC DD`：payload 格式错误。
- `AA BB 87 02 CC DD`：mode 或 key_index 越界。
- `AA BB 87 03 CC DD`：真实 action + description 放不进单个 64-byte HID report。

约束：

- 只读一个 mode + key_index。
- `key_index` 只允许 K1-K4，Power 不可寻址。
- 只读 `key_bund.user_key_bind` 和 `key_bund.user_key_desc`。
- 不写入、不持久化、不执行 HID/macro。
- 成功帧必须完整放入一个 64-byte HID report，不做 USB/BLE 分片。
- 返回真实 action length 和裁剪后的 description length，不返回固定 100/20 字节 padding。

### 1.12 测试与构建框架补充

WS1/WS2 新增了较多 host-side tests，用于固化行为：

- `tests/host/device_lifecycle/`
- `tests/host/power_lifecycle/`
- `tests/host/standby_config/`
- `tests/host/input_control/`
- `tests/host/profile_gap_policy/`
- `tests/host/diagnostic_observability/`

生产构建脚本也被 Harness 化：

- `tools/harness/build-x1-production.ps1`

这些测试不是上位机要运行的正式交付物，但它们说明哪些行为不能被后续改动打破。

## 2. 需要上位机配合的改动

### 2.1 上位机必须把键盘固件当作配置事实源

WS2 的整体原则是：

- 上位机可以有草稿。
- 但当前生效配置以键盘固件读回为准。
- Save/Apply 后必须读回确认。
- 读回失败时，不能把本地草稿当成已应用。

具体 UI 行为：

- 连接/重连后先读键盘配置，再开放高级编辑。
- 读不到时，基础键盘输入仍可用，但高级编辑和保存要 fail-closed。
- 上位机可显示 last-known cache，但必须标注为未验证/只读参考。
- 保存失败或读回不一致时，保留草稿供重试/编辑/丢弃，但不能改变“键盘实际行为”的显示判断。

### 2.2 `0x95` sleep wait time

上位机要配合：

- 提供 sleep wait time 选项：`0`、`30`、`60`、`120` 分钟。
- 用 `0x95` query 读取当前值。
- 用 `0x95` set 写入当前值。
- 写入成功后再 `0x95` query 确认。
- 不再为这个设置发送 `0x04 save_config`。
- 不再使用 `0x86` 作为睡眠时间命令。

固件语义：

- `0` = 不因空闲进入 Quiet/Sleep。
- 非法值返回错误，保持旧值。
- 保存失败返回错误，不能显示保存成功。

### 2.3 `0x9F` firmware catalog key

上位机要配合：

- 连接后优先尝试 `AA BB 9F CC DD`。
- 成功后解析 ASCII catalog key，例如 `x1-c582-hw1-p1-1.0.0-r001`。
- 用 catalog key 决定功能可用性、固件身份、硬件目标、协议 profile。
- `0x9F` 失败时，再 fallback 到旧 `0x00` status 里的 firmware main/sub。
- BLE 下要支持多 notify 拼包，直到收到完整 `AA BB ... CC DD`。

不要做：

- 不要把上位机 app version 当成键盘固件版本。
- 不要对未知新固件盲目开放未知写入能力。
- 不要因为 catalog key 未识别就认为所有旧功能不可用；同 product/hardware/profile 下可保留已知安全功能。

### 2.4 `0x00` / `0x92` mode sync

上位机要配合：

- 用 `0x00` 读取键盘当前 mode。
- 用 `0x92` 设置键盘当前 mode。
- `0x92` 成功后必须再用 `0x00` 读回确认。
- 读回不一致时，UI 回到键盘事实源 mode，并提示失败/可重试。
- 断线状态下可以本地浏览或编辑草稿，但不能 replay 离线 mode click。
- 断线重连后先读键盘事实源，再处理草稿冲突。

### 2.5 `0x96` Voice onboarding state / suppress

上位机要配合：

- 进入正式 AhaKey 配置流程后，发送 `0x96` suppress，避免已经用上位机配置的用户再被键盘弹出 `Mac?` / `Win?` 新手引导。
- 可用 `0x96` query 读取 onboarding state，用于设备信息/诊断。
- 不要把 `0x96` 扩展成通用配置写命令。

固件侧当前语义：

- `0x96` 只处理 Voice onboarding state query 和 Desktop suppress。
- Restore Factory 以后应把 onboarding state 重置为 `unset`，但 Restore Factory 不属于 WS2 已实现范围。

上位机引导内容也要配合：

- Windows 路线说明 `Ctrl + Win` / WeChat 或系统语音输入前置条件。
- Mac 路线说明 K1/Voice 触发 Consumer Voice Command 的预期行为。
- 说明键盘上的 `Mac?` / `Win?` 是没有上位机时的快速引导，不是永久绑定策略。

### 2.6 `0x97` side-switch configuration

上位机要配合：

- 读写两档 side switch 配置。
- 每档支持四种类型：Factory Auto、Factory Manual、Custom Shortcut/Macro、Disabled/None。
- Save/Apply 后必须固件持久化并读回一致后才算成功。
- 如果用户只自定义一边，另一边默认 Disabled/None，除非用户明确设回 Factory Auto/Manual。
- 显示 `sw_state 2` 时要当成 unknown/mid/abnormal/transitional，不要触发策略或动作。

上位机工作流语义：

- Factory Auto/Manual 是上位机/AI workflow 的策略输入。
- 固件不会替 Factory Auto/Manual 发 HID/macro。
- Custom Shortcut/Macro 是固件执行的一次性动作，只在真实物理拨动时触发。
- boot/reconnect/readback/post-save sync 时不应该看到动作触发。

### 2.7 `0x87` ordinary-key readback

上位机要配合：

- 用 `0x87` 逐个读取 K1-K4 的当前配置。
- 一次只读一个 mode + key_index。
- 按真实 action_len 和 desc_len 解析，不要假设固定 100/20 字节 padding。
- 如果收到 `0x87 03`，说明该 key 的真实内容放不进单个 64-byte report；上位机应该 fail-closed，而不是猜测或截断显示。
- `0x87` 是只读，不代表写入协议已经完成。

典型用途：

- 上位机启动/重连后读取键盘事实源普通键配置。
- 和本地草稿/缓存比较，提示冲突。
- 为后续写入协议做 UI baseline，但 WS2 不实现普通键写入新协议。

### 2.8 Voice / Mac / Windows HID 配合

上位机和产品文档要知道：

- Windows quick-start 是 `Ctrl + Win`，按住 Voice 时 hold，松开 release。
- Mac quick-start 最终是 Consumer Voice Command `0x0C/0x00CF`，K1/Voice 单次 press/release。
- 早期四键 Mac diagnostic 只是验证过程，不能作为最终产品交互暴露给用户。
- 若用户反馈 Mac/Windows Voice 不工作，要区分：
  - 固件 preset 是否完成；
  - host OS 是否支持对应快捷键；
  - App/WeChat/系统语音输入是否已满足前置条件；
  - HID descriptor 是否被系统正确识别。

### 2.9 Restore Factory 尚未在 WS2 实现

上位机不要误认为 WS2 已经完成 Restore Factory。

WS2 最终决定：

- CP5 / Restore Factory 已明确延期到 WS4/WS5。
- WS2 不进入 Restore Factory BUILD。
- Restore Factory 未来需要连同 Host Protocol、持久化、release、资源、reset/recovery 边界一起重新设计。

未来 Restore Factory 应重置：

- 四模式绑定/宏。
- short/long slot。
- labels。
- side-switch config。
- global long threshold。
- standby time。
- Voice onboarding state。
- Desktop-writable LCD/light settings。

但不应清 BLE pairing records，除非未来 Owner 决策改变。

## 3. 模块级改动索引

### 新增/重点改动固件模块

| 模块 | 作用 | 上位机是否要感知 |
| --- | --- | --- |
| `APP/services/device_lifecycle.*` | 设备生命周期状态、连接/待机/关机/忘记电脑状态推导 | 间接感知，通过状态显示和行为 |
| `APP/services/connectivity_identity.*` | 稳定身份、配对记录、Forget Computer 封装 | 需要理解 Forget 不等于恢复出厂 |
| `APP/services/power_lifecycle.*` | true-off、fake-off、显示 blank、sleep/wake 执行状态 | 间接感知 |
| `APP/services/standby_config.*` | sleep wait time 合法值、读写、持久化语义 | 需要通过 `0x95` 配合 |
| `APP/sub_main/command_solve.c` | `0x87/0x92/0x95/0x96/0x97/0x9F` 等协议处理 | 需要重点对齐 |
| `APP/hardware/psk_multi_button.c` | Power/普通键/模式显示/Voice onboarding/side-switch 触发链路 | 需要理解物理键行为 |
| `APP/hid_dev/psk_hid.c` / `Profile/hiddev.c` / `Profile/hidkbdservice.c` | USB/BLE HID、Consumer report、BLE notify 长包支持 | Voice 和 BLE 读回需要配合 |
| `APP/sub_main/main.c` | 主事件循环、生命周期接入、power/USB/idle/display 桥接 | 上位机不直接感知，但影响所有行为 |

### 新增/重点协议命令

| 命令 | 方向 | 是否 WS1/WS2 已接受 | 用途 |
| --- | --- | --- | --- |
| `0x00` | 上位机读 | 已有，WS2 正式采用 | status / mode / side switch 等事实读回 |
| `0x87` | 上位机读 | WS2 CP4D 接受 | 普通键 K1-K4 单键只读回读 |
| `0x92` | 上位机写 | 已有，WS2 CP4A 约束采用 | 设置当前 mode |
| `0x95` | 上位机读写 | WS1 CP3A 接受 | sleep wait time query/set，自持久化 |
| `0x96` | 上位机读写窄口 | WS2 CP4B 接受 | Voice onboarding state query / Desktop suppress |
| `0x97` | 上位机读写 | WS2 CP4C 接受 | side-switch configuration |
| `0x9F` | 上位机读 | WS2 CP3 接受 | firmware catalog key |

## 4. 不要误解的边界

- WS1/WS2 没有做 clean-room rewrite；大量原始路径是复用、包裹或迁移。
- WS1/WS2 没有完成 Restore Factory。
- WS1/WS2 没有完成完整 Host Protocol。
- WS1/WS2 没有完成固件升级、候选固件列表、回滚、恢复流程。
- WS2 的 `0x87` 是只读，不是普通键写入协议。
- WS2 的 `0x97` 是侧边开关配置，不是通用动作系统。
- WS2 的 `0x96` 是 Voice onboarding，不是 Restore Factory，也不是 side-switch。
- WS3 的 AI/task presentation 命令 `0x98/0x99/0x9A` 不属于 WS2 最终交接范围。

## 5. 建议给上位机同事的对接优先级

1. 先实现固件识别：`0x9F`，BLE 多包重组，fallback 到 `0x00` legacy version。
2. 再实现事实源读取：`0x00` status、`0x87` 普通键 readback、`0x97` side-switch readback、`0x95` standby readback、`0x96` onboarding state。
3. 再开放写入 UI：`0x92` mode set、`0x95` standby set、`0x96` suppress、`0x97` side-switch config。
4. 每个写入都必须 ACK + readback 确认，不要只看本地发送成功。
5. Restore Factory、普通键写入新协议、完整 Host Protocol、固件升级/恢复留到 WS4/WS5。

## 6. 交接检查清单

交给接手同事时，至少确认他知道：

- 最终基线是 WS2 CP4D commit `8167ba13049c781da2f975bc803eccfe0e6ea2aa`。
- 最终可烧录 HEX 是 `ws2-cp4d-ordinary-key-readback` 目录下的 HEX。
- 上位机要以固件读回为事实源。
- `0x95` 不再依赖 `0x04 save_config`。
- `0x9F` 是新的固件身份能力入口，BLE 可能多包。
- `0x92` 设置 mode 后必须 `0x00` 读回确认。
- `0x96` 只做 Voice onboarding state/suppress。
- `0x97` 只做 side-switch config。
- `0x87` 只做普通键单键 readback。
- Restore Factory 还没实现，不要在上位机 UI 里当成已可用功能。

