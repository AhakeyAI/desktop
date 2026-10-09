# Mac F5 系统听写兜底技术草案（原默认 F5 方案留档）

> 2026-10-09 决策更新：本文件下文是此前“默认改 F5”方案的技术草案，已被 Consumer Voice 优先、F5 兜底的决策替代，不能直接当作固件实施指令。Consumer 须在目标 macOS 上实际触发系统听写并通过验收后才作为默认；失败时引导用户将系统听写快捷键设为 F5，同时将键盘 Voice 键切换为普通 F5 输出。已确认决策和待验证边界以 [跨设备交接](../handoff/CONNECT_AND_TALK_HANDOFF.md) 为准。初始计划/WBS 只覆盖 WS1/WS2 阶段，最终用户版还必须保留旧功能并完成 WS3。

日期：2026-10-09
收件方：X1 固件开发同事
用途：保留普通 F5 的 HID、设置引导和固件切换技术细节，供 Consumer Voice 验收失败后的兜底实现参考。下文曾按“选择 Mac 后默认 F5”写成请求；该默认策略已失效。

## 当前产品目标

当前决策：沿用已有的一次平台选择，Consumer Voice 经目标 macOS 实际听写验收后优先作为默认。未通过时提示用户开启听写并将快捷键设置为 F5，同时将设备 Voice 输出切为普通 F5。下面的“选择 Mac 后默认保存 F5”是先前方案的历史描述，不得作为当前默认实现要求。连接本身不自动开始听写或录音，换系统可手动重新选择/配置。

这属于“首次引导完成后即可使用”，不再要求在系统听写未配置时也零设置触发。基于这个明确前提，可以采用普通 Keyboard F5 `0x3E`；它仍不能与 Apple 麦克风键视为同一 HID 事件。

本次需要修改的部分是 Mac onboarding 默认 preset、K1 特殊覆盖逻辑和设备屏幕说明；现有普通键协议与显示框架可复用。旧 Consumer Voice 路径属于已有行为，迁移时不自动覆盖用户配置。

系统听写开关和首次系统确认仍受 macOS 控制，不能由固件绕过。测试时分别记录听写已开启与未开启的系统行为，明确“无需改快捷键”和“系统首次启用确认”是不同要求。

复核结论：现有固件已经支持普通 F5 绑定。通过 `0x73` 写入、`0x04` 保存、`0x87` 回读，并在必要时用 `0x96` suppress 退出 completed_mac Consumer 特殊分支，可形成不依赖 App 语音中转的 F5 路径。该结论来自源码，仍需 USB/BLE 与系统听写真机测试。下文取消把固件结构调整当成实现 F5 的必需条件；第 4 节改动仅针对无需上位机的默认 preset 和配置模型统一。

## 1. 普通 F5 方案和系统前提

F5 路径发标准键盘 F5，不经过 F18/F19 中转。用户可以通过上位机把该键改成其他系统/输入法快捷键；对于 completed_mac 特殊路径，需要先显式移交到普通绑定执行。是否改变固件新手引导的默认 preset 是独立的产品决定。

标准 F5 是 Keyboard/Keypad Usage Page `0x07`、Usage ID `0x3E`。它与 Apple 键盘上标在 F5 位置的麦克风/听写功能不能直接视为同一 HID 事件。

本次产品方案的前提是用户启用 macOS 听写，并把听写快捷键设为 F5。不能承诺“普通外接键盘 F5 在所有 Mac 上默认启动听写”；未设置匹配时，它可能被前台应用当作普通 F5 使用。

mac 上位机负责提供设置说明与触发测试，不默认改写系统设置，不默认拦截 F5，不要求新的 Runtime。Typeless/豆包等软件的快捷键需与用户选择的键盘绑定匹配；Fn 需要额外验证真实 HID 事件和目标软件支持，不能把普通键码随意标成 Fn。

## 2. 与现有实现的核心区别

必须区分三条链路：

```text
当前固件 Mac preset：K1 → 固件 Consumer Voice 0x0C/0x00CF → macOS
本次 F5 方案：K1 → 固件保存的普通键绑定 0x07/0x3E → macOS 中匹配的听写快捷键
旧客户端 App 语音：K1/F18 等触发键 → App 监听 → App 录音转写/文本整理/粘贴
```

