# Rhino 固件 × 新 Runtime OLED 差分验证（2026-09-02）

## 固定条件

- 固件：Gitee Rhino `53cd0a97e95e3b8b35cd56ed2284970d5a79d1be`
- 固件 HEX SHA-256：`ace7ab3e517ec0849d4f865cdc8d33acb304fbc7b4b5dd68a1d917f8f14b1a70`
- EEPROM：验证前已备份并整区擦除；旧 Rhino 客户端在该清洁状态下写入套图 A，连续两次断电后均保留。
- 新 Runtime：从产品基线 `0b4b5e148ff822454d5ff4316e624c1e1aae1c96` 构建的隔离 HIL Runtime；只为差分开放图片 planner，不覆盖 `/Applications`。
- 写入形状：套图 A 不提交资源；四张输入图仅写入套图 B，随后激活 B。

## 新 Runtime 写入结果

- operation：`11007627-D696-4D8F-AF72-5BA38E764C6C`
- Runtime：`completed 5/5`
- 已确认资源字节：`102400/102400`
- WAL：`completed`，`completed_steps=5`，`total_steps=5`，`terminal_order=1`
- 未出现 `0x97 status=3`

人工观察：

1. 写入后可切换到套图 B，并显示本轮新图。
2. 切回套图 A，原图仍存在。
3. 再切回套图 B，新图仍存在。
4. 断电 5 秒后开机，无人工重连或重写；设备自动重连，A/B 图片均保留。

结论：在同一 Rhino 固件和清洁 EEPROM 上，新 Runtime 的底层编码、CAS、XPC、planner、事务执行、B 套绑定/激活及断电持久化路径本轮通过。此前“新 Runtime 必然无法写图/关机必丢图”的归因不成立；污染 EEPROM 是已确认的重要前置变量。

## 仍为红项：键盘端上传进度

写入过程中键盘 OLED 始终显示 `0,0`。该显示不代表 Runtime/WAL 的字节进度：本轮 Runtime 已单调确认 `102400/102400`。

Rhino 固件的 `0x80` 路径只在窗口开始绘制一次，并显示 `sector / 7, sector`，不是已写/总字节。统一固件 WBS 1.5 的 `upload_progress_core`/B4 才实现逐块推进与刷新；本次键盘尚未刷入该统一固件。因此本轮只把它判为“旧 Rhino 固件 OLED 进度呈现缺陷”，不判为图片写入失败。

## 范围说明

本轮为底层 Runtime 差分 HIL，直接组装合法 desired configuration，以便精确表达“只写 B、保留 A”。当前 Studio 高层 assembler 仍会把 idle 资源与 `defaultAnimation` 镜像，不能表达这一四图 B-only 形状；该产品 UI/assembler 路径尚未由本轮证明。

## 环境恢复

- 临时 HIL owner `lab.jawa.ahakeyconfig.agent.rhino-runtime-diff` 已 bootout。
- 官方 `/Applications/AhaKey Studio.app` v0.2.1 build 361 Runtime 已恢复为唯一 owner，PID `51992`。
- 官方 XPC handshake + snapshot：`RESULT: ok`。
- 官方 legacy status：`switchState=0`、`lightMode=4`。
- 固件、EEPROM、A/B 图片未再改动。
