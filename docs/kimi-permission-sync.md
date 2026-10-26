# Kimi 拨杆与会话权限

本轮产品范围包括普通 Kimi／Work 桌面端、Kimi Code Desktop 和官方 CLI TUI。目标是：实体自动档为完全自动、不再询问；管理全部已明确授权的会话；键盘断连、暂停后台或退出 Studio 后恢复接管前的设置，并保留能识别到的用户后续主动修改。

## 当前已实现：新会话默认配置

安装 AhaKey Kimi hooks、且有新鲜的实体档位与有效出厂绑定证明时，原生配置的 `default_permission_mode` 自动档写为 `auto`，手动档写为 `manual`。旧 Python 配置仍使用 `default_yolo` 的 true／false。这里同步的是新会话默认值，不能用它证明已经打开或恢复的会话也已切换。

接管前的原始标量与写入意图保存在私有日志中，支持进程重开后核对。断连、暂停、退出及卸载按托管记录恢复原值；不会统一强制写成 manual。重复状态不会反复重写。若检测到用户另行修改，保留该值；下一次明确拨杆动作重新核对并以用户的新值作为恢复基线。没有有效实体状态不会凭空授予自动权限。

配置优先使用显式 `KIMI_CODE_HOME/config.toml`，否则选择 `~/.kimi-code/config.toml`；仅在没有 Kimi Code 数据目录而存在旧配置时回落 `~/.kimi/config.toml`。未安装 AhaKey hooks 的配置不参与托管改写。

## 尚未完成：三个产品的运行中原会话控制

需要分别核实当前原会话持有者、权限读写及恢复接口。官方 web/server 的会话设置接口，不等于能控制用户独立运行的原版 TUI 或另一个桌面产品；不能另开托管副本冒充原会话。当前不能把默认配置同步标为三端实时权限控制已完成。

PermissionRequest／PermissionResult Hook 用于观察等待和继续执行。PreToolUse 以及观察事件不替代 Kimi 原生审批；没有取得自动授权时继续原链路，不返回拒绝来拦截正常操作。

源码与接口调查见 [2026-10-25 调研记录](ahastudio/kimi-runtime-permission-api-research-2026-10-25.md)。真实原会话跨档、下一轮执行、恢复原值和用户修改保护仍需完整验收。
