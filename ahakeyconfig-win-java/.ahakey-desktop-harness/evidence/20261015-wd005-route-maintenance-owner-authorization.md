# 历史任务路由维护授权

Owner原话：
> 我独立授权按正式维护流程处理历史任务路由，保留旧合同、批准和起点，不修改产品代码、不降低门禁。

目标：纠正根STATE仍指WD-002的历史路由，保持一个活跃实现，为已批准WD-005准备正式登记。
优先使用既有正式suspend命令，记录实际结果；只暂停，不关闭/验收WD-002，不重启旧产品工作。
已有历史暂停依据：evidence/20261005T180000_suspend_wd002_for_wd003.md。
WD-004关闭依据：changes/WD-004/CLOSE_RECEIPT.json。
产品范围批准：evidence/20261015-wd005-owner-scope-approval.json。

不重写旧合同、approval、start-fingerprint或guard-origin；不修改生产代码。
不自动Git写入、构建、设备写入、烧录或发布；不绕过保护印章/可恢复性检查。
若正式命令被缺失前置阻止，保存失败证据并区分数据缺口和工具缺陷；
需要核心维护时必须独立审阅且保持等效或更严格保护，不能删除检查凑PASS。
