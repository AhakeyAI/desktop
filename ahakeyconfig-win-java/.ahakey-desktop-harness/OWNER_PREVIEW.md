# Owner Preview — v1.3

目的：尽早让 Owner 拿到可测 JAR，并支持“测 → 小修 → 再测”的快速联调循环；Formal Git/candidate/UAT 在 Preview 稳定后统一收口。

## 首次 Preview
1. DIB submit。
2. 原 DLA actual diff review PASS。high-impact fresh review 可与 Preview 并行，不是 Preview 前置。
3. DLA `preview-open` 创建隔离源码快照。
4. DIB 构建快照并 `preview-finish`。
5. Owner 试用；DLA `preview-result` 记录 pass/fail。

## Preview FAIL 分类
- 原 Contract 内实现 Bug：`preview-request-fix` → `IMPLEMENT / PREVIEW_FIX`。不重新 Product Grill、Contract revision、fresh review、formal candidate。
- 产品语义改变：回 DLA Contract revision。
- 协议/架构/范围改变：回 CHANGE / high-impact。

## Preview Fix 快速循环
1. DLA `preview-request-fix --id ... --owner-record ...`。
2. DIB 只修该 Preview defect，运行必要机器检查，写独立 Preview fix report。
3. DIB `preview-fix-submit`，不覆盖原 `EXECUTION_REPORT.md`。
4. DLA 实际审阅该 fix 后 `preview-fix-review --status pass|fail`。
5. PASS 后 DLA 直接再次 `preview-open`；DIB `preview-finish`；Owner 再测。
6. 可重复多轮；每轮保存独立 token/fingerprint/evidence。

Preview PASS 只表示当前 Preview 可接受，不自动写 formal owner_uat PASS。Preview 稳定后再统一完成 final review / fresh review（若适用）/ Git candidate / formal build / test packet / UAT。
