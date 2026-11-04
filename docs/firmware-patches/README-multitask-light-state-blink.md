# 多任务灯珠状态变化闪烁：固件待集成补丁

这是一份可应用的源码补丁，**不是已发布固件，也没有替用户刷机**。基线为 `Fireware-harness@72346b001710d573980a7d398b9e0dced8ff627c`。客户端三会话模拟/临时预览已接入，实体灯珠需固件集成本补丁、完成目标构建和真机验收后才具备闪烁行为。

## 行为

- 原有0x99快照、四槽/每槽两个灯珠、进行中绿/等待黄/完成红均保留；无新协议、Flash写入或等待循环。
- 槽位由空变有效、或状态发生变化：对应两颗灯珠闪三次，每周期约600ms（250ms亮、350ms灭），随后保持状态色。
- 同值重复快照、重复选择多任务模式、仅foreground改变不重启闪烁，其他槽不受影响。
- 灯珠亮灭不改变会话valid/state、OLED选择、300秒过期时间或活动唤醒逻辑。空槽、模式切换、runtime清理、Quiet/Sleep和过期路径清除闪烁。
- 复用原50ms渲染事件，使用当前TMOS时钟做非阻塞计时。host测过32位无符号时钟回绕；真实目标SDK时钟/链接/RAM/功耗仍需构建与HIL确认。

## 为什么同时更新门禁

旧版CP1的PowerShell静态门禁明确含有“不出现blink_on”的限制，原实现常亮符合旧合同。本补丁是新增产品需求，随之把门禁更新为确认600ms状态变化渲染和TMOS时钟接线；不是绕过旧门禁来声称以前就应当闪烁。

## 应用及验证

先将固件工作区保持干净并检出上述精确基线（如目标分支已有额外修改，请由固件维护者审阅移植，勿强制覆盖）：

```sh
git apply --check /path/to/multitask-light-state-blink-72346b0.patch
git apply /path/to/multitask-light-state-blink-72346b0.patch
python3 tests/host/ai_presentation/run_task_led_blink.py
clang -std=c99 -Wall -Wextra -Werror \
  tests/host/ai_presentation/test_display_presentation.c \
  APP/services/display_presentation.c -o /tmp/ahakey-presentation-test
/tmp/ahakey-presentation-test
```

新runner从`APP/sub_main/main.c`提取真正的`task_render_multi_leds()`，链接真正的`display_presentation.c`，仅替代外设与时钟，并启用AddressSanitizer/UndefinedBehaviorSanitizer。测试包括实际颜色/熄灭、三次亮灭、重复快照与foreground变化、仅一槽变化、非法报文、空槽、Quiet/Sleep、单多模式往返、超时清理、计数回绕及再启动。应用后的文件已逐字节核对与拟议源码一致。

红灯证据：将新runner复制到未修改基线的相同测试目录，运行`python3 tests/host/ai_presentation/run_task_led_blink.py --baseline`，在300ms时仍常亮的断言失败。应用补丁后同一生产渲染函数测试通过；原有显示服务host测试也通过。

## 仍需固件方完成

1. 在当前实际集成分支移植并审阅：基线后续可能有并行改动，本补丁不能证明适用于未知新HEAD。
2. 使用真实WCH SDK/编译器完成生产TU、链接、项目全量门禁及更新后的PowerShell静态门禁。没有在Mac上伪造这些结果。
3. 核对目标RAM/栈和时钟。Apple clang host布局中显示服务状态从22增至40字节（+18字节），不等于CH582链接报告或整机RAM批准。
4. 维护新固件构建标识和发布清单，提供源码commit、HEX、SHA256及门禁结果。不要沿用旧F99D的产物摘要或将其标为已含本功能；如改变目录身份需同步客户端能力目录。
5. 真机验证三槽同时/单槽变化、重复报文不重闪、OLED不跳变、全局亮度/充电/低电量提示优先级、BLE断线/Quiet/Sleep/过期和功耗。通过后再移除客户端“实体闪烁需固件支持”的限制说明。

[host与应用验证回执](../validation/connect-talk-hil-2026-10-22/firmware-task-light-blink-patch-2026-11-04.json) · [客户端行为与候选](../ahastudio/multitask-light-preview-2026-11-04.md)
