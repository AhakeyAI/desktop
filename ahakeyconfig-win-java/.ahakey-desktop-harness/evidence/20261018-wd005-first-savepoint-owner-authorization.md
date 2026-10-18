# WD-005 第一版当前源码 Git 存档授权

日期：2026-10-18。Owner当前原文：
> 现在我希望你能先把当下的代码也先按WS-005第一版先保存一个版本，git下，避免之后回退不好，然后再告诉我接下来各个支线应该怎么汇总，怎么做

此为Owner明确授权DLA执行一次当前Windows任务的精确暂存、暂存差异核验及本地Git commit，覆盖此前“不自动Git写入”的默认限制；不授权push、reset、clean、stash、checkout或变更其他仓库。

Owner称WS-005，仓库正式ID为WD-005。命名为“WD-005 first Windows source savepoint (unreviewed)”，指当前revision 3/build_round 4源码，不是恢复最早Preview源码，不伪装候选/正式第一版发行。

纳入本任务精确allowed_paths中的当前生产/测试文件，以及最小合同、原始起点、当前报告/检查/证据和保存说明。排除桥接、固件、本机BLE配置、Harness工具维护、其他任务历史dirty、用户数据、构建产物和模型。

预期源码指纹：e298ea1dd15131f508a602deed06181e0a53c6ff8b5c2366674dfc0cfb44d49d。397断言为DIB报告的本轮执行；DLA核对文件/日志绑定但未独立重跑、不据此审阅通过。

Git存档点只提供可恢复源码；不是formal candidate或可交测产物，不改变STATE/旧start/批准/报告，不把旧回执绑定到新代码。保留原HEAD和旧Preview；后续恢复需先保存届时未提交工作，不给破坏性回退指令。

本次不运行savepoint-plan的状态切换，因为该命令会将当前尚未submit的IMPLEMENT路由转成VERIFY/SAVEPOINT_GIT，而本次Owner请求只是并行保存当前源码并继续DIB提交。使用公开Git命令及精确范围清单完成已明确授权的本地存档，不调用candidate-check，不冒充通过任何Harness门禁。
