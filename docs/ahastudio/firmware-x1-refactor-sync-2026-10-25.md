# 新固件分支同步与客户端适配增量 — 2026-10-25

已从指定仓库拉取 `origin/harness/x1-refactor-main`，锁定 `0a055ba95f857a1d32f05b79bcabd3ecfe78d4eb`。本机固件仓库为 `/Users/heartline/Documents/Codex/AhaKey-X1-unified-firmware`，只更新远端引用，保留现有干净工作分支。客户端仍统一在 `connect&talk` 开发。

## 已改变的依赖结论

| 事项 | 新代码事实 | Mac 接续 |
| --- | --- | --- |
| Consumer 恢复、逐模式混用 | CP2.6 已实现 `0x9E` v1 的能力挑战、切片读取、开始／分块／提交；4个模式分别保存普通或Consumer路由 | 不再等固件提供命令；在现有 Key1 侧栏接入同连接能力核验、真实路由读回、冲突确认和当前模式写入 |
| 旧全局退出方案 | 新显式路由独立于旧 `0x96` suppress；Consumer 会清该模式普通K1绑定，切回普通需完整提交动作 | 新设备可单模式恢复 `0x00CF`；旧设备保留准确的全局退出提示，不能对所有设备直接删限制文案 |
| 恢复初始化 | `0x9E/0x30` 状态、`0x31` 开始／手动重试已实现 | 开发用户确认、外接USB供电门控、失联后只查询、不自动重发、失败／未完成引导、完成后全量读回 |
| WS3 CP3 | 最新工作流明确原CP3已被WS45 Restore替代，不能继续列作独立待实现协议 | 单位置默认恢复仍走0x8D；整机恢复走新Restore，两者范围分别说明 |
| 上传／内存／断连 | CP2.5新增协作式Flash写入、连接代际与排他处理；工作流为PASS_WITH_DEBT | 重新验收取消／断连、长动画与CPU，不把旧“必须重启”结论直接套到新固件，也不凭源码宣布真机已解决 |

来源：[命令注册](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/0a055ba95f857a1d32f05b79bcabd3ecfe78d4eb/.ahakey-harness/contracts/x1/protocol-commands.yaml)、[实际命令处理](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/0a055ba95f857a1d32f05b79bcabd3ecfe78d4eb/APP/sub_main/command_solve.c)、[路由存储](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/0a055ba95f857a1d32f05b79bcabd3ecfe78d4eb/APP/services/k1_restore_store.c)。历史Architecture中“proposed/start locked”段落与后续修订共存，现状以实际实现、最新注册及精确候选收据交叉判断，不采用旧标题作为阻止客户端开发的理由。

## 接入顺序与约束

1. P0：实现并测试0x9E协议编解码和严格相关性匹配。新请求／响应使用随机非零nonce、版本和子命令，拒绝旧六字节ACK；能力不能由相同catalog key猜测。先补协议底座，不自动给连接设备发写入。
2. P1：接入Key1同连接读取与单模式事务，Consumer／App原生／AhaType／自定义快捷键分别保留正确的硬件路由与Host策略。先读真实路由，保存前再核对；只修改当前组件，其他模式和草稿保留。选择Consumer后不会偷偷保留旧普通动作作为回退。
3. P1：接入Restore状态与确认流程。该操作重置键位／宏／描述、拨杆动作、Voice默认、待机、灯光、模式与19位置素材元数据；保留身份、BLE配对、名称／Appearance及工厂资源。Coffee的自定义引用会被清除，因此当前键盘不用于未经确认的破坏性验证。
4. P2：代码全部接线后，先自动／隔离验收，再统一刷入精确组合候选，集中实体输入、语音、屏幕、恢复和断电保持。

事务要求：四模式route每条固定102字节，普通动作最多100字节；Consumer为2字节LE Usage，当前恢复Mac听写使用0x00CF。读取片段必须同模式、同总长、同全记录CRC再组装；分块按精确ACK推进；提交回包丢失后读回解决，不盲重提。全四模式操作须用户明确选择，普通单键保存不使用selector=0xFF。固件写入中断不承诺保留旧K1路由，无有效记录时K1可能停用，K2-K4仍可用，客户端必须识别并引导重新保存。

Restore的handled=0状态码仅表示请求被处理；只有状态COMPLETE及实际默认值读回一致才显示成功。需要USB外接供电，不要求USB数据已枚举；不能把BLE连通误当供电满足。没有取消命令；中断后的INCOMPLETE仅在用户明确重试时发新请求。不会自动刷写或恢复当前键盘。

## 精确固件交付与证据边界

组合候选源码为 `292a49f32939e2b778b15eceb194746133d3b2c7`，记录的HEX SHA256为 `6EC0413CFC983788CDC99F628F0F8E2A64C6AF147D2A5E1727A03F036BF1123C`。正式REGATE收据13项检查均PASS。最新记录为Owner报告组合UAT通过，但checkpoint review仍记录材料不足；这不阻止客户端按现有代码接入，也不等同Mac侧真机验收已完成。

记录路径 `.ahakey-harness/evidence/builds/ws45-cp2_6-restore-combined-regate-20261025/HID_Keyboard_582m_vibe_coding.hex` 未包含在该提交的Git树，因而当前无法从此分支取得并独立核验这份HEX字节。刷机前需拿到该精确文件或发布下载地址，不能用旧HEX或另一次构建冒充。此项是交付输入，不阻塞编码。

[组合UAT记录](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/0a055ba95f857a1d32f05b79bcabd3ecfe78d4eb/.ahakey-harness/evidence/owner-uat/X1-PLATFORMIZATION-RELEASE-COMPOSITION/WS45_CP1_RESTORE_INITIALIZATION/WS45-CP2_6-COMBINED-OWNER-UAT-PASS-20261025.md)。WS3仍列容量/栈、目标stack/heap及协作时序三项NOT_VERIFIED，不能归并成已测通过。独立短／长按绑定和Kimi原版实时审批仍未由这批变更解决；正式发行目录／信任公钥／恢复安全发行材料另行核对。

## 本机恢复与候选

build376（e3e210a）已签名安装、CI40173065317通过，实体拨杆手动／自动对应原Codex会话on-request/:workspace与never/:danger-full-access，均独立读回确认。正常停止后台后租约清空并保留原权限／用户授权；本轮原权限基线就是完全访问，不替代受限基线授权回收和崩溃矩阵。

临时多任务＋终端跟随开关已通过底部统一提交；因终端激活工具不可用，真实窗口跟随未完成。随后明确写回单任务＋关闭跟随，成功弹窗选择完成编辑，原2项草稿未变，未写Coffee／按键／Voice。

## 本批客户端开发证据

已新增共享K1路由值模型与0x9E v1请求／回复编解码，覆盖Consumer/普通动作、挑战、切片、分块推进、提交CRC及Restore状态。7项定向测试和687项完整Swift测试通过；包含旧六字节ACK、错误nonce／版本／模式／偏移、越界及“已处理不等于恢复完成”的负例。尚未接入蓝牙事务或侧栏，因此安装版376仍不具备新Consumer恢复入口，不能宣称端到端适配完成。
