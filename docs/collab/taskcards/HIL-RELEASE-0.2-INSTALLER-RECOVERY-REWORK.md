# 任务卡 HIL-RELEASE-0.2-INSTALLER-RECOVERY-REWORK：覆盖升级恢复模型

计划/WBS：5.9A-R8 / 6.0A  
状态：`ready / R1`  
执行 owner：Cursor  
验收：Codex  
基线：产品 `3b287beecf34c3f2d433631610f8e8c8f85c9149`；真机失败证据 `133385e3d47b9d924863a4820148281015334b06`  
目标版本：v0.2

目标：用可重放的测试锁住“旧 App 密封已坏 + official label 持久 disabled + HIL owner 为前态”覆盖升级，使安装器不丢原始错误、不虚假承诺不可能的 exact rollback，并能恢复到明确可用终态。

## 已证实根因

1. 生产计划为 `bootout previous → installApp → writeLaunchAgent → bootstrap official → register login item`；真机停在 bootstrap 前后，现场 `launchctl print-disabled gui/501` 为 `lab.jawa.ahakeyconfig.agent => disabled`。当前 `AhaKeyReleaseSystemControl` 没有 disabled-state Interface，bootstrap 不会自动 enable。
2. previous 0.1.0 在 mutation 前已经 `codesign --verify --strict` 失败，但计划仍把它当作可验证的 exact rollback target；`restoreApp` 必然返回 `appIntegrityFailed`。
3. engine 在 rollback 再失败时只抛 `rollbackFailed(String(describing: rollbackError))`，原 bootstrap/apply error 被丢弃。

## R1 实现范围

- 冻结可用的前态能力：快照 previous App integrity、official/HIL loaded owner、两个 label 的 persistent disabled override、managed plist bytes 和 login-item。`AhaKeyReleaseSystemControl` 增加可注入的 disabled-state 查询/enable/restore Adapter；生产走真实 launchctl，测试走 Recording Adapter。
- official 安装在 bootstrap 前必须显式 enable，且 rollback 恢复之前的 disabled override。任一 enable/bootstrap 失败都保留完整 command/status/output。
- previous App integrity 分类为 `verifiedRestorable / nonRestorable / missing`。只有 `verifiedRestorable` 允许声称 exact App rollback。`nonRestorable` 必须保留隔离 backup，且使用显式 fail-forward/partial outcome：保留已验证候选 App，恢复前 managed plist/owner/login/disabled 状态；不得再把损坏旧树作为签名可验的 restore source，不得删除 forensic backup。若该终态无法实现单 owner，返回明确 blocked 而非 rolledBack。
- 错误结构必须同时保留 `originalApplyError`、`compensationError`、已完成 step/mutation receipt 与终态快照；不再用单个 String 覆盖原错。
- 安装成功的终态仍必须是：已验证候选 App + exact official plist + official 唯一 owner + login item。不放宽签名、双 owner、路径或 companion 门禁。

## 红灯回归矩阵

1. 真机同构 fixture：previous App 存在但 integrity invalid，HIL owner loaded，official disabled，候选有效。旧实现必须复现 `bootstrap failure → restore invalid backup → rollbackFailed 丢原错`。
2. enable 成功 + bootstrap 成功：终态 official 唯一 owner，login item 正确，candidate 完整；无损坏 backup 恢复尝试。
3. enable/bootstrap 失败：错误保留真实 launchctl output；nonRestorable 路径保留候选和 forensic backup，恢复 HIL/disabled/plist/login 前态或返回含双错的 blocked outcome。
4. verifiedRestorable 路径保持既有 exact rollback；missing 路径保持 clean install rollback。
5. original apply 失败 + compensation 失败：断言两个 error、completed steps、mutation receipt 和快照全部可读。
6. 路径/symlink/identity/Team/requirement/companion 与候选完整性门禁全回归；全量 Swift + App/Agent Release + diff check。

## 白名单

- `ahakeyconfig-mac/Sources/Shared/AhaKeyReleaseInstallPlanner.swift`
- `ahakeyconfig-mac/Sources/Shared/AhaKeyReleaseMacInstallHost.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyReleaseInstallPlannerTests.swift`
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyReleaseMacInstallHostTests.swift`
- 本卡、`HIL-RELEASE-0.2`、append-only board。

禁止：不修改包装/签名身份、XPC/BLE/Agent/Studio；不安装、不删 backup、不 bootstrap、不刷机、不 push/发布。代码提审后停手，不续 HIL。

需要回复：是（@Cursor ACK 后仅执行 R1）
