# 工作证据（v0.3）

保存实际调查、Owner 指派/范围批准、测试日志/截图与反馈；敏感数据脱敏，private/ 默认不入 Git。
每项外部源码/协议引用在 changes/<ID>/REFERENCES.json，helper pin-ref 捕获实际文件 SHA 与 HEAD。原 firmware/REFERENCES.json 保留为历史资料，不自动成为当前任务依据。
证据路径用接收仓相对路径，禁止越界/链接。只有实际存在的日志/产物才引用；测试记录不证明测试真发生，Owner 反馈不能由 DIB 代填。
HARNESS_FEEDBACK 用于记录规则缺陷，Owner 决定正式升级，运行角色不能自行改规则或用临时提示词长期绕过门禁。
