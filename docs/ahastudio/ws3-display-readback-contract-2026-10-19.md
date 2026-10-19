# WS3 显示只读契约与候选核验（2026-10-19）

## 已核验的事实

固定源码：Fireware-harness / 70ca334f65d73b6a2f20a0598e55c6da59f26526。不能再根据过时的 project-state 下一步字段认定 CP2 尚无实现：command_solve.c 已有 0x88–0x8E，资源映射、存储和上传事务已接线。工作流 STATE.yaml 当前为 ready_for_regate；CP1 接受源为 f2092f7516b4296cd015733085a8bf2af8b3d62c。

内存修复候选：.ahakey-harness/evidence/candidates/WS3-CP2-20261018-memory-safety/X1_MEMORY_FIX_20261018.hex。Git blob e72b550c3e943075ddbfd09272e2aec5b5c1378a。本轮已下载到临时目录，校验 Git blob 身份、全部 Intel HEX 记录校验和/EOF/重复地址一致性，共28666记录、458492加载字节，地址0–458491。原始SHA256为 ffb9208f79084aa24a832ad2562a14dbbea5df4d114a135cb5b2eb98d4e05539，与固件artifact-verification-snapshot一致。

这只证明下载对象身份和文件结构。闭环记录仍写明 build_artifact_pending_fresh_regate，用户通过反馈没有再次明确绑定最终正常构建身份；本轮没有刷入或在设备运行此HEX，不宣称已通过Mac真机或正式固件验收。现有Harness资料已足够推进只读和接口开发，无需向固件方重复索要整套说明。

## 只读0x88

所有请求、响应都有 AA BB 前缀和 CC DD 后缀。下表只列中间内容，响应首个00是status。所有多字节整数为little-endian。

| 项目 | 请求 | 成功响应 | 完整响应长度 |
| --- | --- | --- | --- |
| 亮度 | 88 00 | 88 00 00 brightness | 8 |
| SINGLE灯效 | 88 01 mode state | 88 00 01 mode state effect | 10 |
| 资源基本状态 | 88 02 entry | 88 00 02 entry user_valid write_state | 10 |
| 资源完整性元数据 | 88 03 entry | 88 00 03 entry frames:u16 payload_bytes:u32 crc32:u32 | 18 |

mode为0–3，state为0–8，entry为0–18。write_state依次为EMPTY=0、WRITING=1、VALID=2、INVALID=3。默认项0/4/8/12最多8帧，其他项最多12帧；每帧7*4096=28672字节，payload_bytes必须等于frames*28672。非有效资源完整性字段按固件返回全0。当前表覆盖全部19项，早期架构文字里的“默认项不开放”不能覆盖后续修订及当前实现。

通用6字节成功ACK不代表有读回数据，旧CP4D可据此返回“不支持”。非零6字节错误不升级能力。响应必须匹配selector及mode/state/entry，固定长度解帧不把CRC中的CC DD当作帧尾。

## 本次客户端行为

仅在已知WS2目录、同一有效配置连接上发送严格0x88只读请求。新设置页先读亮度，再逐项读19组basic/integrity；只有全部成功且会话仍有效才发布快照。取消、超时、交接清除该快照。旧固件不支持时明确提示，不修改现有显示配置。

界面展示键盘报告的亮度和有效自定义素材数。元数据CRC不是实际资源字节校验，读回也不是断电持久化证明。所有新增查询都不导入画布、不上传、不清空、不保存；0x89–0x8E写入口及WS3呈现能力没有因此开放，也不把相同catalog key当作HEX身份。

新增8项fixture测试覆盖选择器与边界、未知效果只读保留、little-endian CRC、二进制帧尾、短ACK、错项回包、容量和元数据组合；完整测试248项通过。仍需旧CP4D与该候选的真机读回/取消验证。

## 后续开发

1. 按固定契约开发D03预览/保存及D04分块上传，逐项窄授权、会话冲突保护、ACK后读回。上传块上限48字节，还要扣除命令开销适配实际MTU，不能静默截断。
2. CP1的0x98是set-only，0x99只接收version=1完整四槽快照；0x9A只代表链路ACK，不证明显示、资源或续命成功。错误显示模式下返回OK也不能当作状态已应用。D02仍需单独接入。
3. 写入真机前锁定实际HEX与设备；发布以固件团队最终候选和Mac联调结果为准。保留Consumer方案，F5继续暂缓。

## 来源

- [命令入口](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/70ca334f65d73b6a2f20a0598e55c6da59f26526/APP/sub_main/command_solve.c)
- [资源映射](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/70ca334f65d73b6a2f20a0598e55c6da59f26526/APP/services/resource_map.c)
- [上传事务](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/70ca334f65d73b6a2f20a0598e55c6da59f26526/APP/services/resource_upload_transaction.c)
- [存储及元数据](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/70ca334f65d73b6a2f20a0598e55c6da59f26526/APP/services/display_config_store.c)
- [候选核验记录](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/70ca334f65d73b6a2f20a0598e55c6da59f26526/.ahakey-harness/evidence/checkpoints/X1-AI-WORKFLOW-PRESENTATION/CP2/closure-prep/20261018-memory-fix-owner-pass/artifact-verification-snapshot.json)
