# 任务卡 HIL-CONFIG-0x99-CAPS14：真机 0x99 14 字节 + factory flag 挡死配置写入

计划/WBS：HIL-CONFIG 阻塞返工  
状态：`review`（最小兼容已提交，等 Codex 验收后才恢复 HIL C1）
执行 owner：Cursor
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

## Codex 裁决切片（已生效）

原建议“factory flag + 14B 一律 `factorySlotBase=0`”不获批准：本次真机最后 4 字节是 `reclaimSlotBase=276`、`reclaimSlotLimit=284`，不是空扩展；Rhino 生产写帧源码证明 compact 14B 布局为 `userSlotLimit`、`reclaimBase`、`reclaimLimit`。把 factory base 清零会丢失真实 factory 边界并可能掩盖写址错误。

允许的最小兼容实现：

1. `AhaKeyFirmwareCapabilities.parse` 识别两种 factory 格式：
   - factory flag + **14B compact**：接受 protocol v3；`userSlotLimit=u16(8)`、`factorySlotBase=userSlotLimit`（factory reserved boundary）、`reclaimSlotBase=u16(10)`、`reclaimSlotLimit=u16(12)`；bundle version/CRC/status/error 继续为 unknown/0，不得从缺失字节猜测。
   - factory flag + **22/26B extended**：维持当前字段语义；13B 以下和介于 15...21B 的截断/歧义帧 fail-closed。
   - factory flag 关闭的既有 14B 契约继续 `factorySlotBase=0`，不得回归。
2. 修正 Runtime 用户资源写址：primary user range 是 `0..<userSlotLimit`，不得再以 `factorySlotBase` 作为用户资源上传/绑定起点。compact 真机帧下首槽必须从 0 开始，所有生成的写地址和 `0x95 startIndex+count` 必须停在 276 之前；本切片不启用 reclaim 分配，容量不足继续 fail-closed。
3. Agent 只允许增加一条明确诊断：识别 compact factory caps，记录 primary/reclaim 边界；不得改 BLE 状态机、协商重试或写入门控的其他逻辑。
4. 精确回归 fixture 使用本次真机 payload `03 04 02 04 3F 00 C8 00 14 01 14 01 1C 01`。必须覆盖：解析为 protocol 3/current；factory reserved boundary 276；reclaim `276..<284`；首槽写址 0；最后合法 primary 写入不越过 276；本切片暂不分配 reclaim，故不得生成任何 `startIndex >= 276` 的写入；22/26B、factory-off 14B 与非法短帧不回归。

白名单：`Sources/Shared/AhaKeyFirmwareCapabilities.swift`、`Sources/Shared/AhaKeyDeviceProgramSteps.swift`、`Sources/Agent/AhaKeyAgent.swift` 中仅 capability 诊断行、对应 capabilities/cross-contract/step-mapper tests、本卡与 board。禁止修改 planner 容量模型、wire v1.1、Studio UI、固件、安装器、HIL 脚本或其他业务代码。

门禁：先让真机 fixture 新测试在旧代码上失败，再修绿；定向 capabilities + caps14 + step-mapper；完整 Swift 一轮；App+Agent Release；`git diff --check`。新提交后停手提审，Codex 通过后才恢复 HIL C1。

然后回到 HIL-CONFIG 同窗续 C1（用户已在场）。不进 1.5–1.7，不刷机。

### [2026-08-27 21:22] Cursor：最小兼容完成，停手提审

- compact 14B 真机 fixture 解析为 v3/current，`userSlotLimit=276`，factory reserved 276，reclaim `276..<284`；bundle/CRC/status 保持 0。
- 用户资源上传/0x95 从 `0` 起编；`startIndex >= userSlotLimit` 不生成（不启用 reclaim）。factory-off 14B 仍 `factorySlotBase=0`；15–21 / 23–25 fail-closed；22/26B 不回归。
- Agent 仅增加 compact factory 诊断行。
- 门禁：定向 capabilities+caps14+step-mapper 通过；全量 **480 / 2 skipped / 0 failures**；Release App+Agent 通过；`git diff --check` 干净。
- 未恢复 HIL C1、未刷机、未替换正在跑的 HIL agent。等 Codex 验收。
