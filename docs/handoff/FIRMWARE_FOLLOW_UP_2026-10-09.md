# 固件协作问题提醒清单

日期：2026-10-09。配套 [跨设备交接](./CONNECT_AND_TALK_HANDOFF.md)。这是一份问题和验收提醒，不是已经冻结的固件实施指令；无需重新整理 Harness 已有的命令表、HEX 和验收文档。

| 编号 | 事项与事实依据 | 当前决定 / 下一步 | 是否阻塞常用 mac 功能开发 |
| --- | --- | --- | --- |
| F01 | 旧客户端允许宏最多 98 字节/49 步；CP4D 0x87 限制 action+description<=53 字节，超长返回 0x87 03 | 用户要求记录后统一提醒固件方；研究长宏完整回读方案，不截断、不误报成功。正式版未验证写入边界仍待定 | 否 |
| F02 | 当前 Mac 发 Consumer Voice 0x0C/0x00CF，Windows 是 Ctrl+Win。Consumer 事件不是普通 F5，也不是已公开保证的系统听写 API | Consumer 优先，但须保持默认设置、关闭 AhaKey App，在目标 macOS 系统听写中实际验收后才作为默认；失败时转 F5 引导。不要用微信场景通过替代该检查 | 不挡协议/只读开发，影响语音发布验收 |
| F03 | F5 兜底需同时配置 macOS 听写快捷键和键盘 Voice 普通 F5 输出；当前 completed_mac 特殊分支仍抢先处理 K1 | 提供明确切换入口、保存及读回检查，并验证实际 HID 和听写；不自动覆盖已有用户配置。无需为了测试 F5 先重构固件 | 不挡其他功能 |
| F04 | 当前 Try Voice 页约 3 秒内吞掉普通键；0x96 只能由桌面写 suppress=3，不能写回 completed_mac=2 | 设置指引要足够可读，先退出模态吞键再测试。若需可逆切回 Consumer，补足接口或明确产品限制 | 不挡其他功能 |
| F05 | 对方表示存储失败会有上位机提示；mac 尚未实现对应提示。0x95 自持久化，不追加 0x04 | 实现拒绝/超时/读回不一致反馈，保留草稿，重启验证持久化。具体 EEPROM 故障能否检测按联调结果记录，不把旧静态源码疑点直接判作固件缺陷 | 否，属于写入验收 |
| F06 | WS3 CP1 曾接受，但查阅 project-state 仍要求重新应用到 CP4D 基线；CP2/CP3 涉及显示资源布局/保存事务/恢复 | 进入 WS3 前读取最新源和 HEX；最终用户版必须完整完成 WS3。不可只凭旧 checkpoint PASS 推断当前构建功能 | 不挡 WS1/WS2 阶段，影响最终完整发布 |
| F07 | OLED/灯光仍在调整，WS4/WS5 新版本目录/恢复治理未完成 | 开发阶段允许只读，正式版保留旧功能；新增功能可后发。旧手动烧录的校验、失败恢复和可用固件安全不能省略 | 不挡第一阶段 |

## 给固件同学的简短说明

> mac 端先使用 Harness 的 WS1/WS2 基线开发，不需要你重写已有文档。这里记录的是接下来要验证或统一处理的边界：长宏读回容量、Mac 默认语音路线及实际 HID 验收、引导吞键和可逆接管、保存失败与持久化反馈，以及 WS3 最新候选的实际集成状态。先不为每个提醒新增协议；常用功能继续推进，语音路线冻结和 WS3 对接时再逐项收口。

## 参考

