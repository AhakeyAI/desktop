# WBS 5.9A 安装 / 覆盖升级 / 卸载 / 回滚

安装器逻辑在 `AhaKeyReleaseInstallPlanner`；本卡测试全部注入沙箱 host，不修改 `/Applications`、不写真实 LaunchAgents、不调用 `SMAppService`。

## 支持范围

- 允许：macOS 13+（Darwin ≥ 22）。
- 拒绝：macOS 12 及更早。拒绝时零写零擦，不得半安装。

## 原子安装 / 覆盖升级

1. bootout 竞争 owner：`lab.jawa.ahakeyconfig.agent.hil` 以及除正式 label 外的 `lab.jawa.ahakeyconfig.*`；正式 label 在重写前也 bootout。
2. 已有 App 则先备份到 `*.ahakey-backup`。
3. 复制候选 `.app`。
4. 写入带 `MachServices = lab.jawa.ahakeyconfig.runtime` 的 LaunchAgent plist。
5. bootstrap 正式 label，注册 macOS 13+ 登录项（真实 `SMAppService` 留待 HIL）。
6. 断言加载中的 ahakey label 只剩 `lab.jawa.ahakeyconfig.agent`。
7. 成功后删除备份。

失败则回滚：恢复备份 App 与旧 plist（若有），bootstrap 旧 owner；新鲜安装失败则删除半份 App 与新 plist。不得留下双 Agent。

## 卸载

bootout 全部 ahakey label、注销登录项、删除 App 与本产品 LaunchAgent plist。

**必须保留：** `~/Library/Application Support/AhaKeyConfig` 以及第三方 Hook 文件（Claude/Cursor/Codex/Kimi）。卸载不得改这些文件。

## 已知限制（5.9B / HIL）

- 本卡不实际 Developer ID 签名、不公证、不写登录项、不覆盖 `/Applications`。
- 不迁移历史 Keychain/TCC。
- 无 Windows 安装器。
- 真实干净安装、覆盖升级、登录重启由 `HIL-RELEASE-0.2` USER-GATE 执行。
