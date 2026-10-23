# WD-005 第三轮无代码重提与证据适用说明

日期：2026-10-17。角色：Windows DIB。revision=2，build_round=3。
本轮仅证据核验、复用登记与正式 submit，不是第三轮编译或测试执行报告。

## 授权与当前输入

- Owner 本轮明确授权无代码重提；正式协调记录为 contract-revisions/20261017T102202087589Z.json。
- 有效批准来源：../../evidence/20261017-wd005-reference-reconcile-owner-authorization.md，SHA256为88c4a5d87201d3313bf4e96bb933caa743bd6195c27bed4df7a98d4730e07022。
- 新批准时间为2026-10-17T10:22:01+00:00；当前 REFERENCES.json SHA256为1bb3f96c441a6eaa891be6ec3fdc98b58f3e3a45197ba397c26d16027472636f。
- DIB preflight实际退出0；读取到IMPLEMENT/IMPLEMENT、next_actor=DIB、唯一活跃WD-005。历史任务不重启。
- 实际HEAD仍为41c034171e60b2d4962b0adbe8f3cffbf80a0436；原起点和历史dirty保留。
- 正式fingerprint命令实测aea60d8c7eb936cb937cc59522fed7224c845ecf7947cedb17e8f029ad1656c8，与第二轮提交及四项检查相同。
- 本轮未改生产、测试、资源、依赖或构建配置；未执行编译、测试、应用启动、Git写入、设备、Hook、烧录或发布。后续Preview仍须DLA的合法token与隔离snapshot。

## 引用协调适用性

逐项比较协调前REFERENCES.json与当前登记：仅CP2-ARCH、CP2-EXECUTION变化，其余10项登记完全相同；12项当前引用字节均与登记哈希匹配。
两项变化仅改为固定CP2 gate的contract_lock锚点，原文仍是原候选的同一内容，不引入CP1.5。

- 固件候选：08dd24a6e8ce3526fef36661f5c97940add98a25。
- 固定gate：.ahakey-harness/evidence/checkpoints/X1-AI-WORKFLOW-PRESENTATION/CP2/20261015T185611/gate-receipt.json。
- gate哈希：f9d0849a8a54b58dee20c2e11376c0dea2735434632958770a66152454b742c5。
- 用只读git show取得候选原始字节后，ARCHITECTURE.md哈希为9b087f5ac11b706c3a4c7096868dbe307daca87651b3d0db00218c21239a1e16，EXECUTION.yaml哈希为b76711f91bef4b716023a6082a1bfc42e4711233a50b243119f51d8d0fd8783a；均与旧引用、新original_document和gate锁定值一致。
- 当前批准资产逐一核验通过；除REFERENCES外，CONTRACT、DECISIONS、IMPLEMENTATION_SCOPE、PROTOCOL_AND_STATE、ACCEPTANCE、DESIGN_REVIEW、REGISTRATION哈希均与旧批准相同。allowed_paths亦未变。

因此此次变化不改变测试对象、协议期望、产品行为或A01-A11验收要求，第二轮已执行范围可复用。固定固件gate不等于本机设备已刷入或Windows真机通过。

## 测试输入与历史证据核验

正式源码指纹包括以下三份测试文件，其当前SHA256为：

| 测试文件（src/test/java/com/example/ahakey/displayconfig/） | SHA256 |
|---|---|
| DisplayConfigChecks.java | aaca453117ea07bed792b10cc39d80db0b9a9f3b427cfc0cdbcc7526e3622273 |
| DisplayConfigFxChecks.java | 3aa6b3d363936052f001219d702deaf63191ff6e988e37284c7fdab242e2d4a8 |
| DisplayConfigRaceChecks.java | 9ba3dc2155e0dcd8405cfc2988fb024d13573d88095a61cbd213965c3fd7dfc4 |

协调前备份目录为contract-revisions/20261017-reference-reconcile-before。重绑前核验该目录的verification、builder_submission、IMPLEMENTATION_RECEIPT、EXECUTION_REPORT、REVIEW、FORMAL_REVIEW_ROUND_2_20261017、review_pack、start-fingerprint与当前同名文件字节相同。
第二轮报告和检查表实际哈希与该旧verification四项绑定相符：

