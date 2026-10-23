# WD-005 Windows 第一份源码存档回执

日期：2026-10-18。Owner 本轮明确要求先将当前代码 Git 保存，便于后续恢复。

## 实际保存

- commit：f595262207796dbf325cb9951ed3dc02b4887362。
- 原父提交：41c034171e60b2d4962b0adbe8f3cffbf80a0436。
- 分支：main-anpx；未新建或切换分支，未 push。
- 标题：WD-005 first Windows source savepoint (unreviewed)。
- 当前 revision 3 / build_round 4 的 Windows 源码、测试及相关合同/归属/检查记录，共57个变更文件；精确范围见 FIRST_SOURCE_SAVEPOINT_MANIFEST_20261018.json。
- 这是当前实现的恢复存档，不是最初 Preview 的副本，不是 formal candidate、review PASS、构建或 UAT 通过。
- 不含桥接改动、固件、本机 config_server.json、Harness 脚本维护、其他任务历史 dirty、运行依赖和构建产物。没有还原这些内容。
- 23份被 Git ignore 的日志未强制加入提交；实际文件仍留本机，manifest 记录排除项和哈希。本存档不是完整可移植 Harness 工作区或运行包。

## 提交后核对

- git rev-parse HEAD 确认上述提交；索引为空。
- git diff HEAD -- src 无差异；本轮没有编辑生产/测试代码。
- desktop.py fingerprint 仍为 e298ea1dd15131f508a602deed06181e0a53c6ff8b5c2366674dfc0cfb44d49d。
- desktop.py preflight --role DIB --id WD-005：退出0，PASS。
- 原 start-fingerprint.json SHA256 仍为 849598f1b9d53bf9ff8e804459a1b053e6ce946d8c9b7db75c039cb07a1e1fc0，未重置起点。
- STATE 仍为 IMPLEMENT / IMPLEMENT，next_actor=DIB。未以存档替代正式 submit。
- 提交前核对 round4 检查表的16项源码和25项证据文件哈希，全部吻合；这是证据一致性检查，不是重跑397项断言或实际差异审阅。

## 归属协调与接续

使用 Owner 原有外部工作授权及贴回桥接实现报告，新增 evidence/20261018-wd005-bridge-work-attribution-owner.md；正式 reconcile-foreign 成功，四项兄弟目录变更已登记。此操作只解除已知外部改动的归属阻塞，不代表桥接审阅通过。桥接仍按 BRIDGE_01_DLA_REVIEW_20261018.md 退修。

Windows DIB 再次 preflight，并核对当前源码/测试输入/日志哈希；新增接续记录说明 HEAD 前移但源码指纹不变，不改旧报告中的历史 HEAD、原起点和批准。然后按当前 revision 正式 record-check/submit。若有代码或测试输入变化，重测受影响项；新阻塞回 DLA，不降门禁。

Windows 正式 submit 后，由 DLA 审阅累计实际差异。通过后可按 Preview 流程独立安排 Windows 包；桥接与固件未配对前，BLE性能、首次上传根因、RT-03及来源缺失后台事件仍不能关闭。当前没有新 Preview 包。

桥接负责人继续修复 B-F1/B-F2/B-F3、完成真实编译和受控时序验证；不覆盖现场 EXE。固件负责人依本地 Harness 处理上传/Flash 路径和主槽回退，返回正式证据及产物身份。Windows DLA 从仓库回收事实，维护 Windows JAR / bridge EXE / firmware HEX 版本组合；先受控单端对比，再组合 USB/BLE 联调。不得把单端检查互相替代。

本回执为提交后新增记录，不修改刚创建的提交，不回填或伪造正式候选回执。高影响 fresh、formal candidate、产物/固件配对及真实验收仍待办。
