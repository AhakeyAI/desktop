# Phase-scoped Evidence — v1.3

- IMPLEMENT：`EXECUTION_REPORT.md` + `builder_submission.json`；submit 生成 `IMPLEMENTATION_RECEIPT.json` 冻结实现身份。之后不得回写该 IMPLEMENT 报告来记录 build/preview。
- VERIFY：`REVIEW.md` / `REVIEW.json` / review pack。
- PREVIEW：`previews/<id>/<token>/START.json` + `PREVIEW_RECEIPT.json` + `OWNER_PREVIEW_RESULT.json`。
- PREVIEW FIX：每轮独立 `previews/<id>/fixes/<token>/SUBMISSION.json` + `REVIEW.json`；不得覆盖 formal IMPLEMENT/REVIEW 证据。
- CANDIDATE：`candidate.json` + immutable Git commit。
- BUILD：每个 token 独立 `BUILD_REPORT.md` / `RECEIPT.json`，汇总 `BUILD_RECEIPT.json`。不要追加修改 `EXECUTION_REPORT.md`。
- OWNER TEST：`OWNER_TEST` / `test_packet` / `OWNER_RESULTS`。

后续阶段新增证据不反向改变已冻结的前阶段代码身份。Formal candidate 成立后，以 immutable Git commit 为正式 source identity；工作区治理文档追加不应使 candidate 自身失效。
