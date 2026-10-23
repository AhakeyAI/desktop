# WD-005 与暂停任务隔离

依据Owner已批准WD-005范围，以及独立授权的历史路由维护。
WD-002由正式suspend暂停，不关闭、不补写PASS、不重置其原始start或批准。
WD-003/004既有关闭记录保留。

本轮WD-005可恢复源码起点为现有HEAD：41c034171e60b2d4962b0adbe8f3cffbf80a0436。
baseline-start已核验实际生产输入与Git blob一致，并记录START_GIT/guard-origin及恢复副本。
继承当前源码不等于重新验收WD-002；WD-005仅审阅自己起点后的差异，按A10做相关回归。

config_server.json是已确认的本地BLE运行配置，保留原字节，不stage/commit/restore/stash。
三份.rollback-backups/20261010T084508恢复资料按审阅后的RECOVERY_EVIDENCE精确绑定，
原件和完整内容副本均保留。没有全局忽略该目录，也不豁免任何未知或新增产品文件。
并列BLE_tcp_driver_package及其他历史dirty不属WD-005；起点foreign快照保留，不编辑或删除。

没有Git写入，没有生产文件改动；这份隔离记录不授予构建、设备写入或发布权限。
