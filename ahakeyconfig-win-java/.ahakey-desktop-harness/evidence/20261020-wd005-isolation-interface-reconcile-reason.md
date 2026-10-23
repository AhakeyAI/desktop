# WD-005 R5-F1 测试隔离接口版本化协调理由

日期：2026-10-20；DLA。

Owner 已在同轮结构化回复明确批准窄范围补充，原话见 20261020-wd005-isolation-interface-owner-authorization.md。

仍属 WD-005，保留 J005/J006、high_impact、全部原合同及已确认产品行为，不重开产品设计。allowed_paths 不扩大；仅将 R6_ISOLATION_INTERFACE_PROPOSAL_20261020.md 加入 approval_assets，明确 BleManager 文件内新增职责及测试夹具边界。生产只允许一个默认调用原静态发现的 protected 实例入口以及两处调用替换，其余修改限于 displayconfig 测试目录。

目的：封闭 FakeSession 等测试对静态 USB 发现和真实 Socket 的逃逸，同时保留真实 BLE sendCommand 分支、锁、TTL、连接代次、补发和未知 ACK 隔离；不使用 always-open USB、假 quarantine 或覆写整个发送逻辑逃避测试。

协调前源码指纹实测仍为 1fca9345199cd1166acd8b4df7125d3e17f1cad4032c7736dc1060361a2d3ccf。本次没有生产/测试源码修改或测试执行。

修改前 change.json（含完整旧批准）及 STATE.json 已按原字节保存在 changes/WD-005/contract-revisions/20261020-r6-isolation-before/；其 SHA256 分别为 8da468525270130982bedee81d432424121fe64a347c9e68516256cc670fc757、651284f957ff0c8f2fcbe2f02b1e8cf344fe25cf397be1743a6e0ae67f12a24e。

由 contract-reconcile 正式生成新批准/轮次/路由，不手写 phase/build_round，不使用 repair-origin。保留原起点、批准、冻结报告、审阅/fresh及历史 dirty；旧 443 项仅历史证据，不自动成为新轮 PASS。当前 R5-F1 仍待实现、隔离核验、回归及 DLA actual review。上传根因、来源缺失事件、RT-03、BLE性能及完整应用缺口保留；Preview/fresh/candidate/配对身份/Owner UAT分别收口。
