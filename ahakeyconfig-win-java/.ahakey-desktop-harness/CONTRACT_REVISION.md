# Contract Revision / Alignment Reconcile — v1.3

当 Owner 在 IMPLEMENT 中修正产品语义，属于正常 CHANGE 迭代，不要求回退历史 Contract。

## 原则

- immutable origin：任务身份、原始 start-fingerprint、历史 assignment / gate / evidence 保留。
- effective contract：允许通过 DLA + Owner 对齐形成新 revision。
- 每次 revision 保存旧 approval / inputs / reason / Owner evidence，形成 append-only history。
- DIB 必须在新的 effective approval / dispatch 下重新 preflight。
- route/reconcile 命令必须先完成全部校验再写入；失败不得留下半写状态。

## 正式命令

```
python .agents\skillshakey-desktop-harness\scripts\desktop.py `
  --repo <WindowsRepo> `
  contract-reconcile `
  --id WD-002 `
  --owner-record <Owner确认记录> `
  --reason-record <alignment/revision说明> `
  --role DLA
```

若历史 `guard-origin.json` 与当前 `start-fingerprint.json` 因旧 helper 半写发生不一致，且 Owner 已明确授权按当前保留的 start 文件继续，可增加：

```
  --repair-origin
```

该选项不会修改生产代码或 start-fingerprint 内容；它会保存旧 expected hash 与当前 observed hash 的 reconciliation 记录，再更新 guard-origin 对该 start 文件的引用。不得静默使用。
