# 任务卡 HIL-RELEASE-0.3：统一固件与 OLED 增量发布门禁

计划/WBS：6.0B / v0.3
状态：`draft`（`USER-GATE`）
执行 owner：Cursor
验证协作者：Zcode；Codex 验收
基线：WBS 1.5-1.7、OLED E 系列与 HIL-CONFIG 代码门禁 accepted 后冻结

目标：生成 v0.3 不可变客户端/固件候选，完成刷机、安装、回滚和配置事务 C1-C6。

完成定义：Standard/Rhino 两 pack；0x97 持久成功；关机 active set 保留；图片逐块进度；取消/断连/断电恢复；HIL-E1 与 C1-C6；从 v0.2 升级及回滚；兼容策略只在证据通过后开放 OLED。

禁止：未获用户批准不得刷机、安装、签名或切渠道；不得在 HIL 卡顺手修业务代码。

## 执行记录（append-only）

等待 v0.3 前置与用户刷机/安装窗口。
