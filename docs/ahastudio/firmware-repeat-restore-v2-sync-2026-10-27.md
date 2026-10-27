# WS45 Repeat Restore v2：固件增量与Mac接入 — 2026-10-27

## 已核对的固件事实

2026-10-27 22:23（Asia/Singapore）重新核对，`harness/x1-refactor-main` 为 `ed426c97d4aad9a20c1585d6b15125252b6caa49`，较0a055ba新增4035fca（实现/契约）和ed426c9（隔离REGATE输出）两提交；客户端main仍为0ddab17。未切换或修改固件工作分支。

[Stage B amendment](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/ed426c97d4aad9a20c1585d6b15125252b6caa49/.ahakey-harness/evidence/stage-b/WS45-20261026-repeat-restore-after-complete-amendment.md) 与独立Stage C PASS已给出新增合同。生产源码中实现了重复恢复，但新候选尚无本轮正式REGATE PASS/HEX。原6EC041…字节对应292a49f，不包含v2，不得拿旧包验证本次修复。

旧readiness记录来自4035fca后EXECUTION输出路径调整前的工作树；ed426c9已提交路径/合同绑定内容。不能据旧记录断言当前仍有未提交EXECUTION，也不能假装已重新获得READY_FOR_REGATE。正确下一步是在固件原工作目录重新跑Candidate Prep，实际READY后按新输出目录执行13项正式机器门禁。

新OutRoot/HEX目录：`.ahakey-harness/evidence/builds/ws45-repeat-v2-regate-20261027-4035fca/`。保留旧6EC产物、原锁/历史证据；不将旧HEX复制成新构建，不执行过期owner-isolate脚本。固件当前STATE的 `current_can_flash_test: false`、`regate_performed: false` 未被本轮Mac工作改写。

## 精确协议与兼容策略

- 查询不变：`AA BB 9E 01 30 <nonce:u32le> CC DD`。
- V1首次/失败重试不变：`AA BB 9E 01 31 <nonce:u32le> CC DD`，限NEVER/INCOMPLETE。
- 新重复恢复：`AA BB 9E 02 31 <nonce:u32le> <expected_next_attempt:u32le> CC DD`，15字节；回包17字节，必须回显版本2和原nonce。nonce只做相关性，expected attempt必须等于新鲜持久计数+1，禁止0与溢出。
- 同catalog key或v1状态读回不证明v2能力。Mac保留首次/失败重试的v1兼容路径；只有用户明确从COMPLETE发起一次新恢复才用v2。侧栏说明旧固件可能拒绝，不将其显示为已经确认支持v2。
- 不降级、不自动重发。v2错误版本、坏nonce、丢回复/断连不触发v1 fallback，不在失效连接上盲读；之后由用户重读状态恢复事实。

## Mac行为与完成标准

1. 编码/请求反解只增加0x31 v2，不能扩散到v2状态/路由命令；0x30保持v1。零attempt、截断或未知版本被拒绝。
2. 回包、stream framing及matcher覆盖nonce/attempt包含CC DD的任意分包；v1/v2回包不能互认。
3. 仍须同连接新鲜Restore事实、专用写授权、USB供电声明、显式范围确认和新鲜状态对比；不借K1授权写Restore。
4. COMPLETE允许再次勾选，底部唯一写入不变。每轮完成/读回都会清确认勾选；读取、重连和进程重开不启动恢复。
5. 已拒绝且state/attempt保持不变，才能清本次未确认标记；attempt已前进却返回失败是已开始但未完成，保留恢复指导，不说完全未动。
6. 丢回复后新鲜终态读回可解除提交不明的阻塞，但不发布写入成功或默认值已验证；新一轮仍要重新选意图/供电/确认，并按新状态生成v2 attempt token。
7. 只有完整默认设置独立读回一致才报verified；版本/设备/代次改变、计数不符、未知回包不伪造成功。

## 当前证据与边界

初始6个新协议测试在旧客户端产生6个失败（含1个预期之外的抛错）；已接受但失败的恢复分类/明确拒绝后的阻塞另以2测试2失败复现；丢回复后新鲜终态和新确认以1测试2失败复现。92项定点检查及首轮940完整回归通过；最后补齐重开边界后941项完整Swift回归通过。

从精确ed426c9归档，仅以本机clang执行现有 `test_restore_initialization.c` +实际store/coordinator，编译/执行均0，输出 `PASS: RESTORE_INITIALIZATION_HOST_TESTS`。这是辅助host证据，不是正式13项REGATE、生产dispatcher整体门禁或硬件UAT。

日志：`/tmp/ahakey-restore-v2-red-20261027.log`、`/tmp/ahakey-restore-v2-refusal-red-20261027.log`、`/tmp/ahakey-restore-v2-reopen-red-20261027.log`、`/tmp/ahakey-restore-v2-final-full-20261027.log`。新源码未生成HEX、未刷写、未恢复设备。已安装build516不含本轮v2；原2草稿、当前右Alt语音键、Coffee元数据/实际设备不写入。

Mac仍需独立复核及签名候选。新固件实际READY→REGATE PASS→新HEX/SHA/UAT Brief，与对应Mac候选齐备后，再安排集中ISP与重复恢复验证。固定身份、备份/readout、牺牲样机/相邻页sentinel和恢复路径仍按固件UAT合同，不由本地host测试替代。
