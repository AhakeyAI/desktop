# 新固件自动档与配置保留收尾（2026-10-20）

固定客户端0.2.3/source ed64166，固件身份/昨日显示验收见../connect-talk-hil-2026-10-19/WS3_ACCEPTANCE_CHECKPOINT.md。

## 实际结果

- 用户切回自动后的第一次查询，设备不在线，fresh physical=null、autoVerified=false，未调用自动放行Hook。GUI仍展示上次连接与档位；这是待修的连接缓存刷新问题，不把该界面当实时证据。
- 系统蓝牙开启、505C已配对但未连接。用户开机/唤醒后恢复实时状态，第一次实际读回仍为physical1；亮屏重拨后连续读回physical0、factory auto verified=true/version1。不以用户口头档位或缓存覆盖实体读回。
- Cursor beforeShellExecution返回allow；Claude PreToolUse permissionDecision=allow、PermissionRequest behavior=allow；Codex PermissionRequest behavior=allow，顶层approval_policy=never且有本版本lease。均为实际安装二进制Hook进程，未执行示例工具命令；不等于已运行CLI配置缓存全部刷新。
- 配合昨日手动physical1、Cursor Shell ask、Claude/Codex无allow/on-request，完成本轮实体手动→自动往返。Kimi仅确认了手动时配置false，完整运行会话矩阵未完成。
- GUI只读连接读取16键、95待机、96语音引导、97两档绑定。使用生产DeviceFrameDecoder重组分片，与刷写前私有备份比较：16/16逐字节一致，待机/Voice引导/拨杆绑定均一致。比较97时排除实时物理位置字段。只提交无原始键位内容的汇总JSON，原始回包保留本机。
- 本轮仅配置读取，无键位、Voice、灯效、素材或全量保存写入。详细通信日志已关闭。GUI交还同源Agent后，再次fresh physical0/verified=true，并验证Codex allow/never恢复；最后关闭诊断面板。

## 边界与后续

新固件单项显示保存/重启/原值恢复、读取取消等结果仍按昨日记录，不将其扩大为全模式/资源/最终发布验收。失败新设备15秒截止与所有恢复路径仍有隔离测试和复核，真实负例矩阵未覆盖。

基线AgentManager的isAgentBLEConnected只在refresh事件更新，离线时可能保留旧“已连接”外观；实际审批使用fresh查询已按手动回退。后续单独修复该显示刷新缺口，并核对休眠/唤醒与拨杆采样边界；本次唤醒第一次读回1不单独定性为固件漏采。
