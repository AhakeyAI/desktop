# 连接心跳候选验收（2026-10-21）

- 客户端0.2.3/arm64，源码af7645bcde389a470cb14efc6aaf22cfa14d8fd6；Developer ID deep/strict签名通过。旧ed64166包已本机备份，新候选安装到/Applications/AhaKey Studio.app。
- 旧Agent通过界面停止并确认进程退出；关闭诊断面板后退出旧GUI，再启动新进程。新GUI/Agent PID分别17399/17435，均来自安装目录。
- Agent正常连接键盘，socket读回physical1/manual/autoVerified=false；界面一致。没有沿用前一日自动档文字强行覆盖实体读回。未写键位、Voice、待机、拨杆绑定或显示配置。
- 当前提交四项GitHub检查全部success。此前全270项Swift测试和双轴复核通过，详见../connect-talk-hil-2026-10-20/CONNECTION_HEARTBEAT.md。
- 约30.49秒短采样GUI累计CPU+1.22秒，Agent+0.11秒；包含诊断面板关闭等GUI交互，瞬时峰GUI41.2%、Agent6.9%，随后回落，未观察到持续占用。不替代长时性能、GIF及全矩阵测试。

实际断连/恢复验收通过：用户正常关机并保持后，未点刷新、重启或所有权切换，主界面自动变为“未连接／档位未知”，socket status的switchState/lightMode均null、verified=false。正常无线开机后，无需手动扫描或重新配对，主界面自动恢复连接；fresh approval_status读回physical1/manual/verified=false，与界面一致。未精确计时物理断电时刻，不声称测得5秒上限。

另验证生产停止入口：点停止后立即显示BLE未连接、档位未知；随后Agent未运行，无旧已连接回填，Codex为on-request。再点启动恢复同源后台连接。没有写键位、Voice、待机、拨杆绑定或显示配置。真实新设备连接失败15秒截止/手动恢复、长时CPU、完整显示矩阵仍未覆盖；本批仅覆盖既有配对设备断电/恢复及停止入口。PR141目标connect&talk，最终文档提交CI通过后合并。

原始socket/CPU采样仅保留本机私有备份，不提交键位内容或设备地址。
