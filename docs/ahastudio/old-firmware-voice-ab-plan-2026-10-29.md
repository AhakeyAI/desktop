# 旧固件Voice对照：固定测试链路

Owner要求刷回旧版复现Consumer听写/Siri问题。选择实际历史包X1_MEMORY_FIX_20261018.hex（10月19日已刷/Verify OK），而非更新的292a49f组合或客户端内置1.4.6：完整SHA256 ffb9208f79084aa24a832ad2562a14dbbea5df4d114a135cb5b2eb98d4e05539。原git blob e72b550c3e943075ddbfd09272e2aec5b5c1378a已从本地对象恢复，与既有接受记录一致；生产HEX校验及独立逐记录/EOF/地址校验通过，458492加载字节，最高0x6fefb。

## 降级准备

build521升级窗口已明确显示旧文件完整SHA。当前07A8固件16键、60分钟待机、两档绑定、36灯效、35%亮度、19素材元数据和本地14项草稿/Voice偏好已备份，原始数据仅私有本机保存。19项均未报告有效自定义资源；素材像素仍不可导出，不宣称完整像素备份。另保留本轮重启后完整四模式Consumer记录。

本次降级会清DataFlash；旧固件不能表达新逐模式路由记录，因此不向旧版盲目回放0x9E或整份新配置。已请Owner确认本次清除，并先拔USB/关机/保持既有BOOT-GND操作、暂不插USB；确认后才开启180秒等待，再通知插线。Owner随后明确确认本次清除。安装版Studio点击最终确认时已检测到CH582，32个DataFlash扇区和448个CodeFlash扇区擦除，458752字节写入，Verify OK及工具自动复位均在原UI记录核对。未重复刷写，也未将上次07A8同意代替本次。

## 已取得的源码差异证据

旧接受源70ca334的psk_multi_button.c:370在全局MacConsumer有效时，PRESS_DOWN/UP直接发送CF按下/松开。新ed426c9在271行加入按模式捕获路由，旧fallback455行仍透传。两者均未在这条语音路径提供固定短脉冲。

实际逐函数原始字节比较：keyboard_send_usage_report、keyboard_press_consumer_usage_1、MY_USB_HID_SEND_REPORT三个函数完全相同，哈希见准备回执。仅证明这三个函数没有改，不证明整个输入时序/BLE堆栈/固件行为完全相同，也不预判新旧实测结果。

## 实物A/B控制变量

- 同一Mac26.3.1、同一键盘与蓝牙链路，保持系统听写/Siri/快捷键设置；不启用暂缓的F5替代。
- 旧版首次开机若平台选择则选Mac，等引导结束；只读确认onboarding=2/Consumer启用。新版本基线已实读四路由Consumer CF。若旧版读出普通右Alt/F18等，先识别真实路线，不拿普通键桥接与Consumer混比。
- 固定Codex模式，保持当前按键未被客户端草稿自动写回；先将Studio完全退出，只保留必要连接管理，确认Consumer仍由键盘直发。再按需做App运行对照，避免同时更换固件与语音链路。
- 同一只读原始HID过滤器仅记录CF及Command。分别标记快速轻点、正常速度按下/松开、较慢按下与保持，再观察“开始/停止听写”和Siri结果；按键松开后核对中性值。物理持续时间以原始事件相关性为证，不把主观“短按”强制解释为某个时长。
- 每次出现异常停止按键先读状态；必要时再安排正常关开。不把监视器截止时开放按键当已证实卡键，也不为采样注入Siri/Consumer或制造假HID。

当前新固件功能FAIL仍开放；旧版已经写入并Verify OK，等待Owner拔USB/移除BOOT短接/正常无线开机选Mac，尚未进行旧版Consumer输入验收。本文件是受控对照计划，不是旧版通过回执。[准备与源码比较回执](../validation/connect-talk-hil-2026-10-22/old-firmware-voice-ab-preparation-2026-10-29.json)。
