# Agent 交接回退后恢复未完成：待修复

build574集中验收发现：Agent已选中，但设备信息显示App实际连接、Agent进程运行而BLE未连接。此前弹出“Agent已安装但未能启动，已临时由App直接连接”的警告。当前没有证明启动超时的根因。

在设备信息中再次点击已选中的Agent没有恢复；正常切换到App再切Agent后恢复。随后三次间隔5秒的只读查询均为connected=true、physicalSwitchState=0、approvalAutoVerified=true，连接代次不变。未写入任何键盘配置或新增会话授权。

这证明可手动恢复，不证明无干预恢复通过。后续需在生产所有权交接路径复现“启动探活超时→App回退→Agent稍后恢复”，确认App释放和Agent重试的状态一致性，再实施修复与回归。不能仅延长超时或隐藏警告就关闭问题。候选代码位置：AgentManager.applyBluetoothConnectionOwner内socket探活和App回退分支。

已读回16键、待机和Mac平台选择；Claude F18/App本地转写保留，Codex Right Alt不变。最新设备电量82%，早前约10%的读数不足以确认供电导致断连。固件标识是协议身份1.0.1-r001，不代表独立校验HEX哈希。
