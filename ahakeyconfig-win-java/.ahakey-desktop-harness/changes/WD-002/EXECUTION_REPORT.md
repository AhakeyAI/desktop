# WD-002 DIB Execution Report

## 身份与范围

- 角色：DIB。
- 任务：WD-002 - WS2 CP4A Mode Sync + Display Status。
- Harness：1.1.0。
- 本轮模式：FIX，build_round 3。
- 本轮开工门禁：`python .agents\skills\ahakey-desktop-harness\scripts\desktop.py preflight --role DIB --id WD-002`，结果 PASS。
- 修复依据：DLA review fail / request-fix，见 `.ahakey-desktop-harness/changes/WD-002/REVIEW.md`。
- 未执行 Git add/commit/push/reset/clean/stash/checkout；未修改 Firmware 或 eternal；未创建构建收据、测试包或发布批次。

## 实际差异

- 保留前一轮 WD-002 实现：
  - Q7 离线边界：断开时点击编辑配置只发起连接，不进入编辑态；连接成功后才进入编辑态。
  - 离线模式选择只浏览本地草稿，不发送 `0x92`，不排队重放。
  - 连接态模式切换使用 `0x92`，并要求后续 `0x00` 状态回读匹配目标模式。
- 本轮针对 DLA 阻塞点修复 `BleManager`：
  - `processNotifyFrame()` 解析到有效 `0x00` 状态帧时，先继续更新 `cachedStatus` / UI 回调，同时调用 `enqueueNotifyFrame(data)` 把同一原始状态帧放入按命令分组的等待队列并唤醒等待线程。
  - 非状态响应帧也通过同一个 `enqueueNotifyFrame(data)` 入队，避免状态帧和普通命令帧走两套唤醒逻辑。
  - `waitForResponseFrame()` 在等待 `CMD_QUERY_STATUS` 时不再用通用 `CommandResponse.status()` 解释状态帧；改为直接用 `AhaKeyProtocol.parseDeviceStatus(frame)` 校验并返回，避免把电量字节误判为错误码。
- 修复结果意图：
  - `setWorkModeAndVerify()` 的 `0x92 OK` 后，`queryDeviceStatusSnapshot()` 发送的 `0x00` 回读既能更新 UI 缓存，也能被确认逻辑可靠观察到。

## 已执行机器检查

- `python .agents\skills\ahakey-desktop-harness\scripts\desktop.py preflight --role DIB --id WD-002`
  - 退出码：0。
  - 结果：`DIB PREFLIGHT: PASS for current v1 phase/mode only`。
- `git diff --check`
  - 退出码：0。
  - 结果：无空白错误；仅输出工作区 CRLF 提示。
- `mvn -q -DskipTests compile`
  - 使用临时命令环境 `JAVA_HOME=D:\jdk-17.0.19.10-hotspot`。
  - 退出码：0。
- `mvn -q test`
  - 使用临时命令环境 `JAVA_HOME=D:\jdk-17.0.19.10-hotspot`。
  - 退出码：0。
  - 说明：当前仓库未发现 `src/test` 测试目录；该结果主要证明 Maven 测试入口与编译通过，不是真机行为测试。
- 静态核对：
  - `rg` 确认 `setWorkModeAndVerify()` 仍调用 `queryDeviceStatusSnapshot()`。
  - `rg` 确认 `CMD_QUERY_STATUS` 等待路径使用 `AhaKeyProtocol.parseDeviceStatus(frame)`。
  - `rg` 确认 `processNotifyFrame()` 的状态帧和非状态帧均调用 `enqueueNotifyFrame(data)`。
  - `rg` 确认 `0x95` 睡眠等待与 `0x9F` 固件目录键仍存在于协议、解析、BleManager 与 TopBar 调用链。

## 实际可运行产物

- 本轮未执行 `build-open/build-finish`，未生成新的 JAR、EXE 或安装包。
- 本轮没有可交 Owner 真机测试的产物；仅完成源码修复与机器检查。

## 交给 DLA

- 需要 DLA 重新 review-pack 并实际审阅：
  - `0x00` 状态帧是否同时进入 UI/cache 路径和等待队列。
  - `CMD_QUERY_STATUS` 是否避免通用命令响应 status 误判。
  - `0x92 OK + 0x00` 回读确认是否满足 CP4A 合同。
  - 旧 `0x95` / `0x9F` 相邻行为是否仍可接受。
- 尚未完成：DLA review、Git candidate、build receipt、Firmware identity 复核、Owner UAT。
- 不声明 Owner 真机测试通过。
