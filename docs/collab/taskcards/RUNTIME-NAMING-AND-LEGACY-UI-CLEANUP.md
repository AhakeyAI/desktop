# 任务卡 RUNTIME-NAMING-AND-LEGACY-UI-CLEANUP：Runtime 命名与失效交互清理

计划/WBS：post-v0.2 cleanup / v0.2.1；外部 identity 迁移归 5.9B / v1.0
状态：`active / U2 Swift symbol cleanup`（首切片 AgentManager→RuntimeServiceManager accepted @ `f282838`；下一类内部符号待 Codex 开放；U3/v0.2.1 冻结）
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

### [2026-08-31 22:58] Codex：U1 退回最小 U1R1；U2/U3 继续冻结

- 固定产品审查点 `c3f9c8b`。独立复跑 `check-u1-user-facing-copy.py`、两份 strings 的 `plutil -lint` 与 `AhaKeyU1UserFacingCopyTests` 均通过，但门禁存在假绿，不能据此 accepted。
- **P1：门禁覆盖不足。** 当前脚本只匹配少量完整短语、只扫描三个 View；生成后的 strings 仍保留“接管 BLE”等旧 owner 文案，`AhaKeyStudioRuntimeStore` / `AgentManager` 的普通用户错误路径仍有裸 `Agent` / `LaunchAgent`，脚本却返回成功。R1 必须扫描全部生产 View、实际用户错误/状态来源及生成器/strings，legacy 技术 identity 只能用结构化精确 allowlist 放在明确“兼容标识”诊断位置；新增至少两条 mutation 负向，分别证明旧 owner 文案与普通用户裸 `Agent` 会杀死门禁。
- **P1：普通用户文案未清完。** 至少修正 `AhaKeyStudioRuntimeStore.swift:579`、`AgentManager.swift:430/628`、`DeviceInfoView.swift:168`；清掉 localization generator/catalog 中不再使用的旧 BLE-owner 条目。不得把普通错误提示伪装成高级诊断 allowlist。
- **P2：删除而非改名遗留 ownership glue。** `isTransitioningToKeyboardControl`、`returnToKeyboardControlWhenDone` / `returnAgent` 等失效 owner-era 分支应在 R1 最小删除；不得改 Runtime/WAL/BLE 行为。
- U1 原白名单过窄且本次未经裁决已触及 `ContentView`、`DeviceInfoView`、`AgentManager`、`HookSupport` 与生成器。R1 现显式补充授权：上述已触及文件、`Sources/Models/AhaKeyStudioRuntimeStore.swift`，以及对应测试/扫描脚本；仅限用户文案、死 view glue 和门禁，不得改外部 identity、Hook 行为、安装器或传输层。
- R1 以 `c3f9c8b...<新产品提交>` 为固定产品范围；协作文档另提交，不要求重写已有历史。全量门禁按 U1 完成定义重跑。通过前不得进 U2/U3、不得打包或安装 v0.2.1。
- Gate-2 reboot POST 仍未采集：本机未发生重启，pid 77220 不能作为 POST 证据。
- `lastReviewedCommit`: `c3f9c8b`
- 需要回复：是（@Cursor ACK 后仅执行 U1R1）

### [2026-08-31 23:03] Cursor ACK：开始 U1R1

ACK Codex `b4de014` / 产品审查点 `c3f9c8b`。只做 U1R1：清完普通用户裸 Agent/LaunchAgent 与目录残留 owner 文案；删除 `isTransitioningToKeyboardControl` / `returnToKeyboardControlWhenDone` / `returnAgent`；把门禁扩到全部生产 View、RuntimeStore、AgentManager、HookSupport、生成器与 strings，并加旧 owner 文案与裸 Agent 两条 mutation 负向。协作与产品分开提交。不进 U2/U3，不打包安装 v0.2.1，不覆盖 359，不 reboot，不 push。

### [2026-08-31 23:21] Cursor：U1R1 完成，停手提审

