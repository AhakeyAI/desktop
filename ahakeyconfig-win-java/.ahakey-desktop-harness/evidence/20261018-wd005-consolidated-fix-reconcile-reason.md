# WD-005 汇总修复合同修订依据

Owner 已在当前对话授权把本轮所有问题与蓝牙上传一起按 Harness 修复。

UI-01/LOG-01/UP-01/UP-02/FB-01为原范围缺陷；UI-02/03和RT-01/02涉及明确交互/运行态职责扩展；RT-03与BLE性能包含外部依赖。因此选择一次 WD-005 contract-reconcile，而不是把所有问题伪装为原两点快修，也不重开已关闭WD-004。

新增批准资产 PREVIEW_FIX_CONTRACT_R3_20261018.md 和 CROSS_COMPONENT_WORK_20261018.md。原合同、引用、设计/验收、批准、起点和各轮审阅报告不覆盖。修改前change.json/STATE已逐字节备份到changes/WD-005/contract-revisions/20261018-preview-consolidation-before。

新增Windows精确路径：HookDispatchServer.java、CodexSessionDiscoveryService.java、AiRuntimeSlotBinding.java、AiRuntimeStore.java；文件内职责受新增合同约束。旧AiRuntimeDisplayService仅允许补发的限制仅针对本轮明确会话归属/假成功修复扩展；其他行为继续保护。J005/J006用户旅程沿用；classification增加bug_fix，保留high_impact。

外部桥接/固件任务在Windows记录需求和依赖，由其所属工作区执行正式流程，不把../或固件绝对路径塞入Windows allowed_paths。现有CP2线协议引用未变；未来固件交付再版本化核验，不将调研候选根因登记PASS。

preflight观察到global IMPLEMENT/PREVIEW_FIX而change.phase VERIFY不一致。本轮不手改phase或规则，contract-reconcile按支持流程生成新revision/effective approval/IMPLEMENT路由；若仍阻塞则如实报告维护需求，不repair-origin或改seal。

原PREVIEW_FIX_REQUEST仅两项，保留历史但本轮DIB须使用新revision普通IMPLEMENT/submit，不复用旧token。源码起点、历史dirty/preserved foreign、旧报告和失败证据全部保留。
