# 任务卡 WBS-5.9-INSTALL-MIGRATION：1.0 完整 Runtime 安装与升级迁移

计划/WBS：5.9B / v1.0
状态：`draft`（`USER-GATE`）  
执行 owner：Cursor  
基线：WBS 5.9A、5.8、4.8、5.10 accepted 后冻结
目标：在 v0.2 的最小签名安装链及已冻结的 Windows 5.10 seam 上，补齐 v1.0 的完整 Keychain/TCC/权限迁移、支持版本矩阵和正式渠道升级/回滚。

允许修改：macOS Packaging、helper/login item、升级器、权限迁移、相关测试与文档；精确清单晋级时冻结。  
禁止：不静默扩大 TCC/全局 Hook 权限；不删除第三方 Hook/用户配置；不直接发布。  
完成定义：复用 5.9A 稳定 Bundle/Signing ID；macOS 支持矩阵；旧版本 Keychain/TCC/权限迁移；安装/覆盖升级/降级/卸载/回滚原子；Windows 5.10 安装语义对齐；失败可恢复。
测试：干净机、当前版升级、上一支持版升级、降级、签名验证、重启/登录；签名包仅在用户批准窗口构建安装。  
用户门禁：需要本机签名、安装和登录项变更前由用户确认。

## 执行记录（append-only）

等待用户门禁。

### [2026-08-29] Codex：拆为 5.9B / 1.0

本卡改为完整迁移收口，等待 5.9A 与 1.0 前置；不阻塞 0.2-0.5。
