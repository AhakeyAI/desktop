# 任务卡 HIL-RELEASE-0.2-PACKAGING-REWORK：签名 DMG 候选身份闭环

计划/WBS：5.9A-R7 / 6.0A pre-install rework
状态：`ready`
执行 owner：Cursor（Codex 验收）
基线：产品 `6649834602536fe1199960effa6121fdcb4a3739`；兼容策略 `d9d2cbb`；HIL 证据 `11bc323`
目标版本：v0.2 macOS Beta

目标：修复正式 DMG 在二次签名后丢失 Agent signing identifier、且未携带安装器所需 companion plist 的问题；新增最终 DMG fail-closed 门禁。不得改业务功能或弱化冻结身份。

## 已确认阻塞

1. `build.sh` 直出 Agent identifier 为 `lab.jawa.ahakeyconfig`；`package_dmg.sh` 挂载后重签未传 `--identifier`，DMG 内变为 `ahakeyconfig-agent`。
2. DMG 根目录只有 `AhaKey Studio.app`、`Applications` 与背景资源，没有 App 同级 `LaunchAgent.plist`；`AhaKeyReleaseMacInstallHost.inspectCandidate` 因此先得到缺失 companion，签名 checklist 会以 `machServiceMissing` 拒绝。
3. Apple notarization/staple/`spctl` 只证明 Apple 信任链，不证明 AhaKey 的 Bundle/Agent/Mach/Signing 冻结契约。

现有 DMG SHA-256 `4426b3c9924fe83e83f4b2ffb7a4025b53e2786fc42f6c7fc2c1ff02ffce793b` 永久标记为 nonconforming，不得安装。

## 最小实现

1. `package_dmg.sh` 从 `Packaging/ReleaseIdentity.json` 的唯一来源取得 signing identifier、Team ID、Bundle ID、Agent 路径、Mach service 与 requirement；不得新增手写身份常量。
2. Finder 布局后的 App 与 Agent 重签都显式传 `--identifier "$SIGNING_IDENTIFIER"`；Agent 不得回落为文件名。
3. DMG 中 `LaunchAgent.plist` 必须与 App 同级，并通过冻结 Mach service/label/ProgramArguments 校验；不得靠 App 内旧 `AgentManager` 路径替代 5.9A 安装链。
4. 增加最终 DMG verifier。压缩后以只读方式挂载，并在 notarization 前、staple 后各执行一次；使用 trap 保证 detach。任何一项失败均非零退出：
   - 恰好一个预期 App；版本 `0.2.0`、Bundle ID 精确；
   - Agent 路径存在；
   - companion plist 存在且 label、Mach service、Agent 路径精确；
   - App/Agent `codesign --verify --strict`；
   - App/Agent signing identifier 均为 `lab.jawa.ahakeyconfig`；
   - release 模式下 Team 均为 `P2VFVRZK7P`，且均满足冻结 Developer ID requirement。
5. `hdiutil verify`、notary `Accepted`、staple 或 `spctl accepted` 不得替代上述产品门禁。

## 测试与白名单

允许修改：

- `ahakeyconfig-mac/scripts/package_dmg.sh`
- `ahakeyconfig-mac/scripts/pack-release.sh`（仅接 verifier/身份参数）
- `ahakeyconfig-mac/scripts/check-release-identity.sh` 或新增一个专用 DMG verifier
- `ahakeyconfig-mac/Tests/AhaKeyConfigSharedTests/AhaKeyReleasePackagingScriptTests.swift`
- `ahakeyconfig-mac/Packaging/INSTALL-AND-ROLLBACK.md`
- 本卡与 append-only board

测试至少覆盖：缺/错 Agent identifier、App identifier 错、Team 错、Agent 缺失、companion 缺失、Mach service 错、签名损坏均 fail-closed；完全匹配 fixture 通过；现有 planner、Mac host、identity、XPC policy 与全量 Swift 回归通过。

禁止修改 Installer/XPC/ReleaseIdentity 的冻结策略来迁就坏包；禁止 `/Applications`、LaunchAgents/login-item mutation、安装、发布、push。

## 停手点

提交产品修复与测试后停手提审。Codex accepted 后，回到 `HIL-RELEASE-0.2` 从冻结候选步骤重新构建、Developer ID 签名、公证、staple，并提交新的 SHA/notary/最终挂载校验；该证据再次 accepted 前不得进入安装矩阵。

- 需要回复：是（@Cursor ACK 后仅执行本卡）
