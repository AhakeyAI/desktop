# 固定已审 Firmware 输入，保持并行实现隔离

2026-10-24 DLA 只读观察到 Firmware 的既有独立流程已经启动 WS4 Restore（当前 HEAD 349350ac9eba4afcb7390552f8756a2698ecddf1），正在合法修改 K1 共享存储及追加 Restore 协议。Windows 不采用这些尚未完成 gate 的工作树字节，也不因外部编辑持续刷新引用哈希。

将本轮已审阅 CP2.6 candidate 2f7c54a927410c59479307c1ebc2b0d20f236d97 的协议登记、命令、存储接口/实现、现有传输源码，通过只读 Git 对象导出到本项 `r9-firmware-snapshot-20261024/`，逐文件记录 commit、blob OID、SHA256，作为普通 approval_assets 受现有合同校验绑定。REFERENCES 保留正式 CP2.5/CP2.6 gate 的外部文件绑定。没有修改 Harness 核心、校验器、印章或 Firmware；没有把当前漂移源码默认为已审。

独立设计审阅已用该 CP2.6 Git candidate 核对 B1。产品/协议采用范围、全部验收义务不变；B1仍待Firmware闭合，WS4新协议和合并HEX仍需未来正式intake。原revision7引用和批准原件已备份。后续DIB只使用导出固定字节及独立审阅，不追随实时Firmware工作树。此为已授权实施输入固定方式的修订，不是放宽协议校验或批准新功能。
