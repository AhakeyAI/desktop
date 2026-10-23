# WD-005 汇总修复路由结果

日期：2026-10-18。Windows DLA完成治理准备，不是生产实现完成。

## 实际执行

1. 保存Owner汇总修复授权、revision 3增量合同和外部协作工单；原八项批准资产未修改。新增四个Windows精确路径，保留high_impact。
2. 原change.json/STATE逐字节备份。原change SHA256为372cb08a57fae3d2a1a156c8a93d7f3baaf19741a408f68320acc076a10066f7。
3. contract-reconcile写入revision=3/build_round=4及IMPLEMENT/IMPLEMENT/DIB路由后，最终origin检查因兄弟目录新增运行配置返回退出码1。不能把第一次调用描述为无错误成功；没有再次reconcile或手改状态。
4. Owner随后明确同意保留BLE_tcp_driver_package/config_server.json作为本机运行配置，不纳入源码/候选。文件SHA256为177951257d50e9e01605b74e5fbe0935cf692ae376695a49a3866f40f5f3c951。正式reconcile-foreign退出0，原起点保留。
5. DLA执行 `python .agents/skills/ahakey-desktop-harness/scripts/desktop.py preflight --role DIB --id WD-005`，退出0，输出DIB PREFLIGHT PASS。这是DLA代查实现准入，不等于DIB已接单/实现/审阅；DIB接手必须重新运行。

## 身份与状态

- 当前revision=3、build_round=4、phase=IMPLEMENT、mode=IMPLEMENT、next_actor=DIB。
- 源码指纹仍为aea60d8c7eb936cb937cc59522fed7224c845ecf7947cedb17e8f029ad1656c8。
- start-fingerprint.json字节SHA256仍为849598f1b9d53bf9ff8e804459a1b053e6ce946d8c9b7db75c039cb07a1e1fc0。
- 本轮只改Windows治理文档、合同元数据和正式工具记录；无生产/测试/桥接/固件代码修改，无构建/运行/Hook/设备/Git写入。
- 旧两点preview-fix token保留历史，不用于本次扩展范围提交。后续按本revision常规IMPLEMENT/submit，再DLA实际审阅与独立Preview准备。

## 交接与缺口

Windows实现窗口读取PREVIEW_FIX_CONTRACT_R3_20261018.md，先做无外部依赖的UI、日志配方、运行态身份/反馈和上传诊断。上传根因仍未定项必须真实报告，不自动关闭。

外部工单CROSS_COMPONENT_WORK_20261018.md分别交桥接负责人和固件AIA，按各自规则登记。尚未在对应窗口接收/派发，不宣称三端同时已开工。Windows DIB不得修改兄弟目录或固件，也不能以Windows测试通过关闭RT-03/BLE-PERF-01。

DIB完成后新增实现报告与实际测试证据，不覆盖历史冻结报告/审阅/包；DLA逐项审实际diff，检查旧功能回归、身份归属、上传安全、UI状态。正式fresh、candidate、产物、固件身份、Owner真机测试仍为后续门禁。没有新的可测试包。

Harness观察：本次contract-reconcile先写后最终检查外部快照，造成一次退出失败但revision已前移；本记录保留实际经过。已通过受支持的归属协调和preflight恢复，不修改guardrails.py或seal。此工具原子性观察不混入DIB生产修复范围。
