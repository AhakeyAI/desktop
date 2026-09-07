# C5 正式 Studio UI 逐项取证模板

每个单元格填一次。未获对应 USER-GATE 前保持空白。禁止用专用 desired-config / HIL driver 代替正式 UI。

## 公共身份（每轮矩阵开始抄一次）

| 字段 | 值 |
|---|---|
| 产品 commit | |
| App/Agent 版本与 build | |
| 签名 identifier / Team | |
| Runtime pid / launchd label / 唯一 owner | |
| XPC handshake | |
| 固件族 / 来源 SHA / HEX SHA | |
| 刷入前后备份路径 | |
| EEPROM 初态（备份摘要 / 是否擦除） | |
| stable device ID | |
| 语义 compatibility fingerprint | |
| BLE 名 / 地址 / VID | |

## 单项（复制）

**ID：** `C5-<family>-<item>`（例：`C5-gitee-B-only-png`）

| 字段 | 值 |
|---|---|
| 固件族 | GitHub Standard `3e7f900` / Gitee Rhino `53cd0a97` / Local Rhino `00eb7efc` |
| 页面 | 屏幕 / 按键 / 灯条；mode slot |
| scope | A-only / B-only / A+B（只激活当前套） |
| 输入 | PNG / JPEG / 动态 GIF / >2 MiB·121 帧 / 超限 / 损坏 |
| 素材 SHA | |
| Studio 操作 | 选图、写入当前页 / 写入并激活；截图路径 |
| operation UUID | |
| 冻结 field mask | |
| 开始前对象 CAS | |
| planner profile / 实际 opcode 序列 | |
| WAL 终态 / steps / completed/total bytes | |
| 逐字段 baseline 前 | verified / writeConfirmed / unknown |
| 逐字段 baseline 后 | |
| 键盘目视（含是否 `0,0`） | |
| 切换 A/B | |
| 断电 5s + 自动重连时间线 | |
| 严格 no-op 计数（operation/CAS/WAL/设备命令均为 0） | |
| 结论 | pass / fail / blocked；缺陷则停手另开返工卡 |

## 矩阵勾选（正式 UI，非 HIL driver）

### 每族共用

- [ ] 可识别 PNG 写入并显示
- [ ] JPEG
- [ ] 动态 GIF
- [ ] >2 MiB / 120+ 帧源 → 160×80 规范化后写入
- [ ] 超限源零写入拒绝
- [ ] 损坏输入零写入拒绝
- [ ] 屏幕 A-only
- [ ] 屏幕 B-only（另一套保留）
- [ ] 屏幕 A+B 都写、只激活当前套
- [ ] 按键或灯条页 dirty 时屏幕 operation 不组包、不写其他页
- [ ] 与 `verified` 或同次 `writeConfirmed` 相同 → 严格 no-op
- [ ] 两页各一 operation，底部 FIFO 可见；当前页锁、其他页可编辑
- [ ] queued 可移除；running 无普通取消
- [ ] 同设备/同 fingerprint 中段断连续传同一 UUID
- [ ] 不同设备或语义变化必须停止
- [ ] 断连 >60s「放弃未完成写入」
- [ ] 永久失败 fail-fast；已确认入 baseline；重试只发剩余差异
- [ ] 不可读回 → `writeConfirmed`；可读回一致 → `verified`
- [ ] 旧 Rhino `0,0` 单列，不覆盖 Runtime 字节进度
- [ ] 结束恢复官方 Runtime；临时 label/进程/挂载清理证明

### GitHub Standard `3e7f900` 额外

- [ ] 未发送该固件未登记 opcode
- [ ] 5s 断电保持

### Gitee / Local Rhino 额外

- [ ] 先 A 后只写 B；A 未覆盖
- [ ] 断电后两套均保留
- [ ] 断连后自动恢复
