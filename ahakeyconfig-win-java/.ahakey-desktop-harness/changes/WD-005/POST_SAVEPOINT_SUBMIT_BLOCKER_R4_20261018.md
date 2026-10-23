# WD-005 存档后正式提交尝试：新外部快照阻塞

日期：2026-10-18。角色：DIB。revision=3、build_round=4。追加真实结果，不修改既有接续或冻结执行报告。

## 已完成

- 接手 preflight 实际退出0、PASS。
- 核对 HEAD=f595262207796dbf325cb9951ed3dc02b4887362；源码指纹 e298ea1dd15131f508a602deed06181e0a53c6ff8b5c2366674dfc0cfb44d49d 不变。
- 检查表16项源码和25份证据哈希41/41匹配；git diff HEAD -- src无差异。
- 新增 POST_SAVEPOINT_CONTINUATION_R4_20261018.md 和 POST_SAVEPOINT_HASH_OBSERVATION_R4_20261018.json，未重跑测试/编译。
- 正式 record-check 四项均实际退出0：machine、core_regression、special_regression、mock。当前verification四项均round4、同源码指纹，绑定新接续及第4轮真实报告/日志。
- 上述登记仅确认各自执行范围；397项断言为既有第4轮执行，不能推导完整App/桥接/固件/UAT通过。

## 实际submit失败

实际命令：
python .agents/skills/ahakey-desktop-harness/scripts/desktop.py submit --id WD-005 --role DIB

退出码：1。原输出：
HARNESS STOP: SIBLING_WORKSPACE_CHANGED: BLE_tcp_bridge/TcpServer.cs; classify ownership in a reviewed reconciliation, no auto restore

守卫拒绝发生在正式提交前，当前STATE仍IMPLEMENT/IMPLEMENT、next_actor=DIB。IMPLEMENTATION_RECEIPT.json仍为第3轮，没有第4轮提交成功回执。未手写回执或路由。

## 新旧外部身份

- 已正式接受的 TcpServer.cs SHA256：0698dc8e8c4ed05f193f03ea75923285adfffe2477ff5c368da8ca5d6ad3cfe9。
- 失败后只读观察到的 TcpServer.cs SHA256：4affeac500910265c728aa09fd99bb4f218e088d53b352a0093f7dfa1868041f。
- 新变更需原DLA核验实际责任及授权，不能沿用旧快照无限放行。DIB未读取/审阅新桥接逻辑或认定它正确，也未修改、还原或暂存桥接代码。
- 本次Windows源码与HEAD在失败后再次核对仍一致；原起点/原批准/旧报告哈希保留。
- 若桥接仍在独立退修，DLA应先确认适当稳定交接时点并登记精确外部快照，再交DIB尝试正式提交。不能为避免再次阻塞而扩大忽略目录、修改规则或自动重复reconcile。

## 后续

交原DLA做此次新外部归属协调，不是DLA actual review已经开始。合法协调后DIB重跑preflight并核对同轮检查有效性；四项已登记不需假装重跑或回滚，发生相关输入变化则按权限处理。最终submit成功后才进入DLA_REVIEW。

UP-01/UP-02真实根因及恢复、RT-01缺来源事件、RT-03固件主槽回退、BLE-PERF-01真机A/B、完整应用和正式配对仍未完成。无新candidate/Preview、构建打包、应用启动、Hook安装、设备写入、烧录、发布或Git写入。本记录只是失败事实和接续说明，不替代正式状态。
