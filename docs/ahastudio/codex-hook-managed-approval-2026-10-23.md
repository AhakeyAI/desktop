> **已被本次用户确认的新规则取代**：以下保留历史诊断证据，不再作为当前验收要求。当前规则见 [Codex 可选审批与原链路回退](codex-optional-approval-2026-10-23.md)。旧文中的 PreToolUse deny 与 Hook 自动改策略均已移除；拿不到 AhaKey 自动授权时交回 Codex 自身流程。

# Codex 审批从持久开关改为每次请求授权

日期：2026-10-23。对应总 WBS H02-CODEX-LIVE，优先级 P0。此文是本批修复的需求/审查基线。原始语义仍是实体键盘控制自动/手动，失联或不能验证时不自动批准。测试不代替最后的实体拨杆验收。

## 原因与证据

旧实现自动档把顶层 `approval_policy` 写为 `never`，手动改回 `on-request`。真实 Codex CLI 0.162.1 的同一常驻会话表明：文件已改回手动，后续 PreToolUse 仍报告 `bypassPermissions`，并继续执行临时标记命令。六个生产生成的 Hook 均受信且实际执行；不是“文件写入失败”或“Hook 没加载”。原始失败探针日志为本机 `/tmp/ahakey-codex-live-policy-red.log`。

[该版本的权限模式映射](https://github.com/openai/codex/blob/rust-v0.162.1/codex-rs/core/src/hook_runtime.rs)取自当前 thread/turn 的策略。另不能仅看 JSON schema 就发送 PreToolUse `ask`：该版本[实际解析与反例](https://github.com/openai/codex/blob/rust-v0.162.1/codex-rs/hooks/src/events/pre_tool_use.rs)会把不支持的 ask/allow 标为失败并放行；本修复只使用已真实验证的 PermissionRequest allow/原生询问与 PreToolUse deny。

## 决策与行为

1. 新安装和新会话准备 `on-request` 原生基线。生产不再生成 `never` 或新自动租约。自动档只对当前 PermissionRequest 返回 allow，依旧要求 Agent 的完整实时档位/绑定证明及本地未暂停管理；手动、失联、暂停、不能验证均交还原生审批。原生策略本来允许的安全工具仍按原生规则处理，不承诺每个工具都弹框。
2. App 升级时撤回旧版本拥有租约的 `never`；没有所有权标记的用户策略不由迁移函数认领。旧弃用 scalar 的兼容迁移保留。无配置时清掉过期租约；损坏租约不认领用户策略。
3. 旧的已打开免审批会话无法靠文件改写变成原生询问。因此它的每次 PreToolUse 单独查询最新授权；只有验证有效的自动档可继续。手动、离线、暂停或不完整证明返回 deny，工具不执行，并提示启用原生审批或新建使用原生审批的会话。若用户显式选择了免审批命令参数或 GUI Full Access，文件基线不能覆盖该设置；应在 Codex 内恢复原生询问。不能承诺只退出再进入同一免审批会话就自动恢复。新建原生审批会话后走新基线。这是一次升级边界，不能把 deny 描述成已经显示原生批准框。
4. 明确的 `permission_mode=default` 不额外读拨杆，审批仍由 PermissionRequest 接管。其他/缺失模式按需要校验处理。权限模式使用既有 stdin 解析，不复用任务元数据 64 KiB 上限；大补丁不因此被误挡。工具文本不加入授权请求。
5. 策略准备接口不接受“是否自动”参数，避免把短期授权再写成持久免审批。旧字节编辑/租约 fixture seam 保留为模块内部，仅用于重现旧配置及兼容反例。

## 验证要求

- 实际 Handler 注入临时 IO：默认模式不额外查审批；旧 bypass 的有效自动、手动、离线、不完整回复、暂停、未知模式；大输入不误判；现有任务状态/metadata 不变。
- 字节写入保持、旧租约升级/缺失文件/损坏所有权、原生基线与用户未拥有策略区分。
- `scripts/verify-codex-live-approval.py`：真实 CLI、生产配置/输出模块、临时 CODEX_HOME、回环 Responses 服务，模拟五个顺序状态（自动、手动、离线、暂停、恢复自动）。自动与恢复须真正执行临时标记，其余须进入原生请求并由测试拒绝。
- 同命令加 `--legacy-bypass`：重现旧会话缓存 bypass；其余三种非自动状态必须阻止标记执行，恢复有效自动才重新执行。始终保持同一会话，不把重启 CLI 偷换成热撤回。
- 夹具先确认有效配置使用回环 provider，无外部 notify/MCP，六个 Hook 受信启用；只使用虚构授权事实，无账号/云端模型/实体 BLE/真实 IPC 参与。实际 Agent 证明门由 Handler 单元回归覆盖，两层证据不冒充完整真机端到端。

## 交付边界

已验证 CLI 0.162.1，完整旧版/GUI/异常退出/配置变体矩阵仍需继续。安装提示要求已有会话重开一次。本批不修改正在使用的真实配置、已安装 App、键盘键位/语音或 Coffee 素材；最终实体测试前另构建安装候选。
