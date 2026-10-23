# Claude 手动审批的 PermissionRequest 输出

范围：H02/Q01。前置基线 d826a51；不修改实体拨杆、配置所有权或用户权限规则。

[官方 Hook 接口](https://code.claude.com/docs/en/hooks#permissionrequest-decision-control)中，PermissionRequest 的决策仅支持 allow/deny，不能把 PreToolUse 的 ask 决策移植过来。旧 ClaudeHookHandler 在手动、离线、暂停或无法验证时仍输出 decision.behavior=ask，格式不符合该事件合同。

## 行为合同

- 自动档只有经现有完整实时证明及本地启用检查后，才输出 PermissionRequest 的 allow。
- 手动、暂停、离线、未知或证明不完整时，输出空 JSON，不返回许可决策，让 Claude 原生权限流程继续；不以 deny 代替用户审批。
- PreToolUse 的已有仅验证自动时放行规则不变。诊断日志中 ask 表示“交回用户”的意图，不是发给 Claude 的决策值。
- 不扩大自动批准范围，不写用户允许规则，不修改其他 CLI 输出。

## 验证

生产输出函数及实际查询超时路径的回归先失败：11项测试共15处断言失败。修复后完整605项 Swift 测试通过。测试覆盖自动/手动、缺失或不完整证明、暂停和超时不会复用缓存自动状态。

上述证据证明生成输出及证明门控，尚未证明真实 Claude TUI 已显示审批框；真实 CLI 的安装重装/移除及常驻配置重载仍沿用已有独立证据，不能因为这些通过就声称本次 PermissionRequest 已做完整真实模型验收。后续签名包和实体档位检查分别记录。
