# Preserved Foreign Inputs — v1.3

仓内 tracked dirty 若在当前任务开始前已经存在且与任务无关，可以显式保留，不要求 Owner restore/stash/commit。

DLA 使用：
`desktop.py candidate-preserve-foreign --id WD-XXX --path pom.xml --owner-record <Owner说明> --role DLA`

Harness 绑定路径、Owner record 与 hash；candidate-plan 排除这些输入，candidate-check 验证它们没有进入当前 candidate 且工作区 hash 未变化。任务期间新增的 out-of-scope dirty 不可用该机制隐藏。
