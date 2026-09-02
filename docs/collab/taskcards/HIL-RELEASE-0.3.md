# 任务卡 HIL-RELEASE-0.3：客户端 OLED 兼容版发布门禁

计划/WBS：6.0B / v0.3
状态：`draft`（`USER-GATE`）
执行 owner：Cursor
验证协作者：Zcode；Codex 验收
基线：最终 v0.2.1 + `V03-STUDIO-OLED-LEGACY-COMPATIBILITY` + `HIL-V03-STUDIO-OLED-COMPATIBILITY` accepted 后冻结

目标：生成 v0.3 不可变 macOS 客户端候选，完成签名、公证、升级/回滚和已登记旧固件 OLED 兼容回归。v0.3 不包含固件产物，也不要求刷机到统一固件。

完成定义：正式 Studio UI 在 GitHub Standard、Gitee Rhino、Local Rhino 冻结基线上通过对应图片写入/显示/断电保持矩阵；Runtime 字节进度正确；未知固件 fail-closed；从 v0.2.1 升级、卸载、回滚、XPC/Hook/BLE/KeepAlive 无回退；公开兼容清单、已知限制、签名公证 DMG 与 SHA 完整。键盘端旧 Rhino `0,0` 作为固件显示限制披露，不阻断客户端发布。

禁止：未获用户批准不得安装、签名或切渠道；本卡不刷固件、不擦 EEPROM。不得在 HIL 卡顺手修业务代码，不得用专用 HIL 驱动代替正式 Studio UI。

## 执行记录（append-only）

等待 v0.2.1 收口、v0.3 客户端实现与正式 UI 旧固件矩阵。统一固件 WBS 1、`HIL-CONFIG` C1-C6 及平台快捷键不再是本卡依赖。