| 文件 | SHA256 |
|---|---|
| EXECUTION_REPORT_FIX_ROUND_2.md | 47edd5b155d39a65ef8959cfccb3414b9420c3d020a6278b7bb948064cbdf96e |
| IMPLEMENTATION_CHECKS_ROUND_2.json | 92166a4105ddf0e02a192d3be2a5f5ec46288ee5ec0475c4994a2f72e9b72e10 |

以下日志均在../../evidence/，实际字节哈希与第二轮检查表一致；退出码是第二轮记录，不是本轮新进程结果：

| 日志 | 历史退出码 | SHA256 |
|---|---|---|
| 20261016-wd005-round2-compile-01.log | 0 | ed10670395dcc2fb835267f368dd8d5c02504e9f70409173bf8d48c47dd42b77 |
| 20261016-wd005-round2-races-01.log | 1 | 4d6c094b5cab338bafdf34e39a4ee0a45f9b2abae2eb20f65337a4fd2c5c04a8 |
| 20261016-wd005-round2-compile-02.log | 0 | 17767341ed3808dd8a0e14a74399e4e54985ded2a25c94211b835d37adb17878 |
| 20261016-wd005-round2-races-02.log | 0 | 0d92456e623c24648a133205d571e994adae0771d222abcb41e8c08e0893e18f |
| 20261016-wd005-round2-offline-01.log | 0 | c804f7c17d56a1eb13589fd36b73adefbc8999e1905a628e676106e3eb856da2 |
| 20261016-wd005-round2-fx-01.log | 0 | 689798b6712f045661e9df9e44ff48497302f18c19a40d081bb0a2fc6dece372 |
| 20261016-wd005-round2-races-03.log | 0 | ce61296387f74d58b807abee00bf0200300551da09702aec92df3f90cb3afd64 |

原失败仍保留为失败，不删日志、不改变测试预期。原175离线、36隔离FX/服务、72受控时序断言共283项唯一断言；72项重复运行不另计数。

## 四项检查复用范围

| 当前轮检查 | 仅复用的第二轮范围 |
|---|---|
| machine | 已记录的test-compile及三个Java断言入口；本轮只重新核验Harness输入身份和证据哈希，没有再次编译/运行测试 |
| core_regression | 原A10已执行列与F1身份/模式、F2 CP1切换、R1待发事实时序；不包含真实Hook/语音 |
| special_regression | 原A01-A09已执行列与F3旧ACK/FX回调/草稿版本/预览期限；不是整应用体验或全部验收 |
| mock | 内存传输上的真实服务/协议上传、超时、部分保存、互斥和时序断言；不是实体USB/BLE |

四项record-check必须同时引用第二轮报告、第二轮检查表和本说明，绑定当前批准及build_round=3。
该PASS仅表示历史已执行证据对未变输入仍适用，严禁称“第三轮283项重跑通过”。

未验证项原样保留：完整App/Controller与Inspector操作、完整窗口和高DPI、真实USB/BLE/Flash/断电、Hook/语音、全部磁盘故障/迁移/灯效时相、Owner Preview、正式候选/包/固件配对/UAT。没有删减或豁免A01-A11。

## 冻结与后续路由

根EXECUTION_REPORT.md仍是历史基报告，SHA256为749264589c44656848f062fcf3b4ecf35784bef80f7356dc1f204834d69a19a2；正式submit的report_sha256依现有helper仍指向它。本轮适用性须读取verification直接绑定的三份证据，不能仅看根报告判断轮次。
正式record-check/submit更新当前指针，旧verification、submission、receipt已由协调前备份保留；不手写回执、不修改旧批准/起点/报告/审阅。
第二轮DLA/fresh原结果仅绑定旧批准和旧pack，不自动继承为新pack通过。本DIB不登记review、fresh、real_device或owner_uat。
本说明写入时尚未执行四项重绑和submit，最终成功/失败及路由以正式helper输出和新IMPLEMENTATION_RECEIPT为准，不回写本说明制造完成事实。
成功后交原DLA生成当前review-pack、核对实际差异及引用协调；原DLA actual review通过后才能按既有授权开启隔离Preview，交DIB合法token/snapshot。正式配对仍须有效high-impact fresh、Git candidate、真实产物和Firmware identity及实际验收。
