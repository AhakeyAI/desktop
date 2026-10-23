# WD-005 当前审阅入口更新授权

2026-10-17，Owner 在原 DLA 对话明确答复：

> 允许：保留旧记录，更新当前 REVIEW 入口

问题范围：Preview 工具仅读取根 REVIEW.json；允许保留旧 REVIEW 完整原字节及历史路径后，将当前入口更新为第三轮原 DLA actual review。

旧入口字节已保存于 .ahakey-desktop-harness/changes/WD-005/contract-revisions/20261017-reference-reconcile-before/REVIEW.json，SHA256 7308f435fbdbfe8e5e9cfebc036ce37e8cbdad33b7cf74fd12a4cd5a88ffb5c1。
不覆盖历史批准、报告、起点、旧 pack 或 fresh；不使旧 fresh 自动适用于新 pack。此前隔离 Preview 构建授权继续有效，DLA只准备、DIB构建；不授权启动应用、Hook/设备写入、烧录、发布或Git写入。