前两条都由固件直接发送 HID，不需要新的 Runtime，也不需要 App 录音或 F18 中转。第三条服务于 App 自己转写、AhaType 整理或旧兼容方案，不能用它描述当前固件 Consumer preset。

| 比较项 | 当前固件 Mac preset | 本次 F5 方案 |
| --- | --- | --- |
| 发送内容 | Consumer Usage Page `0x0C`、Usage `0x00CF` | Keyboard Usage Page `0x07`、Usage `0x3E`，即普通 F5 |
| 执行入口 | completed_mac 条件下，K1 被特殊分支提前处理 | K1 从设备保存的普通绑定执行 |
| onboarding 的作用 | completed_mac 状态同时控制是否启用 Consumer 路径 | Mac 选择应用一次默认 F5；状态随后只记录引导结果，不持续覆盖键位 |
| 用户修改 K1 | 即使修改了普通绑定，特殊 Consumer 分支仍可能抢先执行 | 用户修改后的绑定成为实际执行依据 |
| `0x87` 读回 | 能读到普通存储绑定，但该绑定不一定是 K1 当前实际发送的 Consumer 行为 | 读回普通 F5/用户自定义绑定，与实际发出的普通动作对应 |
| `0x96 suppress` | 将 completed_mac 改为 suppressed_by_desktop，会关闭 Consumer 特殊路径，之后落回普通绑定 | 只改变引导状态，已保存的 F5/自定义动作仍有效 |
| 对 App 的依赖 | 固件 Consumer 路径本身不依赖 App 语音桥 | F5 系统听写路径也不依赖 App 语音桥 |
| Mac 端前提 | 依赖系统对 Consumer Voice 事件的实际支持；已有相应 Owner UAT | 用户需配置听写快捷键为 F5；普通 F5 不保证等同 Apple 麦克风键，必须重新做 UAT |

统一普通绑定执行的价值是让行为、用户配置和读回结果一致，减少隐藏状态覆盖，并便于用户选择其他快捷键。现有固件也可以由上位机通过明确的 suppress 接管达到 F5 配置目的，无需先重构固件。当前 Consumer 方案本身不依赖 App，也不能宣称普通 F5 比已验证的 Consumer 路径天然更通用。

代价是增加明确的 macOS 快捷键设置与验证步骤。若产品要求“用户完全不设置系统快捷键就能用”，不能直接把普通 F5 当作已经满足该目标；应重新评估实际 HID 事件方案。

## 3. 当前固件实现与修改入口

以查阅的 `Fireware-harness` 提交 `d1b46a14a796790f2ffe0d228e6c5badcfc34d75` 为参考：

- `APP/sub_main/main.c`：`voice_onboarding_complete(completed_mac)` 当前不修改普通键绑定。
- `APP/hardware/psk_multi_button.c`：K1 在 `voice_onboarding_mac_consumer_voice_active()` 为真时直接发 Consumer Usage `0x00CF`，提前返回，普通键的用户绑定不被执行。
- `voice_onboarding_mac_consumer_voice_active()` 当前依赖 onboarding 状态等于 `completed_mac`。
- Windows preset 当前为 Ctrl+Win；本次请求只修改 Mac，不顺带替换 Windows preset。若 Windows 目标也改为 Win+H，应单独作为已确认的平台 preset 变更。

请按实际开发分支调整入口，但不要只将特殊路径中的 `0x00CF` 替换成 `0x3E`：两者 usage page/report 类型不同，而且继续保留强制 K1 覆盖会使用户后续自定义无效。

### 利用现有协议的优先实现路线

1. 读取当前 K1 普通绑定及 `0x96` onboarding 状态，保留原值用于错误说明和草稿处理。
2. 用户明确选择 F5 时，用 `0x73` 写入目标模式 K1 的 `0x3E`，通过 `0x04` 保存，再用 `0x87` 比较真实存储结果。
3. 若当前为 completed_mac、Consumer 特殊分支仍在生效，再显式发送 `AA BB 96 03 CC DD` 并 query `0x96` 确认状态为 3。不要仅凭普通绑定读回 F5 就标为整体切换成功。
4. 保留普通绑定执行，在 AhaKey App 退出后验证实际 USB/BLE F5 事件，并在已配置 F5 听写快捷键的 macOS 上验证触发；检查长按是否重复及断线是否卡键。
5. 任一环节失败显示实际的部分结果，不自动宣称原配置已完全恢复。现有 `0x96` 仅允许桌面写状态 3，不能靠它一键写回 completed_mac=2；恢复原 Consumer preset 若需支持，另列接口需求。

