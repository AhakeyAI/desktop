# WD-009 执行报告（Hook 修正 R3/R4 实现交审）

本轮完成 Owner 已批准的 J014 Hook 管理修正，R4 成熟 TOML 校验依赖是同次需求的实现细化。DIB 已在 Contract revision 4 / build_round 4 / IMPLEMENT 下重新 preflight PASS。当前提交实现供 DLA 审阅；1.0.19 完整本地模型 EXE 需本轮 Preview token 后构建，尚未构建或安装。

## 输入与历史保留

接收仓库 HEAD 仍为 `7afc4e7792e45125c6c5a43a45a346c9331adeb2`。前轮 WD009 已审五组需求、Kimi BLE 路由与 WD008 实现保留，不恢复 WD007 整体实现。R2 冻结报告原字节保存为 `target/wd009-hook-r3/before/EXECUTION_REPORT_R2_FROZEN.md`，此前 Preview 构建报告和 1.0.18 EXE 原样保留。

本轮生产增量仅 HookInstaller.java、TopBar.java、pom.xml；新增两个 wd009 隔离检查。原始两生产文件和 pom 原字节保存于 `target/wd009-hook-r3/before/`。准确输入、依赖、日志 SHA256 见 `IMPLEMENTATION_CHECKS_R4.json`。最终增量 diff 见 `target/wd009-hook-r3/final/`。未改 Firmware、桥、传输、K1、语音、平台审批/灯效语义或接入路径；未写 Git。

## 实际实现

- Hook 检查核对当前平台生成脚本、共享 core（含实际服务端口）和已注册事件。Codex 辅助 sidecar 旧或缺失仅说明，不独立判为待更新。脚本相同 marker 但实际内容改变会报告不匹配。脚本 CRLF/LF、JSON 格式、命令中的 Windows 路径分隔差异不会造成虚假待更新。服务未启动或端口无效为 ERROR，拒绝生成无效端口脚本。
- 每个平台只更新自己的脚本与现有配置，以及内容确实需变化的共享 core。所有计划先在内存准备并校验，再对所有受影响旧文件建立唯一备份，然后原子替换；写后逐字节回读及重新实际检查通过才返回成功。失败给具体步骤和原因，备份保留；不会把部分失败报告成成功。
- JSON 严格拒绝重复键、尾随第二个根、错误根/hooks/event/wrapper 类型。只识别实际 `.ahakey/hooks/本平台脚本` 的 PowerShell `-File` 调用；同名第三方路径或偶然字符串不归属 AhaKey。混合 wrapper 中只移除受管子命令，保留第三方命令及 wrapper 字段，再加入正确受管事件。
- Codex TOML 使用已缓存 `org.tomlj:tomlj:1.0.0`（antlr4-runtime 4.7.2、jsr305 3.0.2）做只读语法/语义验证，使用解析器提供的源位置定点修改 `features.hooks`。支持多行数组/字符串、带引号 dotted key、根 dotted features、inline table、隐式父表；其他节、注释和内容原字节保留，计划写入内容再次解析成功才可写。错误消息只含位置，不输出配置值。
- Kimi 仍沿用现有路径及管理块格式；固定版本 TOML lexer 仅定位字符串外的独立注释标记，合法多行字符串里的示例标记不被替换。更新结果写前同样解析。没有借此改真实客户端接入路径或宣称已验证接入。
- Hook 管理打开/重扫不自动弹更新提示。卡片显示“已匹配”及实际检查原因。单个平台保留主动安装/更新；批量只“更新所有待更新项”，不替未安装平台注册 Hook。扫描和写入后台执行，逐平台结果内联展示，再回读卡片，不再只提示联系管理员。既有窗口重复打开会显示已有窗口。

## 实际验证

环境：JDK 17.0.19.10，既有 1.0.18 app/lib + Sherpa API + 本机三项 TOML 缓存 jar。所有写入测试的 user.home/cwd 在 target 隔离目录，不触及真实用户 Hook。无网络下载。

- 最终全生产 javac：`target/wd009-hook-r3/run-05/compile.log`，exit 0；新测试编译 exit 0。全测试源码编译：regression-01/compile-tests，exit 0。Maven offline validate exit 0，git diff --check exit 0。
- HookManagementChecks：135 断言通过。覆盖旧/缺 marker、反复扫描、新实例、同 marker 异常脚本、共享 core、命令路径等价、缺事件/错误 timeout、无效/漂移端口、按平台隔离、core 不重复写、五份生成脚本与 R2 精确 SHA256 相同、第三方混合命令及同名脚本、JSON 各类错误全文件不变、复杂合法 TOML 与重复别名/畸形值拒写、Kimi 原文/字符串伪标记保留、注入写失败/回读破坏不返回成功、批量部分失败。
- 新进程重新检查旧辅助标记 fixture：regression-01/fresh-process exit 0。
- Hook UI 23 项及既有 UI 42 项：最终 final 目录再次运行通过。包含纯格式/候选函数执行和源码接线检查；没有冒充渲染验收。
- 已有必要回归全部 exit 0：ApprovalFacts 53、CursorWaiting 148、KimiRouting 44、FirmwareIdentityCompatibility 85、DisplayConfig 175、K1RouteProtocol、BackupRestore、DeviceMaintenance、Wd009Ui 42。原真实处理服务通过内存 transport/SQLite/本地 fixture 验证，不代表真实设备通过。日志统一在 regression-01/RESULTS.json。
- 生成的 core/Claude/Cursor/Codex/Kimi 脚本内容 SHA256 与 R2 同端口产物完全相同；本轮未更改审批/灯光脚本含义，不重做平台功能。

失败证据保留：red-sidecar.log 精确证明原实现因旧辅助 marker 报 OUTDATED；run-02/hook.log 为定点插入由节尾改为节首后测试过度限定位置，修测试为验证正确节、保留周边配置，未放宽业务要求。R3 临时手写 TOML 子集的审阅发现由 R4 成熟解析器替代，quoted dotted/重复别名/缺逗号均纳入实际回归。此前 WD009/R2 的失败与构建证据未覆盖。

## 范围与未执行项

machine/core/special 仅以上离线范围通过。mock 为不适用（现有 Hook 页面最小调整，无新产品原型）；真正 JavaFX 渲染、真实用户 Hook 安装及平台回调、真实键盘/灯效、安装更新及本地模型运行均未执行，仍由 Owner 测试。没有运行真实 SendInput、启动/杀真实桥、安装软件、修改真实 Hook、读写/烧录设备、修改 Firmware 或 Git 提交。

下一步 DLA 对上述最终增量及全范围输入实际审阅并取得独立审阅；通过后正式 preview-open，DIB 使用全新派生源及已有桥/模型/发行签名配方构建完整 1.0.19 本地模型 EXE，验证包内新 TOML 依赖与真实包内 classpath，再交 Owner 测试。旧 1.0.18 保留。当前无 Owner 产品歧义待定。
