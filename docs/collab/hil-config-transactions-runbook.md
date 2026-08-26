# HIL-CONFIG-TRANSACTIONS Runbook（纯文档，未获 USER-GATE 前不得执行）

适用任务卡：`docs/collab/taskcards/HIL-CONFIG-TRANSACTIONS.md`（状态 draft / USER-GATE）
前置：WBS-5.6 accepted 提交作为基线。本 runbook 仅描述步骤与证据格式；执行前必须取得用户批准断电/断连窗口。
约束：不刷机、不改生产安装脚本、不并入 MachServices 正式登记（归 WBS-5.9）。临时登记必须可完整回滚。

## 0. 构建与产物

```bash
cd ahakeyconfig-mac
swift build -c release --product ahakeyconfig-agent
# 产物：ahakeyconfig-mac/.build/release/ahakeyconfig-agent
```

记录基线：`git rev-parse HEAD`、构建时间、`shasum -a 256 .build/release/ahakeyconfig-agent`。

## 1. launchd 临时登记（用户域，可回滚）

1. 写临时 plist 到 `~/Library/LaunchAgents/lab.jawa.ahakeyconfig.agent.hil.plist`（**不得覆盖正式安装的同名/服务 plist**；若已存在正式登记，先停止并记录原状）：
   - `Label`: `lab.jawa.ahakeyconfig.agent.hil`
   - `ProgramArguments`: `[ "<abs path>/.build/release/ahakeyconfig-agent" ]`
   - `MachServices`: `{ "lab.jawa.ahakeyconfig.runtime": true }`（与 `Sources/Agent/main.swift` 打印的登记样例一致）
   - `RunAtLoad`: false（手动控制生命周期）
2. 登记：`launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/lab.jawa.ahakeyconfig.agent.hil.plist`
3. 启动：`launchctl kickstart gui/$(id -u)/lab.jawa.ahakeyconfig.agent.hil`
4. 验证登记：`launchctl print gui/$(id -u)/lab.jawa.ahakeyconfig.agent.hil | grep -A2 MachServices`（应见 `lab.jawa.ahakeyconfig.runtime`）

## 2. XPC smoke（不碰真机）

- Studio（Debug 或已安装客户端）连接 `lab.jawa.ahakeyconfig.runtime`：下发一个最小合法包（1 张 160×80 测试图），期望 accept 成功返回。
- 负向：故意发一个 digest/byteCount 不符的资源项，期望 `resourceByteCountMismatch` 且 CAS 目录零新增。
- 证据：Studio 侧返回码截图/日志、`log stream --predicate 'subsystem == "lab.jawa.ahakeyconfig.agent"'` 对应时间段落盘。

## 3. 真机用例（HIL 主体，需用户在场操作键盘供电/连接）

| # | 用例 | 操作 | 通过判据 |
|---|------|------|----------|
| C1 | 图片+基础配置成功 | 完整 apply 一个小型包 | 设备显示正确；revision/baseline 与设备一致 |
| C2 | 容量拒绝零写入 | 构造超容量包 apply | 拒绝；设备配置与 CAS 无变化 |
| C3 | 取消 | apply 中途用户取消 | 事务收尾一致；无半绑定状态 |
| C4 | 断电恢复 | apply 中途拔键盘供电，再通电 | 重连后事务可恢复或安全回滚；设备不砖 |
| C5 | 断连恢复 | BLE 断连（关蓝牙/走远）再恢复 | 同上 |
| C6 | partial resume | C4/C5 后再次 apply 同包 | 已完成步骤不重传；最终一致 |

每用例记录：开始/结束时间、操作时点、Agent 日志段、Studio 返回、设备现象（照片）、结论。

## 4. 证据打包

- 目录：`docs/collab/evidence/HIL-CONFIG-<date>/`，含日志、截图、用例表填写版、基线信息。
- board 追加总结条目并标「需要回复：是（@Codex）」；任务卡追加执行记录。

## 5. 回滚（必须执行，无论成败）

```bash
launchctl bootout gui/$(id -u)/lab.jawa.ahakeyconfig.agent.hil
rm ~/Library/LaunchAgents/lab.jawa.ahakeyconfig.agent.hil.plist
```

- 确认 `launchctl print gui/$(id -u) | grep ahakeyconfig.agent.hil` 无残留。
- 若实验前存在正式登记，按其原状恢复并验证 Studio 可连。
- Agent 进程全部退出后删除测试用 persistence root（若用了临时目录）。

## 6. 中止条件

任一用例出现设备不可恢复异常、Agent 崩溃无法重启、或数据目录损坏迹象：立即停止，执行回滚，board 上报并等 Codex 裁决；缺陷修复走新返工卡，不在本卡内改业务代码。
