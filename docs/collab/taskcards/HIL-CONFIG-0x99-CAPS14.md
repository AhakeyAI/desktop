# 任务卡 HIL-CONFIG-0x99-CAPS14：真机 0x99 14 字节 + factory flag 挡死配置写入

计划/WBS：HIL-CONFIG 阻塞返工  
状态：`draft`（等 Codex 晋级；HIL-CONFIG C1 暂停）  
执行 owner：待 Codex 指定（建议 Cursor，仅客户端解析）  
基线：HIL-CONFIG active；5.7 accepted @ `488097d`  
目标：让已连接的 current 键盘能完成 0x99 协商并允许 C1 apply；不得在 HIL 卡内改业务代码。

## 现象

HIL Agent 已 `已连接: AhaKey X1`，XPC Runtime 正常。0x99 原始应答：

`AA BB 99 00 03 04 02 04 3F 00 C8 00 14 01 14 01 1C 01 CC DD`

payload 14 字节 `03 04 02 04 3F 00 C8 00 14 01 14 01 1C 01`：`protocolVersion=3`，`flags=0x003F`（含 `factoryAssetsFlag=1<<2`）。`AhaKeyFirmwareCapabilities.parse` 在 factory flag 打开且长度 &lt; 22 时返回 nil。日志无「能力帧」，随后 `LED 状态 7: 协议协商未完成或非 current，发送被门控`。C1 无法受理。

## 约束

- 本卡未授权前不得改 Agent/Shared。HIL-CONFIG 不得顺手修。
- 未授权刷机：即使固件应发 22 字节，本窗口也不能刷。
- fail-closed 不得改成「缺字段就猜 factory 布局」。

## 建议切片（待 Codex 裁）

客户端最小：factory flag 打开但仅 14 字节时，**拒绝 factory 扩展字段**（`factorySlotBase=0` 等与 flag 关闭相同），仍接受 `protocolVersion==3` 为 `.current`，并打明确日志。覆盖：14B+flag 不得 nil；22B+flag 仍解析 factory；非法短帧仍 nil。

然后回到 HIL-CONFIG 同窗续 C1（用户已在场）。不进 1.5–1.7，不刷机。
