# WD-010 第3轮执行报告

2026-11-05，DIB / IMPLEMENT / FIX，第3轮。仅处理独立复核 R2-FR-01：已确认交易成功的结果排入FX队列后，同源服务端401使旧delivery快照失效而丢失终态。完成定向修复和检查，提交DLA审阅；不自认review、真机或Owner UAT通过。

## 固定身份与范围

仓库：C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java
HEAD：70ccc3361ecd90e6c67828bac581a6975ebdccb2；分支：codex/win-zxy-work。本轮未执行Git写入。
第2轮指纹：aeda3627d82d8d5b7c9751dfde57c366d59ed65f176018daa8e912099d0e67ef
第3轮最终指纹：6de1cbfd7a26442edf44ee12c519a957bcd60c4f2366a6ae9b291944261f94c0
累计40个批准范围内变化文件；相对第2轮仅3文件：CloudAccountManager、CloudAccountDialog、批准测试目录新增QueuedDeliveryChecks。原始起点、Contract revision1、批准和Journey不变。逐文件SHA见evidence/r3-IMPLEMENTATION_CODE_IDENTITY.json；本轮精确差异见evidence/r3-DELTA.diff。

第1轮归档recovery/implementation-round-1完整保留。第2轮报告/receipt/submission在覆盖前按原字节保存于recovery/implementation-round-2，报告SHA32441403744dde13d0b4f4ce41aa1a5506399a091ffac2d0e26f091a887ac118、receipt SHA23da0d576ce079b1dea99579020bbde6d7a70f5ac492e406494ce9cf52cabb87；与冻结回执核对相符。各轮原日志及独立审阅记录未修改。

## 最小实现修复

CloudAccountManager.deliverOperation 在实际消费时重新调用operationDelivery，而不是只检查生成结果时的delivery快照。在aha会话锁内验证并交付，避免验证后、显示前再被认证或退出改变会话。只允许原会话或其已登记的同源server-expiry关联；显式logout、重新认证、服务关闭仍切断旧操作，不无条件使用当前会话。

兑换服务完成状态、付款complete及兑换/付款实际FX回调采用同一交付校验。付款继续核对pollGeneration、paymentWindow、窗口可见与closed；兑换继续核对closed并核对当前redeemStage身份，原窗口隐藏再打开仍保留同一兑换操作。

当操作已确认成功但投递时已失效，显示“兑换成功/支付成功；登录已失效，请重新登录”，保留成功事实并更新主账号页，不再显示已经过期的“账号信息已刷新”。未改协议、后台请求/重试规则、兑换新码语义或任何恢复实现。

## 实际验证

mvn -Dmaven.repo.local=.m2repo -DskipTests test-compile，Java17.0.19.10，r3-compile-01.log BUILD SUCCESS，102产品/45测试源码；编译不是测试或打包。

5个套件实际通过，合计222项：
- QueuedDeliveryChecks：84，依据独立审阅真实复现fixture纳入测试目录并扩充。阻塞users/me后阻塞FX，放行200资料响应并等真实执行器空闲，确认成功结果已入队，再触发401。兑换及付款均显示终态、退出进行中、提示重新登录、主窗口回登录页，且不显示“账号信息已刷新”。
- 同一fixture覆盖排队后主动退出、换号、关闭/重开账号窗口、关闭及关闭重开付款窗口、兑换隐藏重开；旧回调不能更新替换账号或新窗口，付款窗口代次失效仍有效。直接覆盖服务层complete在结果创建后同源401、轮询取消、logout和新认证的最终门禁。
- CloudTransactionUiChecks：47，保留上一轮真实交易窗口时序与新兑换检查。
- CloudChecks：52，相关账号/服务回归。
- VoiceFinalChecks：32，相关云端final管线回归。
- CloudUiChecks：7，相关真实UI入口回归。

以上全部本地合成账号/loopback HTTP与真实JavaFX，无真实兑换/付款或键盘输出。完整命令、隔离home、退出码和SHA见evidence/r3-EXECUTION_EVIDENCE.json；日志manifest共6份。git diff --check范围检查exit0。未重跑无变化恢复/设备/全仓套件，其旧证据仍在，不声明本轮重跑。

## 保留的1.0.20构建与失败事实

第2轮Preview完整local-model 1.0.20 EXE已构建成功，但独立审阅FAIL后暂停交付，未preview-finish。产物与阶段记录保留于target/WD010-Preview-R2-LocalModel-1.0.20和target/wd010-preview-build-01。EXE SHA256=3e3cd45ab685a8dc2730b52bc0cdb9c7e286f69671dff13d9a8ab769665b5b29，297409080bytes。

当时已启动的成品验证自然结束：恢复准备61、状态机603、生产UI21、运行竞态7通过；SpeechLifecycleCheck在第125行默认模型关闭假设下exit1，而完整local-model成品model.enabled=true。失败原样保留，批次停止，不能当全套通过；未修改产品配置或原测试迎合该假设。真实JNI/WAV和余下成品验证尚未运行。第3轮只编译和定向检查，没有新包。

## 交接与限制

record-check后submit交原DLA实际/独立复核，冻结本轮报告。Owner无须转发或审批。通过后由DLA新preview-open快照继续1.0.21完整本地模型EXE，保留1.0.20；必须用最终包runtime/JAR/lib验证，执行现有SpeechNativeCheck公共WAV重复与release。云端loopback仅测试依赖jdk.httpserver缺失时使用完整JDK+成品JAR/lib并注明JVM差异。既有model-disabled生命周期检查须如实说明配置适用性，不改变local-model产品配置。

没有安装、kill、下载、真实设备写入/烧录、线上账号/付款或Owner UAT；正式恢复v2固件Gate/Artifact配对仍需DLA只读核验，不把mock或已构建EXE当真机PASS。未修改Harness核心、REVIEW、批准、Firmware/eternal或无关脏文件。
