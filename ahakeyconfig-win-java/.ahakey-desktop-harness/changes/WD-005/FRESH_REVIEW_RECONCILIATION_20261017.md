# WD-005 fresh review 核验与正式路由

日期：2026-10-17。角色：原 Windows DLA。

## 结论与来源
独立 fresh actual review 绑定第二轮固定 pack，经本轮核验后使用正式 record-check 登记 review pass。
Harness 自动路由 VERIFY / CANDIDATE_PREP，next_actor=DLA；guard-status 返回 actual DLA review PASS。
STATE.status 仍为旧描述 awaiting_actual_diff_review；本轮不手改 STATE，以正式 review check 和 mode/next_actor 判定路由。

- pack canonical SHA256：2e7ab919025f1b0ca1ae339d01eb3d9fffeb8825c35a938adec008f0110f8ab0
- code fingerprint：aea60d8c7eb936cb937cc59522fed7224c845ecf7947cedb17e8f029ad1656c8
- HEAD：41c034171e60b2d4962b0adbe8f3cffbf80a0436
- audit-run UUID：a2ff1e32-d619-4803-bd54-bc94917d329f，不是 Codex thread UUID；此记录与本地哈希不是身份认证。
- 累计24个路径与 fresh per_file 一一对应、无重复，每项有实质分析；F1/F2/F3/R1均为 pass。
- 原 fresh SHA256：701b045782d43962a5a37a270a480dfd5f3e586c47060fc1e7ec767f302e2458。
- 原 REVIEW SHA256：7308f435fbdbfe8e5e9cfebc036ce37e8cbdad33b7cf74fd12a4cd5a88ffb5c1。

## 追加记录，不覆盖历史
原 fresh 的 review_session_id 和结构化分析不是 Harness 期望的 session/analysis。
新增 FRESH_REVIEW_BINDING_ROUND_2_20261017.json，仅映射字段并完整保留原 fresh 所有字段：
SHA256 167aa3ee4539b90f68067e1690360b48a8be46f2671f644622952636968efc2d。
新增 FORMAL_REVIEW_ROUND_2_20261017.json，保留原 DLA 分析、风险、逐文件和问题结论，
补充 fresh 引用，并嵌入原 fresh 内容及回填前 verification/保护哈希：
SHA256 22febdb448c0bb6fe7de9e613520e3ce4c9f94f1a00550473a51efc3cb711a60。
正式 verification.review.evidence 指向此补充 FORMAL 文件，不是旧 REVIEW.json。
原 REVIEW 中的 fresh pending 是当时快照，不得据此覆盖当前 formal pass。

回填后逐项核对：原 REVIEW、原 fresh、固定 PACK、ACTUAL_DIFF、原 actual Markdown、
change批准、start、冻结基报告、IMPLEMENTATION_RECEIPT 共9个文件哈希全部不变。
verification 仅 review 项变化，machine/core_regression/special_regression/mock/real_device/owner_uat保持原值。

## 保留观察与缺口
失败的灯条回读也将OLED设备事实置未知；已核对 DisplayConfigService.refresh 及
OledResourceState.unknown：本地asset、localStatus和历史metadata保留，不产生设备写入。
作为保守状态显示观察保留，不认定已证实数据丢失，不据此扩大修复scope。
283项仍仅175离线、36隔离FX/服务、72受控竞态；本轮没有重跑。

Git candidate、可运行包、Preview、完整UI/DPI、A01-A11余项、Firmware identity、
USB/BLE物理测试及Owner UAT均待后续完成。没有新构建、启动、Hook/设备/固件或Git写操作。

## 下一步
原DLA继续候选/Preview准备，不重复产品Grill。构建或Git写入仍须单独授权。
候选记录清单须明确检查包含补充FORMAL、映射文件和原fresh；
closure_assets只自动从原REVIEW追踪fresh引用，不应仅凭默认清单断言追加证据全已存档。
不能为补齐清单修改原报告、规则、seal或降低门禁。
