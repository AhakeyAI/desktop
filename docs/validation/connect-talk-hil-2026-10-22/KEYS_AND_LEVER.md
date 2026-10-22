# 按键与实体拨杆补验

候选：0.2.3，源码f719026，2026-10-22。仅当前Mac和当前CP2内存修复固件，不代表旧设备、真实CLI生命周期或全部宏容量矩阵通过。

## 16键读取与取消

通过虚拟键盘选组件、右侧修改，逐项确认固定Mode/Key和“已读取”，再返回。四模式各4键均通过，合计16/16；每次退出未同步改动0。保留现有键位，包括Claude现有宏，未重写Voice。原始逐项界面证据仅保留本机。

快速连续“返回→浏览其他模式→修改”时，一次后台重连的实体模式更新先于进入编辑，目标回到实体Codex；因目标核对不符中止，未计入Cursor通过、未写硬件。等待交接稳定后，Cursor四键逐项按目标确认通过。记录为浏览期间连接交接体验问题，不能将它与已修复的编辑中目标锁定混为一谈。

## 非当前模式单键描述往返

实体保持Codex Mode3，在Cursor Mode2 Key4仅把描述Backspace临时改为Backspace HIL，底部“写入键盘”。成功弹窗明确Mode2/Key4；选择继续编辑仍留在该目标，界面显示保存并读回一致、未同步0。随后恢复Backspace并写入，成功弹窗按Return走默认“完成编辑”，退出编辑并交还Agent。再次独立进入Mode2/Key4读取，描述Backspace、绑定Backspace均恢复。

只验证本次描述往返及产品回执范围，没有开启详细BLE包记录；不声称已通过所有16键动作写入、长宏、真实外部冲突或断电保持矩阵。Coffee、灯效、其他按键和Voice未主动写入。

## 实体手动／自动与安装包Hook

用户切手动后：实时physicalSwitchState=1、switchState=1、autoVerified=false，界面手动批准。实际运行已安装Agent的Hook处理器：Claude PreToolUse无放行输出，PermissionRequest=ask；Cursor beforeShellExecution=ask，preToolUse=allow交回原生权限层（此事件不支持ask）；Codex无allow决策、approval_policy=on-request；Kimi无放行输出、default_yolo=false。

用户切回自动后：physicalSwitchState=0、switchState=0、autoVerified=true；Claude两个权限事件、Cursor两个事件及Codex均返回allow；Kimi仍按协议无stdout，default_yolo=true；Codex为never。所有Hook进程退出0。

测试使用独立合成session id，不执行工具命令；完成后通过各自结束事件关闭测试状态。此项是实时硬件到安装包Hook处理器及策略落盘验收，不代替Claude/Cursor/Kimi真实CLI重装、会话重载、异常退出验收。
