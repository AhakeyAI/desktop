# 固件协作问题提醒清单

日期：2026-10-09。配套 [跨设备交接](./CONNECT_AND_TALK_HANDOFF.md)。这是一份问题和验收提醒，不是已经冻结的固件实施指令；无需重新整理 Harness 已有的命令表、HEX 和验收文档。

| 编号 | 事项与事实依据 | 当前决定 / 下一步 | 是否阻塞常用 mac 功能开发 |
| --- | --- | --- | --- |
| F01 | 旧客户端允许宏最多 98 字节/49 步；CP4D 0x87 限制 action+description<=53 字节，超长返回 0x87 03 | 用户要求记录后统一提醒固件方；研究长宏完整回读方案，不截断、不误报成功。正式版未验证写入边界仍待定 | 否 |
| F02 | 当前 Mac 发 Consumer Voice 0x0C/0x00CF，Windows 是 Ctrl+Win。Consumer 事件不是普通 F5，也不是已公开保证的系统听写 API | 先确认最终 Mac 默认路线；保持默认设置、关闭 AhaKey App，在目标 macOS 系统听写中验收。不要用微信场景通过替代该检查 | 不挡协议/只读开发，影响语音发布验收 |
| F03 | 若采用键盘 Mac 选择后存普通 F5：当前 Mac onboarding 没写 F5，completed_mac 特殊分支仍抢先处理 K1 | 需要小范围 preset/执行事实源修改；0x87 读回与实际 HID 一致；不自动覆盖已有用户配置。这是候选方案，不先下令修改 | 不挡其他功能 |
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
