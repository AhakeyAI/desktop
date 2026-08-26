# 任务卡 WBS-5.9-INSTALL-MIGRATION：正式 Runtime 安装与升级迁移

计划/WBS：5.9  
状态：`draft`（`USER-GATE`）  
执行 owner：Cursor  
基线：WBS 5.3-5.8 accepted 后冻结  
目标：交付稳定签名 Runtime helper/login item、旧 Agent 清理、Keychain/权限迁移和原子升级/回滚。

允许修改：macOS Packaging、helper/login item、升级器、权限迁移、相关测试与文档；精确清单晋级时冻结。  
禁止：不静默扩大 TCC/全局 Hook 权限；不删除第三方 Hook/用户配置；不直接发布。  
完成定义：macOS 13+ SMAppService、macOS 12 兼容路径；稳定 Bundle/Signing ID；旧 Agent/重复 Hook 清理；Keychain/TCC 迁移；安装/覆盖升级/降级/卸载/回滚原子；失败可恢复。  
测试：干净机、当前版升级、上一支持版升级、降级、签名验证、重启/登录；签名包仅在用户批准窗口构建安装。  
用户门禁：需要本机签名、安装和登录项变更前由用户确认。

## 执行记录（append-only）

等待用户门禁。