- [WS2 Architecture](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/d1b46a14a796790f2ffe0d228e6c5badcfc34d75/.ahakey-harness/workstreams/X1-INPUT-CONTROL/ARCHITECTURE.md)
- [命令实现](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/d1b46a14a796790f2ffe0d228e6c5badcfc34d75/APP/sub_main/command_solve.c)
- [Mac onboarding 与状态](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/d1b46a14a796790f2ffe0d228e6c5badcfc34d75/APP/sub_main/main.c)
- [K1 与普通键执行](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/d1b46a14a796790f2ffe0d228e6c5badcfc34d75/APP/hardware/psk_multi_button.c)
- [Harness 阶段状态](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/d1b46a14a796790f2ffe0d228e6c5badcfc34d75/.ahakey-harness/project-state.yaml)
- [Apple HID Voice Command 定义](https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/IOHIDFamily/IOHIDUsageTables.h)
- [USB HID Usage Tables](https://www.usb.org/sites/default/files/hut1_3_0.pdf)
- [Apple 系统听写与快捷键](https://support.apple.com/en-gb/guide/mac-help/mh40584/26/mac/26)


## 2026-10-13 新增：HID 释放发送失败可能丢失（待固件侧验证）

状态：静态代码确认存在发送状态未处理的缺口；未确认是本次 Command 卡住的根因，不应标为已修复。

真机：Mac 26.3.1，CH582，WS2 CP4D HEX SHA256 `6f9759eb912ec067564c4e63558589ab9732126344d52c2d2a278383119516be`，保留历史 DataFlash。用户首次仅操作 Voice 后反馈 Dock 点击显示目录；探针捕获左 Command 在 combined/HID 两层按住。键盘关机后释放，App 退出后重连不按键正常；之后 App 退出及旧 App 运行时重复短按均正常。一次按住 Voice 的原始 Consumer CF=1/0 间隔 3.360623 秒，唤起 Siri但 Dock 正常。后测未再捕获 Command 卡住，不能归因于单一模块。

代码依据（`Fireware-harness` 头 `d1b46a14a796790f2ffe0d228e6c5badcfc34d75`）：

- `APP/hid_dev/keyboard.c:378–395`：Consumer 按下/释放经 `keyboard_send_usage_report` 单次调用无返回值的发送封装，没有释放发送失败重试。
- `APP/hid_dev/psk_hid.c:432–450`：`MY_USB_HID_SEND_REPORT` 不检查 `HidDev_Report` 返回值。
- `Profile/hiddev.c:1236–1289`：底层通知可能因资源、分配、未就绪等原因返回失败；此路径没有上层重试。
- `APP/hid_dev/keyboard.c:106–109`：普通键报告在发送前更新 `tkeyboard_buff_last`；若底层发送失败，后续去重可能阻止相同释放报告再次发送。

请固件方补强并给出验证结果：

1. 向上层传递实际发送状态；普通键“已发送”缓存仅在发送被成功接受后更新（不把接受发送等同于主机应用处理完成）。
2. 为 Consumer/普通键 release 保留待发送状态和有界重试，保持按下/释放顺序；安全时丢弃断线前旧按下，重连/模式切换/关机路径确认中性报告。不得无条件重放旧按下或打断仍合法保持的按键。
3. 用故障注入分别使 keyDown、keyUp 的通知分配/发送失败，验证恢复后最终报告为中性且没有重复动作，覆盖普通修饰键和 Consumer。
4. 同步抓取 HID 原始 Cmd/Consumer 与系统修饰键状态；只有异常现场证据能确定固件漏释放还是系统映射问题。
5. 产品行为另行确认：当前目标 Mac 的 Consumer Voice 轻点启动听写，按住会启动 Siri。若只允许听写，需设计固定短脉冲与防重复策略，再做系统兼容验收；它不能替代上述释放可靠性修复。

本次未改固件/客户端输入实现，也没有再次烧录。原始设备日志和配置备份仅本地保存，不放入仓库。

## 2026-10-21 新增：Mac 取消配置连接后上传 owner 可能仍在

CP2/HEX ffb9208f真机：位置18上传一帧，UI15/598块时取消，线日志总30块后停止，无Commit/8D/04/8E。Mac仍保留HID物理连接，配置重连后83及9F返回status1；正常关开键盘后19项查询恢复、素材显示不可用并按固件回退，能显式恢复默认。新客户端已补跨重连保留取消恢复提示；三帧UI26/1792处取消也确认提示保留。

已接受CP2合同允许这种物理链路未释放的边界，mac当前用停止发送、撤回快照/写权限、提示正常重启并重新读取处理。若后续希望取消无需重启键盘，请固件方评估：有界事务空闲释放或专用owner-scoped取消、释放失败时状态可观测、物理HID连接继续保持时的恢复路径；先在Harness冻结合同并验证跨owner/迟到包，mac再接入。0x8D仍是清空资源，不能复用为abort。此项记录为后续协作提醒，不是本轮擅自修改固件或已承诺新协议。
