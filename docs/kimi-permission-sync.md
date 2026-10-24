# Kimi 拨杆与会话权限

macOS 的 Kimi Code 配置同步只影响**新建会话**。已打开和恢复的会话保留其会话权限；切回手动档后，要在这些会话中运行 `/permission` 选择手动模式，或用 `/yolo` 切换。PreToolUse 不替代 Kimi 自身的审批，手动档也不把所有调用改成 deny。

已安装 AhaKey Kimi hooks 时，实体自动档将 `default_permission_mode` 设为 `yolo`；已有 `auto` 值会保留。手动档、Agent 启动、断连和未知状态将新会话默认值设为 `manual`。Agent 每次收到实体状态都会核对配置，失败后下次确认重试；断连时定期重试恢复 manual。未安装 AhaKey hooks 的配置不参与这些自动改写。

配置优先使用显式 `KIMI_CODE_HOME/config.toml`，即使目录尚未创建；否则选择 `~/.kimi-code/config.toml`，仅在没有 Kimi Code 数据目录而存在旧配置时回落 `~/.kimi/config.toml`。旧版 Python kimi-cli 保留 `default_yolo` 同步与既有补丁流程。
