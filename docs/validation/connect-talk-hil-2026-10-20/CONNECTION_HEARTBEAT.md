# Agent连接提示刷新修复

现场：2026-10-20首次自动档核对时，socket status的switchState=null、fresh physical=null/autoVerified=false；主界面和设备信息却仍显示已连接/旧手动档。用户唤醒后恢复实际连接，再亮屏重拨确认自动。审批始终以fresh结果为准，未从旧界面生成allow。

基线AgentManager只在初始化、安装/启停/归属等refresh事件查询BLE连接；断连后该布尔可长期残留，且GUI还用它允许旧状态缓存继续展示。

修复：

- MainActor维护每5秒一次的只读socket status心跳，独立于昂贵的Hooks/配置/launchd扫描。Agent不运行或归属不在后台时撤回连接显示。
- 后台IO同一时刻仅一个有效worker；停止、不可查询或归属代次改变后旧结果不能恢复连接显示。撤销发布权时仍等旧IO返回后再占用新slot。
- 相同连接值不重复赋Published，避免每5秒唤醒整界面。RunLoop common模式让菜单/滚动期间仍能检查；弱引用和stop支持生命周期收尾。
- 初始化的startServices=false及query注入仅供隔离测试，生产默认仍迁移/读取原设置并启动心跳；不改审批、GATT命令、键位或固件。

新增3项真实timer/异步query回归：连接后离线自动撤回、重复相同结果不重复发布、慢旧回包撤销与查询不重叠。将重复timer临时改为单次时，第一项复现3个失败（只有true，未转false）；恢复重复timer后通过。全270项Swift测试通过。复核补充：生产卸载入口在任何launchd/配置工作前同步撤回连接状态并撤销旧查询发布权；慢回包回归直接覆盖该无IO的卸载准备入口，保留原IO slot直到返回。补充后全270项再次通过。

候选真实离线/重连与短时CPU仍待本批包验证；不得把隔离回归当作硬件全部通过。当前硬件原值已恢复，16键/待机/Voice/拨杆绑定保留检查与自动Hook结果见README.md。
