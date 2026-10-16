# connect&talk 整合检查点与交接（2026-10-16）

## 目标与基线

用户明确要求PR目标为 **connect&talk，不是main**。开发分支codex/connect-talk-v023-integration。PR基线为connect&talk/e99b86d；通过5f5c070合入main/1b8882a（PR #122，0.2.3），一并解决6文件冲突：CI、Agent、Claude Hook、Cursor Hook、Studio、设备信息。main更新检查/下载校验、语言菜单、灵动岛控制、AhaType修复及Claude PreToolUse均保留。

此前WS1/WS2开发已在connect&talk，不是本PR才首次引入。本PR主要是同步0.2.3与处理交叉影响；合并后便于在同一基线继续。仍是不依赖Runtime的旧客户端适配检查点，不能等同完整新固件正式发布。

## 已开发基线与本PR变化

已开发：按能力区分新旧固件，未知只读；配置快照与单键/模式/待机/实体拨杆绑定窄写入和读回；明确授权的App Voice接管；统一设置及精确成功回执；实时状态与Factory Auto绑定校验；停止/卸载/移除Hooks时暂停并撤销有归属自动配置。

本PR保留main的Cursor Shell/MCP原生ask和自动白名单行为，同时纳入共享锁与权限项归属撤销。旧完整备份仅识别此前注入权限，保留用户后续字段，不复制整份备份覆盖当前配置。新cli-config保留version=1。Claude的PreToolUse与PermissionRequest统一使用实时证明与暂停门控。

独立审查发现并修正：状态查询超时后不再复用无请求ID的连接（拒绝迟到状态，重连后才重新接受）；Kimi default_yolo目标命名空间为表/点分键时拒写，防止生成TOML冲突。

## 验证边界

整合前基线203测试，初次main整合222项通过。最终测试/签名构建与提交在下方补录。自动检查不替代真机；此前真机证据按原提交记录在CONNECT_AND_TALK_HANDOFF.md第13–20节，不称为本次整合包已重新通过。

本轮不安装或启动候选、不切拨杆/Voice、不修改用户CLI配置。已安装客户端保持0.2.3/source1760a3f，由并行会话管理。切换候选需协调GUI/Agent同源，避免混用导致测试归因错误。当前物理语音已在此前明确授权后切为App接管（onboarding=3/F18），不要假设仍是Consumer，也不要直接回写旧E7绑定。

限制：已打开CLI可能缓存策略，需按各CLI方式重载/重开；已授权工具不追溯撤销。无归属历史Codex never及用户预存的自动权限不擅改。强杀/崩溃不承诺GUI正常停止清理。管理期间用户主动增加同名权限项的意图无法区分，应核对后再撤销。

## 后续WBS与完成定义

1. **U01/H02/Q02整合真机**：同源GUI/Agent，先只读识别；验证六标签、提案取消/成功/失败、四类CLI手动/自动/未知、Hooks移除/重装、停止Agent与GUI接管、Custom/Disabled不自动。写入先记原值、读回并恢复；补截图。
2. **Q01/Q02旧固件与故障**：旧保存功能、真实断连/拒绝/迟到ACK/超长读回、单键/模式/待机断电保持；不将fixture数当作HIL通过。
3. **WS3/L01**：重新读取最新Fireware-harness，确认显示资源地址/容量/保存与失败恢复契约，完成OLED/GIF/灯光适配再开放写入。当前禁用的入口不得绕过能力授权或使用旧布局全量写新固件。
4. **最终发布**：旧客户端已有功能必须一同完成并通过新旧设备回归；新增WS4/5可独立发布。另行版本号、签名公证和发布，不以本PR当正式发布。

详细证据：CONNECT_AND_TALK_HANDOFF.md。计划/WBS：../ahastudio/legacy-macos-ws12-adaptation-plan-2026-10-08.md及对应wbs md/csv。固件清单：FIRMWARE_FOLLOW_UP_2026-10-09.md。只提交源码文档，不提交安装包、用户配置、原键位备份、录音或凭证。

## 最终检查结果

最终候选源码0463463。224项测试全通过；两路独立审查复核确认状态超时P1、Kimi命名空间P2关闭，无新增实质阻塞。新Cursor schema fixture通过。0.2.3 arm64 Release与Developer ID深层签名校验通过，构建路径 /Users/heartline/Documents/Codex/local-builds/connect-talk-pr-integration-final-20261016/AhaKey Studio.app；未安装/未启动。只读确认当前安装source1760a3f。范围差异检查通过。后续仅注释/证据文档更新不改变候选运行逻辑。

PR：head codex/connect-talk-v023-integration → base connect&talk。未向main提交或合并。此检查点保留上述真机/界面/WS3待验收事项，接手后先按此清单验证再继续后续功能。
