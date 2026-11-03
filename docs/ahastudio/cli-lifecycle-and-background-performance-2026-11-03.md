# 无需实体操作的补验与工具修复 — 2026-11-03

当前固定组合仍为Studio build537/b8a9faec及F99D HW1 1.0.1-r001。本次没有重装客户端、刷机或改键盘设置。实体正常重启的请求尚未收到回复，不能用自动连接状态推断真实断电保持。

## 后台10分钟样本

Studio以隐藏状态保留设备信息弹窗，5秒采样一次，600.08秒共121次观测均为后台、Agent报告连接，两个进程PID均连续。单核平均CPU：Studio 1.1565%，Agent 0.6849%。RSS分别从63984→38304KiB、15392→13376KiB，不能据短样本宣称无内存泄漏。

期间其他进程运行了隔离CLI验收与编译，因此这是后台并发工作场景，不是空载，也不代表前台可见GIF长期矩阵通过。只查询Agent内存中的presentation overview，未增加BLE状态查询。前台归属仅记录是否为Studio，不采集其他应用标题或内容。窗口已恢复、日志仍关闭。[性能回执](../validation/connect-talk-hil-2026-10-22/build537-background-performance-2026-11-03.json)。

## 修复独立验收工具的编译依赖

真实verify-kimi-native-hooks.py在编译生产配置生成器时失败：ApprovalAutomationControl已依赖Kimi会话恢复日志，独立源列表遗漏KimiDesktopLeverState及其桥接／发现／凭据类型、进程身份类型，以及Kimi默认权限恢复依赖。这是维护者工具的源文件依赖遗漏，完整SwiftPM客户端此前977测试／构建成功不与之矛盾。

先新增真实编译回归，确认报缺失类型；补齐生产源依赖，不使用替代类型。回归还在显式临时目录执行真实beginRevocation，确认依赖闭包可运行。20项维护者测试通过，Kimi2.4.0安装／重装／移除10/10/1真实执行通过，模型请求0。Codex信任夹具编译和生成配置三阶段通过，未运行真实Codex模型或权限请求。

## Claude运行中新增命令的边界仍开放

Claude Code2.1.299普通生命周期12/12/1通过；Cursor2026.10.19-6bbf2c4启动／退出10/10/1通过。Cursor采用不可用的本地Agent流，未验证真实提交／工具回调；Kimi生命周期不等于原TUI权限接管。

Claude --live-reload实际失败：替换为启动时未登记的新命令路径后，仅用户阻断Hook执行，新的托管Hook没有执行。将稳定等待2.5秒改为8秒仍失败；HOME与配置目录一致化也未改善；同一替换配置在新进程中正常执行next:SessionStart/UserPromptSubmit/SessionEnd，模型请求0，排除了该配置本身无法执行。

唯一改变为在进程启动配置中预先登记两个托管命令路径的对照，原同进程替换／移除断言全部通过。该差异与新命令需要重新确认的限制一致，但不是对CLI内部安全实现或任意交互TUI的完整证明。不能通过预先加入路径来改写原验收前提并假称所有热重载通过；原始失败脚本及断言保持。

[当前官方Hooks参考](https://code.claude.com/docs/en/hooks#disable-or-remove-hooks)称文件更改通常由watcher自动拾取；[官方说明文章](https://claude.com/blog/how-to-configure-hooks)同时记录直接修改新Hook需要在/hooks检查。两者与版本／交互方式有边界，支持时应引导现有会话检查/hooks或重新打开，不能静默绕过命令确认。客户端现有成功提示是“已写入配置”，只证明文件写入，不证明正在运行的原会话已执行新Hook。

没有修改真实CLI配置、复制账号凭据、发起真实模型请求或自动同意额外命令。测试使用临时配置、保留的用户阻断Hook和本地端点。诊断代码及原始输出保留在本机private diagnostics目录，未加入产品；源码改动仅维护者工具依赖与编译回归测试。[CLI回执](../validation/connect-talk-hil-2026-10-22/cli-lifecycle-recheck-2026-11-03.json)。

当前结论：后台样本与CLI生命周期增量完成；Claude当前无界面会话新增命令热重载仍未通过，交互TUI确认路径待核验；实体重启／Voice／拨杆待用户。全WBS不标完成。

验收工具修复源码6cd4d6fb已通过[CI41584051512](https://github.com/AhakeyAI/desktop/actions/runs/41584051512)全部三项作业。该检查包含当前工具与生产源，不会把未通过的Claude新增命令热重载场景变成通过。
