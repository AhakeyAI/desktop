# Preview Iteration — v1.3

快速联调目的：Owner 尽快拿到可测版本；治理与正式 candidate 在 Preview 稳定后统一收口。

状态流：
`OWNER_PREVIEW FAIL` → DLA 分类 → 原 Contract 内 Bug 使用 `preview-request-fix` → `IMPLEMENT/PREVIEW_FIX` → DIB `preview-fix-submit` → `VERIFY/PREVIEW_FIX_REVIEW` → DLA `preview-fix-review pass` → `preview-open` → Preview build → Owner 再测。

产品语义变化不走该 fast lane，必须 Contract revision。协议/架构/范围变化回 CHANGE。

Preview 轮次独立记录，不覆盖 formal IMPLEMENT/REVIEW/CANDIDATE evidence。Preview 稳定后才重新做 final formal review/candidate/build/UAT。
