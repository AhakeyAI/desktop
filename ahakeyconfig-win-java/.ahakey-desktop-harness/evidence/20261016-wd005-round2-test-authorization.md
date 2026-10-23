# WD-005 第二轮机器检查授权

Owner 在当前 DIB 对话回复：“我授权”。

对应上一条明确请求：本轮仅本地编译与离线、隔离 JavaFX 测试，
不打包、不启动正式应用、不访问设备、不做 Git 写入。

允许执行本地 test-compile 和 DisplayConfigChecks、DisplayConfigFxChecks、
DisplayConfigRaceChecks；保留日志、退出码，修复合同内真实失败。
这不是正式交测包、设备操作、安装 Hook、烧录、发布或 Git 写操作授权。
原批准、起点、冻结报告和前轮未执行记录不重写。
