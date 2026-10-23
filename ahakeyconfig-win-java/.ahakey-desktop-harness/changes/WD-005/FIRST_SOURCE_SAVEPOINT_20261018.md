# WD-005 第一版 Windows 源码存档（未验收）

日期：2026-10-18。Owner明确要求保存“当下代码”便于后续恢复；正式任务ID为WD-005，口头称WS-005。

## 存档输入

- revision 3 / build_round 4；DIB已完成本地实现与检查，但尚未正式record-check/submit。
- 原HEAD及任务起点：41c034171e60b2d4962b0adbe8f3cffbf80a0436，保持旧历史和start-fingerprint不变。
- 保存前工作区源码指纹：e298ea1dd15131f508a602deed06181e0a53c6ff8b5c2366674dfc0cfb44d49d。
- 本次Git范围：FIRST_SOURCE_SAVEPOINT_MANIFEST_20261018.json的paths。Git自身可能规范化CRLF/LF，manifest保存的是暂存前工作区原字节SHA256；不据换行差异冒称逻辑改变。
- 32/33等数量以manifest和实际commit为准；未变的授权文件可以被明确暂存但不会形成commit差异。
- 保留原运行Preview，不修改任何旧JAR/快照。该commit不带JRE、模型、依赖缓存、运行包或现场驱动，不是立即可执行测试包。

## 明确排除

桥接源码/驱动包、固件、config_server.json、其他任务元数据、Harness维护工具/规则、全局STATE、用户配置、历史dirty和生成产物不纳入本次提交；不执行git add -A，不push，不reset/checkout/clean/stash。

## 已核验及仍未完成

DLA核对当前代码指纹、检查表16项源码/25项证据哈希全部匹配；读取编译成功及断言日志，不重跑测试。397项是DIB本轮真实执行报告，不是完整UI/真机证明。

四项桥接文件归属已依据Owner前序授权、Owner贴回的桥接报告和DLA实际diff核验，经正式reconcile-foreign登记。DIB preflight当前PASS；桥接B-F1/F2/F3仍退修，不能混成代码通过。

当前代码还未完成本轮DLA actual review、独立fresh、formal candidate、新Preview构建、配对固件/桥接身份核验与Owner真机验收。上传根因、来源缺失后台事件、主槽回退与BLE性能仍OPEN。

## 恢复与后续汇总

该commit是可定位Windows源码的调试存档，不用于回滚全部共享仓库。未来恢复时先查看当时dirty并另存新增工作，再按此commit的Windows文件范围恢复；不得直接对共享仓库git reset --hard，也不得自动回退桥接/固件/本机配置。

Windows DIB核对HEAD已前移但原任务起点/源码指纹不变，重跑preflight并验证报告证据后正式record-check/submit。历史报告中旧HEAD保持历史事实；新增续接报告写明存档commit与来源不变，不改旧报告。

桥接修复审阅问题并完成编译/隔离检查后单独回DLA；固件按本仓Harness回传主槽/上传修复与正式产物。DLA汇总三端版本矩阵，只在匹配身份与实际审阅后安排隔离Preview及分阶段USB/BLE测试。每条支线独立完成不等于整体PASS。
