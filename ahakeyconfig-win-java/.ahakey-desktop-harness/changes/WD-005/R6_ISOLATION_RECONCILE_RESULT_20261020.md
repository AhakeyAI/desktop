# R5-F1 隔离接口协调结果

Owner 明确批准窄范围补充后，2026-10-20 DLA 正式运行 contract-reconcile，退出0。实际结果：revision4/build_round7，STATE=IMPLEMENT/IMPLEMENT，next_actor=DIB。不是手写路由，也没有修复 origin。

新增批准资产 R6_ISOLATION_INTERFACE_PROPOSAL_20261020.md 已正式绑定；文件中的“待确认”描述为协调前历史状态，以当前 change.json 的 effective approval 及本结果为准。Owner证据及理由分别为 evidence/20261020-wd005-isolation-interface-owner-authorization.md 和 evidence/20261020-wd005-isolation-interface-reconcile-reason.md。旧 change/STATE 原字节见 contract-revisions/20261020-r6-isolation-before/；正式工具另追加合同修订历史。未修改旧批准资产、起点、审阅或冻结报告。

协调前后源码指纹相同：1fca9345199cd1166acd8b4df7125d3e17f1cad4032c7736dc1060361a2d3ccf。

执行记录：
- contract-reconcile --id WD-005 --owner-record .ahakey-desktop-harness/evidence/20261020-wd005-isolation-interface-owner-authorization.md --reason-record .ahakey-desktop-harness/evidence/20261020-wd005-isolation-interface-reconcile-reason.md --role DLA：退出0。
- preflight --id WD-005 --role DLA：退出1，DLA preflight routing mismatch: next actor is DIB。属已派工DIB后的角色限制，没有改路由或以DLA冒充DIB继续；由DIB接手重新preflight。
- guard-status --id WD-005 --role DLA：退出0，immutable origin / scope / governance PASS；submission旧轮、review及candidate/build/delivery仍pending/blocked。不是产品PASS。

本轮仅治理记录，无生产/测试/桥接/固件改动，无编译、测试、打包、真实应用、设备或Git写入。下一步DIB按revision4/round7实现测试隔离，先静态确认真实I/O全部截断，再执行适用离线回归，新增执行报告并按实际结果record-check/submit。旧443项不自动继承新轮PASS。R5-F1仍未解决；上传根因、来源缺失事件、RT-03、BLE性能、完整应用及配对验收仍待办。
