# WD-005 正式 build-only 与直接接续授权

日期：2026-10-22，来源：当前原 DLA 对话中 Owner 直接消息及工具问题的直接答复。

## 对话接续

Owner 原话：

> 今后所有要再别的对话继续或则和在本对话继续的你都可以直接发起

据此，DLA 可直接向已有 DIB 实现对话「DLB」发送本任务接续信息，不要求 Owner 手工搬运。此授权仅为对话协调，不自动授权代码扩展、构建、Git 或设备动作。

## 本次正式构建

DLA 提问原文：

> 正式收尾还缺绑定 Git 候选的 BUILD_RECEIPT；现有 Preview 回执不能直接改成正式回执。是否授权我直接交 DIB：仅对候选 e08524c 离线构建 JAR/classpath 正式包、保存日志与回执，并与已测 Preview 对比？不改源码、不启动应用、不安装、不操作设备、不执行 Git 写入。

Owner 答复：

> 授权这次 build-only（推荐）

## 精确边界

- 候选 e08524cc07077a06d34b79130ddea074355ea2fb，WD-005 revision5 / round9。
- 源码指纹 98fe4428d5187e7f900a30df99b2432c7a540fcc02f7707a7aa1ac659d2213b9。
- DIB 通过正式 preflight/build-open，离线 JAR/classpath package，保留完整日志、退出码、依赖及回执；DLA 不代构建。
- 可核对新包与 preview-20261021T024920511394Z-2ae03d 的 ZIP 条目内容及运行依赖；区分压缩/时间戳差异和真实代码/资源变化，不宣称未执行的启动或测试通过。
- 不修改生产/测试/pom/固件/桥接/Harness，不覆盖冻结报告、Preview 或旧产物；不 clean、下载依赖或模型、启动应用、安装 Hook、连接设备、写设备、烧录、发布、Git 写入。
- 不把构建授权当正式 UAT PASS；已有 656 项为原执行证据，不冒称本次重跑。
