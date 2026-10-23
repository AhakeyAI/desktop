# WD-005 SINGLE 无灯效/GIF 跟随：日志与冻结源码核对

## 范围

Owner 在已切换 SINGLE 后运行当前 Codex 对话，观察到灯光未亮、GIF 未切换。本轮只读日志、配置元信息和源码，不改生产代码、用户配置、固件或 Harness 路由，不运行应用、Hook、构建或设备命令。

使用正在测试的 preview-20261017T104547091113Z-0e6fcf 冻结 source 核对调用链，不用工作区后续改动推断运行包行为。
受只读边界限制，未动态复现、未注入 Hook、未读取 JVM 内存变量；结论区分日志事实、静态缺陷和待确认根因。

## 证据来源

- 实际运行日志：.ahakey-desktop-harness/previews/WD-005/preview-20261017T104547091113Z-0e6fcf/runtime-jar-classpath/logs/ahakey-studio.log。日志仍在追加，统计截至读取的 2026-10-18 15:21:28.596。
- 仓库根 logs/ahakey-studio.log 最后内容为 10 月 16 日隔离测试，不作为本次设备运行证据。
- C:\Users\20825\.ahakey\ai-runtime.json：displayMode=SINGLE；读取时 SHA256=4E6BD6BCD7A9A157B184CF886FAAFDB6DDBD9AD2AEF042182A1F71FD0683C7FC。
- C:\Users\20825\.ahakey\oled-resources\v1\index.json：读取时 SHA256=7F15873B92A8FB3EFD6ECF19A3C327CE0669BF456C0C639157578461EF48E7CA。
- 已安装 ahakey-codex.ps1、ahakey-core.ps1 与 .codex/hooks.json 只读核对；版本标记为 ws3-cp1-v1，目标端口 8765，与应用启动日志一致。不执行脚本或安装更新。

## 已确认时间线

1. 15:11:09.823 发送 AABB9800CCDD，15:11:09.825 收到 AA BB 98 00 CC DD。SINGLE 切换有成功 ACK。
2. 15:11:12.245 和 15:11:43.320，hook-dispatch 发送 AABB9008CCDD，分别收到 0x90 成功 ACK。码 8 是 SESSION_END，不是工作中状态。
3. 15:11:17.790 再次发送 SINGLE，收到成功 ACK。
4. 15:12:14.558 新一轮 Begin 返回 AA BB 8A 00 CC DD。
5. 15:12:14 至 15:12:15.795 共有 63 条 0x8B 成功响应，之后到观察截止没有这轮 Commit 响应。
6. 15:12:30.814、15:14:35.289 读取显示配置返回 AA BB 88 01 CC DD。
7. 15:12 后到截止，hook-dispatch 有 37 条 queryStatusAndWait 状态刷新成功日志，0x90 发送记录为 0。USB 状态查询仍持续正常，不能说整个 Hook 服务或 USB 连接失效。现有日志没有逐事件平台/session 字段，因此不声称这些查询全部属于当前 Codex 会话。

## 本地持久记录补充

当前设备 Mode 索引为 1（UI Mode 2）。资源索引：

- entry 4，Mode 2 默认屏幕：APPLIED，1 帧。
- entry 5，Mode 2 SINGLE 工作中：DRAFT，1 帧。
- entry 6，Mode 2 SINGLE 等待中：DRAFT，1 帧。
- entry 7，Mode 2 SINGLE 已完成：FAILED，1 帧；notice 原文为“上传并应用未完成：设备保存或读取结果未确认，请重新连接后同步。 键盘资源有效性需重新同步确认。”

这说明后续 SINGLE 资源并未全部应用。device 字段可能是失败前缓存，不能当成失败后新读回的设备事实。commitUncertain=false 只代表没有进入未知 Commit 阶段，不代表整个上传可安全继续。

## 调用链判断

冻结源码相对 source/src/main/java/com/example/ahakey/：

- service/BleManager.java:196 设置响应等待 15 秒；超时等异常使 displayWriteUncertain=true（约 210-214 行）。
- service/OledUploadService.java:40 在非明确 FAIL 的上传异常中调用 requireDisplayRecovery，避免事务仍占用时继续写入。
- service/BleManager.java:734-741 的 sendRuntimeState 在 displayLease 或 displayWriteUncertain 存在时只保留 deferredRuntimeState，并返回 false，不发 0x90。
- service/AiRuntimeDisplayService.java:276-280 的 SINGLE 分支忽略上述 boolean，仍返回 true；service/HookDispatchServer.java 的 handleGeneric 可因此回复 displayUpdated=true。此为明确的反馈语义缺陷，不等于物理发送成功，也不是暂停的原始原因。
- service/DisplayConfigService.java:119 起的 upload 将 UploadFailure 捕获并保存为 FAILED/notice，而不是抛给通用日志分支，因此仅搜索 WARN/ERROR 会漏掉此失败。
- 固件 APP/sub_main/command_solve.c:425 起：0x00 查询先处理；上传 active 或 pending 时拒绝其他不允许的命令。可解释“状态查询仍正常、显示配置读取 FAIL”的组合，但不能仅凭 0x88 FAIL 就证明固件内存一定为 active。

## 结论分层

高置信直接机制：SINGLE 切换成功后发生了另一轮上传超时；上位机按保护策略暂停 AI 状态写入，与之后无 0x90、灯光和 GIF 不跟随一致。不是把整个问题归结为未切换模式、未安装 Hook 或槽位未绑定。

独立资源条件：工作中/等待中仍是草稿，已完成上传失败，不能期待这三份自定义资源已在键盘上生效。默认屏幕的成功不等于 SINGLE 三项成功。

确定静态问题：SINGLE 返回值忽略未发送结果，反馈会误报更新；失败日志和 UI 可见性需修复阶段一起评估，保护门禁不能直接删除。

仍待定位：为什么此次分块上传在 63 个成功 ACK 后停止。现有日志未记录每个发出 chunk 的 offset/完整字节，也无底层 USB 抓包或固件现场日志，尚不能归责上位机、传输或固件。不能宣称已经修复或完整复现。

## 后续验证建议（尚未执行）

Owner 暂停继续上传，物理断开并重新连接 USB，让两端进入新连接；如应用未正确识别断开再正常退出重开，不删除草稿、不恢复出厂、不重新烧录。先不上传资源，保持 SINGLE，发起新的 Codex 请求，核对是否恢复 0x90 和灯光响应；自定义 GIF 另按每项资源成功状态验证。异常继续保留截图、时间与日志。

本记录为 Preview 问题分析，不登记 SINGLE PASS，不改变正式门禁；待 Owner 汇总测试后再按授权退修。此前默认屏幕首次 Begin FAIL 是另一条异常，不与这次 chunk 超时合并成同一已证实根因。

## Owner 后续验证：USB 重连后灯光恢复

2026-10-18，Owner 原文：

> 拔插了一次usb，现在灯光都是正常的了

- 记录为 Owner 实际观察：物理 USB 重连后，灯光恢复正常。
- 进一步支持前述“上传超时后的连接内保护状态阻断运行态下发，重连后恢复”的判断；拔插同时重置两端状态，不能仅凭此定位最初上传超时的责任侧。
- 恢复操作有效不等于软件缺陷已修复；上传首次失败、分块超时、反馈误报仍保持待处理。
- Owner 本条未报告 GIF 恢复、资源重新上传或所有 SINGLE 状态逐项通过，不补写这些结果，也不登记整体 SINGLE/UAT PASS。
- 本轮只追加记录，未修改生产代码、固件、用户配置或 Harness 路由，未执行设备操作。
