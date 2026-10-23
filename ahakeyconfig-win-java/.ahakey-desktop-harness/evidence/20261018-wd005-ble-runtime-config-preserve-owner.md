# 本机 BLE 运行配置归属确认

日期：2026-10-18。当前原DLA对话，Owner对结构化问题的实际回复。

问题：是否保留蓝牙测试生成的 BLE_tcp_driver_package/config_server.json，并通过 Harness 将它登记为本机运行配置，不纳入 WD-005 源码修改或候选提交？

Owner回答：保留并登记为本机运行配置（推荐）。

该文件包含当前测试设备选择、监听地址、端口9000和StartMinimized选项。DLA已只读查看，属于本机驱动运行配置，不是本轮生产源码修复。不删除、不覆盖、不恢复，不改动现场连接偏好，不授予DIB对此路径的写入权限，不进入Windows候选/隔离源码。

contract-reconcile最终检查仅报告此项新增兄弟工作区差异；原始guard-origin/start保持不变。用正式reconcile-foreign保存当前快照和本授权，然后重新preflight核验已生成revision 3，不再次执行contract-reconcile制造revision 4，不手改seal/guard/phase。