因此，不改固件不会阻止经上位机配置后的 F5 方案；它只是保留“无上位机新手引导默认 Consumer Voice”和“completed_mac 特殊分支优先于普通绑定”的当前行为。首次选择 F5 需要明确接管，而非只改普通键码。

## 4. 本次首次引导所需的固件改动

以下是先前“Mac 引导后默认 F5”的固件改动草案，现仅供 F5 兜底实现参考。当前不要求所有 Mac onboarding 都默认改 F5；只在 Consumer 未通过验收、用户选择兜底时，明确同步切换系统快捷键设置指引与设备 Voice 实际输出。它们不需要新的 Runtime 或新的普通键命令。

### 首次屏幕引导流程

建议流程：连接就绪 → 选择 Mac → 保存 F5 preset → 显示设置说明 → 用户退出引导 → 用户按 Voice 测试。

屏幕说明至少包括“启用 macOS 听写”“把听写快捷键设为 F5”“设置后按 Voice 测试”。小屏可用短文本分步显示，如 `Enable Dictation`、`Shortcut: F5`、`Exit to test`；最终中文/英文排版沿用实际字体资源，不能承诺不存在的中文字库。

当前 `Try Voice` 页面约 3 秒内仍消费普通按键，所以必须先退出模态按键消费，再让 Voice 真正发送 F5。不能在一个吞掉 K1 的页面要求用户立即按 K1 测试。设置说明要有足够时间阅读，可继续查看或退出，不沿用仅 3 秒的提示作为完整设置教程。

固件可验证 preset 已保存，但不能获知 macOS 的听写开关和快捷键是否配置成功。界面应分别表达“键盘 F5 已配置”和“请在 Mac 设置并测试”，不要把系统听写标为自动验证完成。首轮验收由用户实际触发系统听写确认。

### A 将 F5 保存为可回读的普通绑定

Mac onboarding 确认或显式应用 Mac Voice preset 时，将 K1/Voice 的动作保存为标准键盘 F5，使用现有普通绑定与持久化路径。

按当前绑定格式，建议的存储表示为：

```text
action_type = 0x73
action_len  = 0x01
action_payload = 0x3E
内部绑定示意：73 01 3E
```

对应现有上位机写入示例（mode 使用 0..3 的协议值，K1 index 为 0）：

```text
AA BB 73 73 <mode> 00 3E CC DD
```

onboarding 内部应用 preset 应沿用保存及失败处理；上位机显式编辑仍按既有 `0x73/0x04/0x87` 契约写入、保存和读回。不能因本地设置了 `completed_mac` 就把未持久化的动作显示为已完成。

preset 的应用模式范围保持现有产品约定，不在本次顺带覆盖 Mode 4 或所有用户模式。新手引导应用默认值可以改变约定范围内的 K1；已配置设备不会因重连、读回或状态刷新反复重写。

### B 移除 Mac onboarding 对 K1 的隐藏覆盖

Mac preset 改为普通绑定后，K1 执行用户保存的动作。`completed_mac` 只记录 onboarding 结果，不再把 K1 强制路由到 Consumer `0x00CF`。

用户之后把 K1 改成另一快捷键、宏或 Disabled，应立即按新绑定执行，并在重启后保持。不要把“用户选择了 Mac”当成永久覆盖用户键位的依据。

Consumer HID 能力本身不要求全局删除；需要取消的是此 Mac preset 的强制 K1 分支，避免影响其他可能使用 Consumer report 的功能。

### C 明确按压与释放行为

Mac 系统听写 preset 按一次触发一次，发出完整 F5 key-down/key-up，不带 Ctrl/Alt/GUI 等修饰键。长按不应因重复事件连续启动/停止听写。

请根据现有普通键/宏执行方式实现该 preset 的一次点击语义，避免破坏普通快捷键的 hold 行为。用户改成其他动作后，应按该动作明确的触发语义执行。

断连、模式切换、关机等中断场景仍必须释放已按下键，不能造成 F5 或修饰键卡住。

### D suppress 只管理引导

