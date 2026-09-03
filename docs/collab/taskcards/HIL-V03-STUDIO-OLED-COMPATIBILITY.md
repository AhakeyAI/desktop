# 任务卡 HIL-V03-STUDIO-OLED-COMPATIBILITY：正式 Studio × 旧固件图片写入矩阵

计划/WBS：v0.3 客户端 OLED HIL
状态：`draft / USER-GATE`
执行 owner：Cursor
只读验证：Zcode；Codex 验收
依赖：`V03-STUDIO-OLED-LEGACY-COMPATIBILITY` accepted
基线：从该卡 accepted 产品提交冻结签名 HIL 候选；不得使用专用 desired-config 驱动替代正式 UI

## 目标

用正式 Studio UI 和正式 Runtime，在所有已登记旧固件上证明图片写入兼容；不刷统一固件。该卡只执行与取证，不在 HIL 现场修改业务代码。

本卡同时是页面级写入模型的 C5 验收：验证“当前页 dirty-only、每页独立 operation、底部设备 FIFO、断连续传、三级 baseline 与严格 no-op”，不得只证明底层 HIL driver 能写图。

## 矩阵

1. **GitHub Standard `3e7f900`**：写入一组可识别图片；确认正确显示、切换（若固件支持）和 5 秒断电保持；日志证明未发送不支持 opcode。
2. **Gitee Rhino `53cd0a97`**：先写 A，再由正式 Studio 只写 B；operation completed、字节进度到 total、A 未覆盖、A/B 可切换；断电后两套均保留；断连后自动恢复。
3. **Local Rhino `00eb7efc`**：重复 A/B scoped 写入、切换、断电保持与自动重连。
4. 每一族至少覆盖 PNG、JPEG、动态 GIF；包含 >2 MiB/120 帧源图的 160×80 规范化路径，以及超限/损坏输入的零写入拒绝。
5. 对未知或畸形 capability fixture 只做 host/模拟负向，不拿真机冒险写入。
6. **页面 scope**：屏幕页分别覆盖 A-only、B-only、A+B 同时 dirty；A+B 都写但只激活当前套。另造按键页或灯条页 dirty，证明屏幕 operation 不读取、不组包、不写入其他页。
7. **严格 no-op**：当前页与 `verified` 或同次 `writeConfirmed` 基线相同时，operation/CAS/WAL/设备命令均为 0；不得仅以 UI 无变化代替计数证据。
8. **队列与页面锁**：至少两个不同页面各建 operation，底部 FIFO 顺序可见；当前页排队即锁、其他页仍可编辑；queued 可移除，running 不显示普通取消。
9. **断连续传**：同一设备/同一语义 fingerprint 在资源中段断连，重连后保持同一 UUID、只续传未确认字节；不同设备或协议语义变化必须停止。另覆盖断连超过 60 秒后的“放弃未完成写入”。
10. **部分成功与旧固件**：制造永久失败，证明 fail-fast、已确认字段入 baseline、剩余字段仍 dirty、重试只发剩余差异。不可读回旧固件显示 `writeConfirmed`；可读回时升级为 `verified`，不一致则冲突。

## 证据要求

- 固件来源 SHA、HEX SHA、刷入前后备份与 EEPROM 初态；每次换固件/擦 EEPROM 都是单独 USER-GATE。
- App/Runtime 版本、产品 commit、签名身份、PID、唯一 owner、XPC handshake 和设备 identity。
- 每次 operation UUID、planner profile、实际 opcode 序列、WAL 终态、steps、completed/total bytes、Studio 截图、键盘目视结果。
- 每次记录 page/object ID、冻结 field mask、stable device ID、语义 compatibility fingerprint、开始前对象 CAS 结果，以及逐字段 baseline 前后状态（verified/writeConfirmed/unknown）。
- A/B 写入前后与断电后的照片/视频或逐项人工记录；自动重连时间线。
- 旧 Rhino 键盘 `0,0` 单列为已知固件显示限制，不得覆盖 Runtime 字节进度证据。
- 每次结束恢复官方 Runtime；临时 label、进程、挂载、候选和日志目录均有清理证明。

## 停止条件

- capability 路由与预期不一致、发送了该固件未登记 opcode、现存图片被意外覆盖、WAL/设备结果矛盾、签名/XPC/唯一 owner 漂移时立即停止。
- 发现产品缺陷时另开最小返工卡；不得在本 HIL 卡内顺手改代码。
- 断电、固件切换、EEPROM 擦除、安装与签名均须用户在对应步骤明确批准。
- 发现 Studio 首次连接自动创建 operation、补写默认值或触发 CAS/WAL 时立即停止；出厂默认由固件负责，不得在客户端 HIL 中补救。

## 完成定义

三类旧固件的正式 UI 矩阵及 C5 页面事务矩阵全绿，兼容清单与已知限制可直接用于公开 v0.3 文档。通过后开放 `HIL-RELEASE-0.3` 客户端候选冻结；`HIL-CONFIG` C1-C6 和统一固件刷机仍为独立后续门禁。

## 执行记录（append-only）

等待客户端实现卡 accepted 与用户逐次开放固件/EEPROM/断电窗口。
