# WD-005 引用协调授权

来源：2026-10-17当前原DLA对话，Owner直接回复“我授权”，并完整发送REFERENCE_RECONCILE任务。
授权仅针对CP2-ARCH、CP2-EXECUTION两项Windows引用登记作正式版本化协调。
保留旧批准、起点、审阅和固件原文，不修改规则或seal，不增加CP1.5功能。
允许正式流程对有效批准/提交/审阅身份及路由产生必要影响，但必须如实记录，不伪造旧fresh对新pack的绑定。
此前隔离Preview构建授权继续有效；不授权启动应用、安装Hook、设备写入、烧录、发布或Git写入。

本轮采用固定CP2 gate中锁定的原合同哈希及candidate_commit作为两项引用的稳定锚点；不采纳CP1.5新增设计。
若流程需DIB无源码变更重新提交，则按实际角色交接，不由DLA冒充DIB；Preview需等待有效前置恢复。
