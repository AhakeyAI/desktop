# 任务卡 RELEASE-0.2-COMPATIBILITY：0.2 当前固件兼容策略

计划/WBS：0.2 发布列车 / 兼容功能面
状态：`draft`
执行 owner：Cursor（Codex 验收）
基线：E-1R1 review 关闭后由 Codex 冻结；未 accepted 的 OLED 改动可冻结到 v0.3，不成为本卡产品依赖
目标版本：v0.2 macOS Beta

目标：建立一个集中式 `ReleaseFeaturePolicy`（名称可按代码语境调整），以发布版本、固件能力和已通过 HIL 的能力为事实来源，确保 0.2 只开放当前量产固件可靠支持的功能。

## 必须交付

1. OLED/任务图编辑与写入在 0.2 中隐藏或只读；不得靠分散的 View 条件判断。
2. 基础键位/灯效配置的 planner 必须证明不会生成 OLED 资源、`0x95`、`0x97` 或其它依赖统一固件的步骤；无法安全拆分时 fail-closed，不提供按钮。
3. Runtime 仍是唯一 BLE/USB owner；不得恢复 Studio 直连 BLE 回退。
4. AI Hook 自动/手动批准、后台设备检测、防休眠和 Studio 退出后的持续运行保持可用。
5. 兼容策略必须有版本/能力矩阵测试，旧固件、未知能力、畸形能力帧一律保守降级。
6. UI 必须明确标出 0.2 已开放能力与“需 0.3 固件”的能力，不得让用户进入必失败流程。

## 禁止事项

- 不实现统一固件、OLED 新功能、语音、拨杆宏、Windows 或会话定向。
- 不跳过 `0x97` 来伪造 OLED 成功；0.2 根本不暴露该写入面。
- 不安装、不覆盖 `/Applications`、不签名发布、不刷机、不 push。

## 门禁

- 当前量产固件 fixtures 的可见/可写矩阵。
- 基础配置生成包的 opcode/resource 白名单测试。
- 未知/旧/畸形 capability fail-closed。
- 全量 Swift 测试、App+Agent Release build、`git diff --check`。
- 完成后停手提审；不得自行进入 WBS 5.9A。

## 执行记录（append-only）

等待 E-1R1 review 关闭与 Codex 晋级 `ready`。
