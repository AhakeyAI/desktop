# R3：Hook 检测与更新一致性

原合同明确排除 Hook 管理扫描/升级策略，本轮 Owner 已明确批准该范围，故以 Contract revision 纳入，而不冒充原范围内修复。

实证：../../evidence/20261103-hook-status-diagnosis.md。实际 Codex 脚本及管理事件与当前生成版本一致，而 sidecar 为旧版本；隔离复现仅改变 sidecar 就改变检测结果。当前 installOrUpdate 每次重写全部平台脚本，成功未回读核验。TopBar 每次进程首次扫描到待更新会弹提示。

本轮复用 Journey J014（Hook 管理检测与更新一致性），bug_fix + scope_expansion，保留任务既有 high_impact 独立审阅。生产仅 HookInstaller、TopBar，测试位于已允许 wd009 目录。保留既有审批/灯光/平台路径及其他所有生产改动，不引入 WD007 模块。旧冻结审阅与实现报告仅作历史，新实现与新审阅另行绑定。
