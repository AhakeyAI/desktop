# 任务卡 RUNTIME-NAMING-AND-LEGACY-UI-CLEANUP：Runtime 命名与失效交互清理

计划/WBS：post-v0.2 cleanup / v0.2.1；外部 identity 迁移归 5.9B / v1.0
状态：`ready / U1 user-facing cleanup`
执行 owner：Cursor（Codex 验收）
基线：产品 `5c4f440a779452dd00282cd35fe915e2642678f0`；HIL Gate-2 accepted @ `c082ecd`

## 背景与裁决

5.7 后的真实架构已经是：Studio 是 Runtime 客户端，不扫描、不连接、不临时占用 BLE；后台进程是唯一设备 owner。当前 UI/本地化仍大量展示“控制方”“Studio 临时接管蓝牙”“把蓝牙交还给 Agent”“由 App/Agent 二选一占用”等旧交互，且用户可见名称混用 Agent / Runtime。

本卡分三层，禁止一次性全量改名：

1. **U1（本轮开放）用户可见清理**：统一产品名称与真实交互，不改外部身份。
2. **U2（U1 accepted 后另开）内部 Swift 符号/文件清理**：如 `AgentManager` → `RuntimeServiceManager`，仅机械重命名与死代码删除；单独验收。
3. **U3（不在本卡直接施工）外部身份迁移**：二进制名、LaunchAgent label、plist 文件、日志路径、Hook command。归入 `WBS-5.9-INSTALL-MIGRATION`，必须用 build 359 做升级/降级/回滚/卸载兼容验证。

## U1 冻结产品词汇

- 用户可见后台产品名：**AhaKey Runtime**；简短位置可写“后台服务”。
- `LaunchAgent`、`ahakeyconfig-agent`、`lab.jawa.ahakeyconfig.agent` 只允许出现在“高级诊断/技术详情/日志路径”，不得作为普通用户操作概念。
- 顶栏 `控制方` 改为 **配置状态**；状态表达本地编辑/同步事实，不再暗示 BLE owner。建议值：`浏览配置` / `编辑配置中` / `正在同步`，以现有状态机能可靠表达的最小集合为准。
- `设备信息 · Agent` 改为 **设备与后台服务**；`安装 Agent + Hook` 改为 **修复后台服务与 IDE 集成**；`启动 Agent` 改为 **启动后台服务**。
- 删除或改写所有“Studio 临时接管蓝牙 / 把蓝牙交还给 Agent / App 与 Agent 二选一占用 / 编辑态释放或接管 BLE”的用户可见文案。真实口径：**键盘连接始终由 AhaKey Runtime 管理；Studio 的编辑保存在本地，写入时通过 Runtime 提交。**
- “自动批准依赖 Agent”统一为“自动批准依赖 AhaKey Runtime 与 IDE 集成”；不改 Claude/Cursor/Codex/Kimi 的既有功能语义。

## U1 允许修改

- `ahakeyconfig-mac/Sources/Views/AhaKeyStudioView.swift` 中用户可见文案、帮助文字，以及仅为删除已失效 BLE-owner 控件/分支所需的最小 view glue。
- `ahakeyconfig-mac/Resources/zh-Hans.lproj/Localizable.strings`
- `ahakeyconfig-mac/Resources/en.lproj/Localizable.strings`
- 对应 UI/本地化/静态架构契约测试；允许新增一个用户可见词汇扫描脚本放入 `ahakeyconfig-mac/scripts/` 或 Tests。
- 本任务卡、append-only board、必要的产品说明文档。

## U1 禁止事项

- 不改 `Package.swift` target/product 名，不重命名 `ahakeyconfig-agent`、LaunchAgent label/plist、Mach service、Bundle/Signing ID、socket、日志目录或 Hook command。
- 不改 Runtime wire/XPC、BLE transport、WAL、配置 planner、固件协议、安装器/打包签名逻辑。
- 不重新引入 Studio 直连 BLE，不增加兼容双进程，不删除用户配置/Hook。
- 不签名、不安装、不覆盖当前 `/Applications` 359、不改登录项、不刷机、不 push。
- 不顺手执行 U2/U3。

## U1 完成定义

1. 普通用户可见页面不再出现裸 `Agent`、`控制方` 或旧 BLE 交接口径；高级诊断允许显示 legacy 技术 identity，并明确标注“兼容标识”。
2. 顶栏、设备信息、自动批准说明、首次引导、帮助中心、写入/返回提示与中英文本地化一致。
3. 增自动门禁：扫描生产 View 与本地化资源，旧短语只允许出现在显式 allowlist 的高级诊断位置；删除 allowlist 外命中时测试失败。门禁至少覆盖“控制方”“临时接管蓝牙”“交还给 Agent”“由 Agent 占用”“设备信息 · Agent”。
4. `plutil -lint` 两份 strings；定向 UI/文案测试；全量 `swift test`；App + Runtime(现技术 target 仍为 Agent) Release build；产品范围 `git diff --check` 全绿。
5. 交一个产品 commit 与回传包后停手提审。Codex accepted U1 前不得进入 U2，也不得生成/安装 v0.2.1 候选。

## U2 / U3 预留验收原则

- U2 必须先建立内部名称映射表，区分产品名、Swift 类型、进程身份和兼容文件；机械 rename 不改变运行行为。
- U3 采用 dual-read / single-write 迁移：升级时识别并 bootout build 359 的旧 label，安装新 Runtime identity，任何时刻只允许一个 owner；卸载同时清理受管新旧 identity，保留用户配置和第三方 Hook；失败回滚必须恢复精确旧 owner/disabled/plist/login 状态。
- Mach service `lab.jawa.ahakeyconfig.runtime` 已是目标名字，默认保持不变。是否改 executable/launchd label 要先交迁移 ADR 与版本矩阵，不以“统一命名”为理由破坏存量 0.2 安装。

## 执行记录（append-only）

### [2026-08-31 22:27] Codex：创建任务并开放 U1

- 用户要求清理存量无效交互，并提出 Agent→Runtime、删除“控制方”等表达。Codex 只读盘点确认 View/本地化仍有大量与 5.7 架构相反的 BLE ownership 文案；创建本卡。
- 本轮只开放 U1 用户可见清理；外部 identity 迁移冻结到 U3/5.9B，当前已安装 0.2.0 (359) 不受影响。
- 需要回复：是（@Cursor ACK 后仅执行 U1）

### [2026-08-31 22:36] Cursor ACK：开始 U1 用户可见清理

ACK Codex `58c4d7f`。只做 U1：用户界面统一 AhaKey Runtime/后台服务，顶栏改配置状态，删除失效 BLE 所有权交互，中英本地化与旧词门禁。不改外部 identity、不签名、不覆盖 359、不进 U2/U3、不 push。重启 POST 因本机未重启未采集，不阻塞本卡施工。

### [2026-08-31 22:49] Cursor：U1 完成，停手提审

顶栏「控制方」改为「配置状态」（浏览配置 / 编辑配置中 / 正在同步）。设备信息、自动批准、首次引导、帮助中心与写入提示改为 AhaKey Runtime / 后台服务口径；键盘连接始终由 Runtime 管理。旧短语门禁 `scripts/check-u1-user-facing-copy.py`；`plutil -lint` 两份 strings；`swift test` 713 passed / 2 skipped；Release 构建 AhaKeyConfig + ahakeyconfig-agent。未改 executable/LaunchAgent label/plist/Mach/Hook command，未覆盖 `/Applications` 359。未进 U2/U3。

- 需要回复：是（@Codex 验收 U1）
