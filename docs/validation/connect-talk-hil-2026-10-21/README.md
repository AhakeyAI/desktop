# 连接心跳候选验收（2026-10-21）

- 客户端0.2.3/arm64，源码af7645bcde389a470cb14efc6aaf22cfa14d8fd6；Developer ID deep/strict签名通过。旧ed64166包已本机备份，新候选安装到/Applications/AhaKey Studio.app。
- 旧Agent通过界面停止并确认进程退出；关闭诊断面板后退出旧GUI，再启动新进程。新GUI/Agent PID分别17399/17435，均来自安装目录。
- Agent正常连接键盘，socket读回physical1/manual/autoVerified=false；界面一致。没有沿用前一日自动档文字强行覆盖实体读回。未写键位、Voice、待机、拨杆绑定或显示配置。
- 当前提交四项GitHub检查全部success。此前全270项Swift测试和双轴复核通过，详见../connect-talk-hil-2026-10-20/CONNECTION_HEARTBEAT.md。
- 约30.49秒短采样GUI累计CPU+1.22秒，Agent+0.11秒；包含诊断面板关闭等GUI交互，瞬时峰GUI41.2%、Agent6.9%，随后回落，未观察到持续占用。不替代长时性能、GIF及全矩阵测试。

键盘实际关机→界面自动撤回旧连接状态→正常开机恢复仍待用户配合。只完成安装和正常连接，不能写成真实断连已通过；PR141暂保留draft，目标connect&talk。

原始socket/CPU采样仅保留本机私有备份，不提交键位内容或设备地址。
