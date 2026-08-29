# 任务卡 HIL-RELEASE-0.4：纯硬件语音增量发布门禁

计划/WBS：6.0B / v0.4
状态：`draft`（`USER-GATE`）
执行 owner：Cursor
验证协作者：Zcode；Codex 验收
基线：WBS 2、WBS 4.1-4.4 与 WBS 5.8 accepted 后冻结

目标：证明 macOS/Windows、USB/BLE 下系统与第三方语音由固件独立工作，Studio/Runtime 均退出时仍可使用。

完成定义：F5、Win+H、Typeless/Fn/Globe/F19 fallback；平台学习/切换/Unknown fail-closed；AhaType 与纯硬件语音边界；从 v0.3 升级及回滚；适用 CPU/权限证据。

禁止：未获用户批准不得刷机、安装或签名；不得把 AhaType 冒充纯硬件能力。

## 执行记录（append-only）

等待 v0.4 前置与用户跨平台真机窗口。