`0x96` 的 Desktop suppress 仍用于停止初学者引导。修改后，onboarding 从 `completed_mac` 变为 `suppressed_by_desktop` 不应使已保存的 F5 消失，也不应恢复 F18 或另发 Consumer 事件。

普通绑定成为执行事实源后，上位机可通过现有绑定读写切换 F5 和其他快捷键，不必通过 `0x96` 写回 `completed_mac` 才恢复语音。

### E 旧配置迁移不覆盖用户数据

旧 completed_mac 设备的普通绑定可能仍是 F18，也可能被用户改过。不能仅凭状态为 completed_mac 就自动把其 K1 全部改成 F5。

建议：新 onboarding 使用 F5；已有设备通过明确的“应用 Mac F5 preset”动作切换，并在动作执行前告知将修改哪些模式的 K1。保留其他按键、宏、模式、OLED/GIF、灯光和配对数据。

## 5. mac 上位机配合

- 系统语音默认路径不启用 AhaKey 录音或按键转接，App 退出后仍可触发系统听写。
- 引导用户在“系统设置 → 键盘 → 听写”中启用听写并把快捷键设为 F5；操作时可直接按 AhaKey Voice 键录入真实触发键。
- 保存后用 `0x87` 确认 `action_type=0x73`、`action_len=1`、payload 为 `3E`，再用实际按键验证听写。
- App 自己转写、AhaType 整理以及旧设备兼容功能若保留，只由用户显式启用，不默认抢占系统或输入法的快捷键。

## 6. 验收清单

1. macOS 事件记录显示标准键盘 F5，不是 F18/F19，也不是同时发 Consumer Voice。
2. 退出 AhaKey Studio 及其语音桥后，USB 和 BLE 下都能按绑定发送 F5；配置系统听写快捷键后，Voice 键能触发系统听写。
3. 未配置系统听写 F5 时，上位机说明明确，不把普通 F5 发送成功误报为系统听写可用。
4. 一次按压仅一次触发，长按不重复切换；中断后无卡键。
5. `0x87`、实际 HID 事件与保存配置一致，重启后 F5 保持。
6. 将 K1 改成可用的其他快捷键后，真实执行及读回一致，completed_mac 不再强制覆盖它。
7. `0x96 suppress` 前后普通 Voice 绑定不变，不自动执行任何 Voice 动作。
8. K2/K3/K4、Power、Mode 4、Windows preset 及 OLED/灯光/配对行为没有本次修改引入的回退。

交付时请给变更提交号、HEX 哈希，以及 HID 事件和 `0x87` 的验证结果；不需要重新整理整套 Harness。

## 7. 当前可供固件对接的简短说明

我们沿用首次选 Mac/Windows 的引导，并先在目标 macOS 上验证现有 Consumer Voice 是否真正触发系统听写。通过后可保持 Consumer 默认；失败时提供明确的 F5 兜底：提示开启听写并将系统快捷键设为 F5，同时让设备 Voice 输出普通 Keyboard F5 `0x3E`。当前 `completed_mac` 会使 K1 Consumer 特殊分支抢先执行，所以仅保存普通 F5 绑定还不够；需通过现有 `0x96` suppress 明确移交执行路径，或在后续固件改动中提供等效且可验证的切换。旧用户其他键位和 Windows preset 不自动覆盖。设置说明要有足够阅读时间，测试前退出会吞键的引导页面。验证 USB/BLE 实际 HID、保存读回、重启保持和系统听写触发；当前接口不能承诺从 suppress 一键切回 Consumer。

## 8. 参考

- [Apple 听写和快捷键设置](https://support.apple.com/en-gb/guide/mac-help/mh40584/26/mac/26)
- [USB HID Usage Tables：Keyboard F5 为 0x3E](https://www.usb.org/sites/default/files/hut1_21_0.pdf)
- [当前固件 Mac onboarding](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/d1b46a14a796790f2ffe0d228e6c5badcfc34d75/APP/sub_main/main.c)
- [当前 K1 Consumer Voice 分支](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/d1b46a14a796790f2ffe0d228e6c5badcfc34d75/APP/hardware/psk_multi_button.c)
- [当前绑定读写与 suppress 命令](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/d1b46a14a796790f2ffe0d228e6c5badcfc34d75/APP/sub_main/command_solve.c)
