# WD010 起点及暂停任务隔离

日期：2026-11-05（Asia/Shanghai）。
Owner批准完整WD010 Contract进入实施；没有批准恢复其他暂停任务或清理他人文件。

- 暂停任务：WD-002, WD-006, WD-007, WD-008, WD-009
- WD009保留1.0.19 Owner Preview PASS；正式收口暂停，不标CLOSED，不重置原起点或回执。
- WD010 START_GIT已核对提交70ccc3361ecd90e6c67828bac581a6975ebdccb2，生产指纹与当前一致；不通过stash/reset/checkout制造干净目录。
- 共享旧文件只能做WD010批准范围内增量，既有WD009行为和其他阶段实现均受保护；原候选/包/测试记录保持，不拿旧PASS给新代码背书。
- BLE_tcp_bridge、Harness历史变更及config_server.json等既有脏内容不纳入本次实现，不还原、暂存、提交或清理；运行配置不是产品起点的Git缺口。
- Git仅win-zxy-harness，分叉保存须先审精确增量；本记录不执行或授权新的Git写入。

本轮只写批准/隔离记录，不改生产文件、测试断言或治理规则。