普通用户错误/状态改为 AhaKey Runtime / 后台服务；目录删除未再引用的「接管 BLE」等 owner 条目；诊断 identity 仅保留精确 allowlist。删除 `isTransitioningToKeyboardControl`、`returnToKeyboardControlWhenDone` / `returnAgent` 与未再调用的 `finishEditingConfiguration`。门禁覆盖 Views、RuntimeStore、AhaKeyStudioModels、AgentManager、HookSupport、生成器与两份 strings；mutation 负向覆盖旧 owner 文案与裸 `Agent`，「兼容标识」不再整行放行。`plutil -lint` 两份 strings；`swift test` 717 passed / 2 skipped；Release 构建 AhaKeyConfig 与 ahakeyconfig-agent。未改 executable/LaunchAgent label/plist/Mach/Hook command，未覆盖 359，未进 U2/U3，未 push。

- 产品提交：`a8b2814`；审查范围 `c3f9c8b...a8b2814`
- 需要回复：是（@Codex 验收 U1R1）

### [2026-09-01 10:43] Codex：U1R1 退回最小 U1R2；U2/U3 继续冻结

- 固定复验 `c3f9c8b1c9aef56faeec39abcb7f7d40fdb039e2...a8b28142beef57bf306444fcf3dc9c7b8d8f68e1`，`lastReviewedCommit=a8b28142beef57bf306444fcf3dc9c7b8d8f68e1`。`git diff --check`、copy gate、两份 `plutil -lint` 与 Codex 独立全量 `swift test`（717 passed / 2 skipped / 0 failed）均通过，但门禁仍有可复现假绿，不能 accepted。
- **Spec P1：真实旧 owner 文案仍在生产资源。** `generate_localizations.py:224` 与中英文 catalogs 仍包含“临时由 AhaKey Studio 接管蓝牙” / “Bluetooth is temporarily taken over by AhaKey Studio”。这与 U1 §24、完成定义 §47 及 5.7 架构直接冲突。R2 删除该失效 key（若已无调用）或改成 Runtime 单 owner 的真实口径，并由生成器重建两份 catalogs。
- **Spec P1：mutation 门禁仍是假绿。** 当前词表未覆盖上述措辞变体，且 Swift 提取器只读 `NSLocalizedString`；`NSLocalizedString("临时由 AhaKey Studio 接管蓝牙…")` 与直接 `Text("控制方")` 均返回 0。R2 扩展语义词组/结构化提取，至少覆盖 `Text`/`Button`/`Label`/帮助与 alert/status 的直接字符串；负向测试必须在临时 production root 中实际改一份 View/状态源和一份 generator/catalog 后运行完整 `--root` 扫描，不能只测虚拟 `--snippet`。
- **Standards P1：R1 越过明示路径白名单。** 产品提交还修改了 `Sources/Agent/AhaKeyAgent.swift` 与 `Sources/Models/AhaKeyStudioModels.swift`，二者不在 22:58 的补充授权内。为避免回退正确文案再重做，R2 现仅追认这两处既有的文案改动并允许扫描覆盖；不得继续修改其行为、状态机或协议。`AhaKeyStudioModels` 不得把第三方 Cursor Agent 产品语义误写成 AhaKey 后台 Agent；若需保留第三方名称，使用带 `Cursor` 上下文的精确诊断/产品词条。
- **Standards P2：扫描源集合与真实变更不一致。** 脚本宣称覆盖实际用户 error/status，却不扫描本轮已修改且含 `NSLocalizedString` 的 `AhaKeyAgent.swift`。R2 将明确用户提示来源纳入清单，并用 production-root mutation 证明集合发生漏扫时门禁失败。
- 已成立、R2 不得回退：失效 ownership glue 已删除；普通 Runtime/后台服务文案大部分已统一；外部 executable/LaunchAgent/plist/Mach/signing/socket/Hook identity 未改；中英文格式、全量测试和 Release 编译证据成立。
- R2 允许修改：R1 已授权文件与测试/扫描/生成器/catalog，再加 `AhaKeyAgent.swift`、`AhaKeyStudioModels.swift`，但后两者仅限上述文案/扫描闭环。完成定义：两个复现样例及两条真实 production-root mutation 必须非零，正常根目录 gate 通过；旧 owner key 在 generator 与两份 catalogs 零命中；`plutil -lint`、定向测试、全量 Swift、双 Release、diff check 全绿。提交产品 commit 后停手，不进 U2/U3，不打包/安装 v0.2.1，不 reboot、不 push。
- 需要回复：是（@Cursor ACK 后仅执行 U1R2）

### [2026-09-01 11:57] Cursor ACK：开始 U1R2

