# Roadmap

权威范围与门禁见 [`unified-firmware-runtime-implementation-plan.md`](unified-firmware-runtime-implementation-plan.md)。本页只提供产品版本视图。

## v0.2 — 可用 macOS 客户端 Beta

- Runtime/Studio 主链、AI Hook 自动/手动批准、后台检测和防休眠。
- 中央兼容策略只开放当前量产固件已通过 HIL 的功能；OLED/任务图写入隐藏。
- 基础键位/灯效配置必须证明不会附带 OLED/`0x97` 写入。
- 最小正式安装链：签名 DMG、稳定身份、旧进程互斥、覆盖升级、卸载和回滚。
- 当前量产键盘真机门禁及 30 分钟 CPU/RSS。

## v0.3 — 统一固件与 OLED

- WBS 1.5-1.7：EEPROM journal、图片持久化/恢复、USB/BLE 与双 pack。
- OLED 受理前编码、局部提交、真实字节进度。
- HIL-E1 与配置事务 C1-C6；用户批准后刷机。

## v0.4 — 纯硬件语音

- macOS F5、Windows Win+H、Typeless/Fn/Globe/F19 fallback。
- USB/BLE 平台识别、学习与 Unknown fail-closed。
- 系统/第三方语音不依赖 Studio/Runtime；AhaType 仍由 Runtime 提供。

## v0.5 — 拨杆快捷键与宏

- 三档自定义快捷键、宏、无动作和系统动作。
- release-all、重入、快速越档与配置/升级互锁。
- 与 AI 自动批准拨杆状态保持正交。

## v1.0 — 正式统一版

- macOS/Windows Studio 与 Runtime Adapter 对齐。
- 完整权限/安装迁移、升级/降级与回滚。
- Standard/Rhino 量产包、完整 HIL、性能、10 台内测、50 台灰度和正式发布。

## v1.1 — 会话定向

- Codex App 精确会话唤起、SessionSelector、TargetLease 和安全草稿。
- iTerm2/tmux 首批 Adapter 与多会话错误目标注入测试。
- 不反向阻塞 1.0。
