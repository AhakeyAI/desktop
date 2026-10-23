# WD-005 Preview 准备受阻记录

日期：2026-10-17；角色：原 Windows DLA。
Owner构建授权：.ahakey-desktop-harness/evidence/20261017-wd005-owner-preview-build-authorization.md。

## 已核对
- Windows当前代码指纹仍为 aea60d8c7eb936cb937cc59522fed7224c845ecf7947cedb17e8f029ad1656c8。
- 原DLA/fresh正式审阅记录保留；STATE仍VERIFY/CANDIDATE_PREP。本次未修改STATE/verification。
- 固件HEAD仍08dd24a6e8ce3526fef36661f5c97940add98a25。
- 12项REFERENCES逐项重算：10项匹配，包括命令实现、资源表、上传、配置、预览、灯效及CP2 gate。
- 两项变化来自固件工作区的CP1.5 revision 3设计更新；git diff只见CP1.5部分更新，未修改CP2合同语义。
- 固件HEAD中的两份原文blob哈希与Windows原批准精确匹配，历史来源仍可恢复。

## 精确阻塞
guard-status当前返回：Pinned reference changed/missing: CP2-ARCH; DLA reconcile before using old approval。
builder submission / actual DLA review当前就绪检查因此blocked，不是已发现新的Windows功能缺陷。

CP2-ARCH：.ahakey-harness/workstreams/X1-AI-WORKFLOW-PRESENTATION/ARCHITECTURE.md
- 原批准/固件HEAD：9b087f5ac11b706c3a4c7096868dbe307daca87651b3d0db00218c21239a1e16
- 当前工作区：e6efebe8adc8247061e7d03f6b2778c0d029717257bec02c016d01c3e1d968a0

CP2-EXECUTION：.ahakey-harness/workstreams/X1-AI-WORKFLOW-PRESENTATION/EXECUTION.yaml
- 原批准/固件HEAD：b76711f91bef4b716023a6082a1bfc42e4711233a50b243119f51d8d0fd8783a
- 当前工作区：47f4bd6f54a978d83aa13109f1f73e5baae6a36db5692020c40b466adbd9a550

没有执行preview-open：其preview_basis先调用submission_ok，会在引用核验失败，不能得到合法快照。
没有编造token/source路径，也没有调用内部make_preview_snapshot绕过入口。
已读取contract-reconcile实现：会提升revision/build_round、更换有效批准并路由IMPLEMENT/DIB。
这不是无副作用的引用刷新；本轮不执行，不改REFERENCES原哈希，不恢复固件文件，不修改规则或seal。

## 隔离与构建方式的已知信息
原隔离记录保留config_server.json、rollback证据及并列BLE包，未写Git或修改原件。
本任务目前没有preserved_foreign_inputs.json；不能声称已登记此文件。正式preview-open按HEAD重建并只叠加allowed_paths。
pom.xml使用Java17；package包含jar及runtime依赖复制，无应用启动执行绑定。
本机JDK路径D:/jdk-17.0.19.10-hotspot/bin/java.exe存在；Maven为C:/Program Files/apache-maven-3.9.12/bin/mvn.cmd。
后续DIB须核对实际版本及缓存；仅在合法隔离source中package，不clean主target、不跑安装器或下载模型。
主产物预计ahakey-studio-1.0.0.jar及lib；实际身份须由构建结果确认，不拿旧target冒充。
已有com.example.ahakey.Main包装入口转入App；后续启动配方优先明确classpath和Main，避免单纯java -jar的JavaFX入口问题。
本轮没有运行Java/Maven构建或应用，故不宣称启动成功。

## 下一步
需原DLA先获得针对引用登记的窄治理授权，核对并采用正式协调流程，保留全部旧批准和审阅。
不得把CP1.5纳入WD-005功能scope。若合法协调必须使approval/pack身份变化，应如实处理相关证据路由，不重写旧审阅或伪造fresh绑定。
若现有工具不能保持本次边界，报告Harness维护需求，不自行修改规则。
恢复有效Preview前置后再使用已有构建授权开启隔离快照，给DIB真实token、source路径和build-only提示词。
本轮无构建、包、设备操作、Hook写入或Git写入；不能交Owner测试。
