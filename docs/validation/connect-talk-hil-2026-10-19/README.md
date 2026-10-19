# macOS connect&talk 真机检查点（2026-10-19）

本记录仅覆盖下表所列项目，不等同于最终用户版验收。用户确认键盘可用、并行旧包测试已结束后安装。PR #140 目标为 `connect&talk`。

## 候选与环境

- 原安装及原运行 GUI 均为 0.2.3/source1760a3f，已保留本机私有备份。
- 第一轮候选：0.2.3/arm64/source6094a27，GUI 与 Agent 均从 `/Applications/AhaKey Studio.app` 运行。
- 英文菜单漏译修正后的最终候选：source99b0c20，Developer ID 深层/严格签名验证通过，已安装并启动。该提交仅补充一个资源键，无运行逻辑变化。
- 键盘：AhaKey515C，目前为既有 WS2/CP4D 设备；本轮未刷 HEX。0x88 返回旧通用 ACK，不支持 WS3 显示读回。
- 保留用户当前 Voice：onboarding=3、四个 F18 绑定（App 接管）；本轮没有将其恢复 Consumer。Consumer 可行是用户此前确认，F5 继续暂缓。

## 已执行

| 项目 | 观察与结论 | 候选 |
| --- | --- | --- |
| 安装/启动 | GUI 正常打开；Agent 从同一安装目录运行，旧构建路径已移交 | 两轮 |
| 六标签 | 按键、工作模式、待机、实体拨杆、语音方案、显示与灯光可打开 | 6094a27 |
| 待机只读 | 读回 60 分钟，未应用更改 | 6094a27 |
| 模式 | 当前 Claude；打开/浏览没有切换实体模式 | 6094a27 |
| 拨杆只读 | 位置1出厂自动、位置2出厂手动，未改绑定 | 6094a27 |
| 普通键读回 | Mode1/Key1 = F18，描述 Record，18/64 字节；显式载入画布提案后没有执行应用 | 6094a27 |
| Voice只读 | 四模式 F18 确认；保留当前方案，未执行接管 | 6094a27 |
| 显示兼容 | 明确提示“当前固件未提供 WS3 显示读回，未修改键盘显示配置”；不伪造数值或开放写入 | 6094a27 |
| 连接交接 | 配置连接返回日常连接；快照清空、编辑读按钮禁用；Agent重连后审批查询成功 | 6094a27 |
| 英文布局 | 六标签、读按钮、反馈可见，无观察到的裁切；发现更多菜单入口漏译并修正 | 两轮 |
| 英文入口修正 | 新候选更多菜单显示 Keyboard Settings…；恢复用户原“跟随系统”并重启回中文 | 99b0c20 |
| 正常停止后台 | UI变为未运行，socket不可用，全局 all.paused 已持久化；重启后恢复连接/解除全局暂停 | 两轮 |
| 无归属旧策略 | 原 Codex never 没有 AhaKey lease；停止时保留，不能把该路径记为“恢复手动成功” | 6094a27 |
| 实体手动 | 用户切至手动；界面显示手动，physicalSwitchState=1，approvalAutoVerified=false；Codex PermissionRequest无allow，on-request；Cursor Shell返回ask | 99b0c20 |
| Cursor preToolUse | 手动仍输出allow，交回Cursor自身权限层；该事件不以ask阻断所有工具，不能据此声称自动批准 | 99b0c20 |
| 实体自动 | 用户切回自动；physicalSwitchState=0，approvalAutoVerified=true；Cursor Shell及Codex PermissionRequest返回allow；Codex never并生成归属lease | 99b0c20 |
| 有归属停止收尾 | UI停止后台后Codex收回on-request、lease移除、socket关闭；停止时Cursor Shell为ask、Codex无allow | 99b0c20 |
| Codex Hook移除/重装 | 自动档时移除仅产生codex.paused；Codex回on-request、6个Agent入口移除，直接旧Hook不放行，Cursor仍allow；UI重装后6个入口恢复、暂停清除、Codex再次allow；非审批文本与安装前一致 | 99b0c20 |
| 配置保留 | 比较私有安装前备份，Codex/Kimi除目标审批字段外文本内容一致；无整份回滚 | 99b0c20 |
| 短时待机CPU | 30秒/11点：GUI CPU用时+0.32秒，Agent +0.09秒；ps瞬时分别0–0.3%、0–1.0%。初始语言切换/启动峰值另计，不混为待机 | 99b0c20 |
| 电量 | 状态更新后75→82→83%，未出现持续0；不等于电量精度/低电量/充电完整验收 | 两轮 |

248项Swift测试在运行逻辑6094a27上通过；99b0c20仅资源补漏，资源语法/生成器/签名检查通过。没有因文字改动重复执行全套测试。

## 仍待执行

- 真实 CLI 运行会话重载（直接Hook进程输出不等于已运行IDE/CLI刷新缓存）。
- Claude/Cursor/Kimi移除重装及四客户端完整矩阵；Codex移除/重装已通过。当前Claude/Cursor/Codex均指向已安装Agent，未改Kimi补丁。
- CoreBluetooth真实在途取消/迟到通知、DATA分片中断、写入失败与断电保持完整矩阵。
- WS3最终候选固件与0x88完整快照、预览/写入/上传/清空；本机不支持不能代替新固件验收。
- 长时CPU、Dynamic Island交互、完整电量和四模式Voice回归；本轮未重复录音。

私有配置、原始宏、完整通信日志和凭据没有写入本目录。无未脱敏的应用截图上传。

## 收尾状态

最终安装99b0c20；GUI与Agent均从Applications运行，BLE归Agent日常连接，实体自动档、Codex never且有本版本归属记录；Codex Hooks已恢复。语言回到跟随系统中文，画布未同步改动0。Voice/AhaType设置保留，详细通信日志没有开启。
