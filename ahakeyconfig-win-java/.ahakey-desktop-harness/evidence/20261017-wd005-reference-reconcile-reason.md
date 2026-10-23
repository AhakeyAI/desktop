# WD-005 两项引用的版本化协调依据

## 原因与范围
Windows功能代码指纹仍为aea60d8c7eb936cb937cc59522fed7224c845ecf7947cedb17e8f029ad1656c8。
两份共享固件文档仅追加/修订CP1.5 revision 3设计，当前Windows引用按整个工作区文件哈希核验而被阻塞。
其余10项固定引用匹配；CP2资源、命令、配置、上传、灯效实现及原gate未变。
不修改Windows产品合同、allowed_paths、验收、固件线协议或功能代码，不加入CP1.5。

## 稳定依据
固件根：C:/Users/20825/Desktop/vibe-code（全程只读）。
候选commit：08dd24a6e8ce3526fef36661f5c97940add98a25。
固定gate：.ahakey-harness/evidence/checkpoints/X1-AI-WORKFLOW-PRESENTATION/CP2/20261015T185611/gate-receipt.json。
实际SHA256：f9d0849a8a54b58dee20c2e11376c0dea2735434632958770a66152454b742c5；result=PASS。
contract_lock.architecture_sha256：9b087f5ac11b706c3a4c7096868dbe307daca87651b3d0db00218c21239a1e16。
contract_lock.execution_sha256：b76711f91bef4b716023a6082a1bfc42e4711233a50b243119f51d8d0fd8783a。
对candidate_commit逐个git show原文并按原始stdout字节SHA256核验，两值与旧Windows引用精确相同。
固定回执只证明原合同/候选身份；协议内容仍由原candidate Git blob及其余10项引用查阅，不用PASS一词替代协议分析。
原架构路径：.ahakey-harness/workstreams/X1-AI-WORKFLOW-PRESENTATION/ARCHITECTURE.md。
原执行路径：.ahakey-harness/workstreams/X1-AI-WORKFLOW-PRESENTATION/EXECUTION.yaml。

## 登记方式及保留
只将CP2-ARCH/CP2-EXECUTION两项path指向固定gate，sha256指向其字节哈希，kind为decision、maturity为observed。
section明确各自contract_lock字段；保留原提交和原文路径/哈希作为original_document元信息。
其余10条不修改。CP2-PROTOCOL等implemented protocol引用继续满足真实协议依据要求。
变更前10份记录已逐字节复制并校验至changes/WD-005/contract-revisions/20261017-reference-reconcile-before。
正式contract-reconcile负责保存旧批准并生成新有效批准和路由，不手改STATE/start/guard-origin。
工具会提高revision/build_round并交DIB，需要重新绑定未变源码的提交证据；这不授权重新实现功能。
旧pack/fresh仅对旧批准身份有效，不覆盖或伪造新绑定。原DLA对新有效输入完成审阅后可开启Preview，fresh正式链另行处理。

## 边界
不得通过恢复固件工作区文件、改seal/规则、手写submission或直接调用内部snapshot函数绕过门禁。
没有构建、启动应用、安装Hook、设备/固件或Git写入。旧机器断言仍仅代表其真实执行范围。
