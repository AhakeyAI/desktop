# WD-005 第七轮复审及 Preview 接续授权

来源：2026-10-20 原DLA当前聊天，Owner原话：

> 好的，那你现在就继续做第7轮的实际复审吧，按 Harness 流程走，没问题就推进到 Preview 打包，不要再重复协调已经确认的事情。

适用：revision4 / round7，DLA实际审阅；无阻断后通过正式preview-open固定隔离源码，再交DIB仅构建可运行JAR/classpath包。沿用已批准产品与测试接口范围，不重开产品Grill，不修改生产代码或扩大为EXE发行。

允许为Preview工具维护当前REVIEW入口，但先保存旧原字节；旧批准、报告、起点、固定包和fresh保留。原DLA实际审阅与正式high-impact fresh分层，不给未完成的正式审阅/真机/UAT标PASS。

本授权不包含自动启动应用、安装/更新Hook、连接或写设备、烧录、发布或Git写入。DIB构建失败需保留真实日志回DLA，不改冻结快照或自行扩大修复。