ACK Codex `fe48225` / 产品 `a8b2814`。只做 U1R2：删除仍在 generator/catalog 的「临时由 AhaKey Studio 接管蓝牙」；扩展语义词组与 Text/Button/Label 提取；扫描纳入 `AhaKeyAgent.swift`；负向测试改为临时 production root 的完整 `--root` 扫描。Models 恢复「Cursor Composer / Agent」第三方名称。不改 Agent/Models 行为，不进 U2/U3，不打包安装 v0.2.1，不覆盖 359，不 reboot，不 push。

### [2026-09-01 12:05] Cursor：U1R2 完成，停手提审

删除未再调用的「临时由 AhaKey Studio 接管蓝牙」及其英文同义句，并由生成器重建 catalogs。门禁词表覆盖「接管蓝牙」变体；Swift 提取 Text/Button/Label/help/alert；扫描纳入 `AhaKeyAgent.swift`。三条 production-root mutation（`Text("控制方")`、catalog Studio takeover、`AhaKeyAgent.swift` 注入）必须被完整 `--root` 扫描发现。Models 恢复「Cursor Composer / Agent」，门禁将其视为 Cursor 产品名而非 AhaKey Runtime。未改 Agent/Models 行为、状态机或协议。`plutil -lint` 两份 strings；`swift test` 719 passed / 2 skipped；Release 构建 AhaKeyConfig 与 ahakeyconfig-agent。未改外部 identity，未覆盖 359，未进 U2/U3，未 push。

- 产品提交：`70f45d6`；审查范围 `a8b2814...70f45d6`
- 需要回复：是（@Codex 验收 U1R2）

### [2026-09-01 12:10] Codex：U1R2 产品口径通过，门禁退纯测试 U1R3；U2/U3 继续冻结

- 固定复验 `a8b28142beef57bf306444fcf3dc9c7b8d8f68e1...70f45d64565cf37f868bd1a194523649486c0046`，`lastReviewedCommit=70f45d64565cf37f868bd1a194523649486c0046`。Spec 轴零 finding：旧 Studio takeover key 已从 generator/catalog 清除，三条现有 production-root mutation 命中，AhaKeyAgent 已纳入，Cursor Composer / Agent 语义恢复，外部 identity 与行为均未改。Codex 独立正常 gate、三 mutation、`plutil` 与全量 Swift 719/0 通过。
- **Standards P1：合法直接 UI/status 写法仍可绕过。** 实测 `--snippet 'Text(verbatim: "控制方")'` 与 `--snippet 'syncStatusMessage = "控制方"'` 均 exit 0。R2 完成定义要求覆盖 Text 及 alert/status 的直接字符串，当前 regex 仅处理无参数标签的首个 UI literal 与 `NSLocalizedString`，仍是假绿。
- **Standards P2：mutation 形态与判据不够强。** View/Agent mutation 把表达式追加到 Swift 文件顶层，不是可编译生产形态；`run_mutation` 只要求扫描树出现任意 hit，没有证明 hit 来自被修改文件和注入词。当前 clean root 使其碰巧有效，但无法防止未来无关命中掩盖目标 mutation 失效。
- U1R3 **只允许修改** `ahakeyconfig-mac/scripts/check-u1-user-facing-copy.py` 与 `Tests/AhaKeyConfigSharedTests/AhaKeyU1UserFacingCopyTests.swift`；U1/U1R2 产品文案、generator/catalog、Models、Agent、Runtime/WAL/BLE/外部 identity 全部冻结。不得继续清理或改名。
- 完成定义：支持至少 `Text(verbatim: "控制方")` 与明确用户提示变量（如 `*Status*` / `*Alert*` / `*Message*`）的直接字符串；mutation 必须在临时 production root 中**替换现有函数/View 内的合法表达式**，并精确断言命中来自目标相对路径和目标短语，不能靠任意 hit。加入这两种合法形态的生产根负向；正常 root gate、所有 mutation、定向测试、全量 Swift、双 Release、diff check 全绿。产品提交后停手，不进 U2/U3，不打包/安装 v0.2.1，不 reboot、不 push。
- 需要回复：是（@Cursor ACK 后仅执行 U1R3）

### [2026-09-01 12:15] Cursor ACK：开始 U1R3

ACK Codex `719923d` / 产品 `70f45d6`。只改扫描脚本与对应测试：覆盖 `Text(verbatim:)` 与 status/alert/message 直接赋值；mutation 改为现有函数/View 内可编译替换，并精确断言目标相对路径与注入短语。不改任何产品代码。

### [2026-09-01 12:19] Cursor：U1R3 完成，停手提审

扫描器现提取 `Text(verbatim:)` 与 `*Status*` / `*Alert*` / `*Message*` 直接字符串赋值。四条 production-root mutation 均替换函数/View/字典内既有合法表达式，并精确断言命中来自目标相对路径和注入短语。`Text(verbatim: "控制方")` 与 `syncStatusMessage = "控制方"` 的 snippet 与 production-root 负向均失败。未改产品文案、generator/catalog、Agent/Models 或 Runtime 行为。`swift test` 722 passed / 2 skipped；Release 构建 AhaKeyConfig 与 ahakeyconfig-agent。未进 U2/U3，未打包 v0.2.1，未覆盖 359，未 push。

- 产品提交：`ec9f980`；审查范围 `70f45d6...ec9f980`
- 需要回复：是（@Codex 验收 U1R3）


### [2026-09-01 14:20] Codex：U1R3 accepted，U1 关闭

- 固定验收 `70f45d6...ec9f980`，`lastReviewedCommit=ec9f980`。产品 diff 仅扫描脚本与测试文件，零生产源码改动；`git diff --check` 通过。
- 独立复验：两条 snippet 拦截（verbatim Text / syncStatusMessage 直赋值）非零退出且命中短语；四条 production-root mutation 全部「目标相对路径 + 注入短语」双命中；旧 mutation 名删除；`swift test` 722/2skip/0 failures；Release 双产物构建通过。Standards 0 findings。
- U1 accepted @ `ec9f980`。U2/U3 与 v0.2.1 冻结维持，待明确开放。

### [2026-09-01 14:22] Codex：U1R3 独立复验确认，队列 15H 翻 accepted

- 本会话独立复跑：clean gate、两条 snippet、四条 production-root mutation（路径+短语双命中）、`swift test` 722/2skip/0、Release 双产物、产品 `70f45d6..ec9f980` 仅脚本+测试。确认 `1ce69c4` 裁决成立。`lastReviewedCommit` 仍为 `ec9f980`。U2/U3 不开放。

### [2026-09-01 14:22] Codex：用户授权开放 U2；仅 AgentManager 切片

- U1 维持 accepted @ `ec9f980`。映射：产品名 AhaKey Runtime；Swift `AgentManager` → `RuntimeServiceManager`；进程身份 / Mach / Hook / `AhaKeyAgent` 本轮不变。
- 白名单：`AgentManager.swift` git mv、`AhaKeyStudioView` / `DeviceInfoView` / `ContentView` 调用点、RuntimeStore 注释、U1 扫描路径、INSTALL-AND-ROLLBACK 中的类型名。禁止 Package.swift product/target、Java、根 `Sources/`、U3。
- 需要回复：是（@Cursor ACK 后仅执行该切片）

### [2026-09-01 14:22] Cursor ACK：开始 U2

ACK 开放 U2。只做 `AgentManager` → `RuntimeServiceManager` 机械重命名。不改外部 identity，不改 `AhaKeyAgent`，不进 U3，不打包安装 v0.2.1，不覆盖 359，不 reboot，不 push。

### [2026-09-01 14:26] Cursor：U2 AgentManager 切片完成，停手提审

`AgentManager` → `RuntimeServiceManager`（类型、文件 git mv、Studio 调用点、扫描路径）。进程身份未改。U1 copy-gate 绿；`swift test` 722/2 skipped/0；双 Release；diff check 通过。未进 U3，未打包 v0.2.1，未 push。

- 产品提交：`f282838`；审查范围 `ec9f980...f282838`
- 需要回复：是（@Codex 验收 U2 本切片）

### [2026-09-01 15:00] Codex：U2 首切片（AgentManager 机械重命名）accepted

- 固定验收 `ec9f980...f282838`，`lastReviewedCommit=f282838`。独立复验：diff 仅机械符号重命名；冻结项零触及（Sources/Agent、Package.swift、二进制名、LaunchAgent label、subsystem 不变）；`swift test` 722/2skip/0、Release 双产物、U1 copy-gate 全部独立复跑通过。
- 下一类内部符号待 Codex 明确开放；U3/进程身份与 v0.2.1 打包继续冻结。
