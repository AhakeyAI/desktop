# 分支纠错与固定推送目标结果

日期：2026-11-04。Owner授权见 evidence/20261104-owner-fixed-zxy-branch.md。

## 已完成

- Windows 1.0.19及相关Harness迁移到origin/win-zxy-harness，迁移提交83136b97cc228da429e9365326721a15f0279988，清单提交c904b98bad17b6619941728651d1e868d42d5f36；远端hash已核实。
- 保留bc633a75目标分支历史，另一个父链保留369da0d7及其全部祖先。原候选b9466fb1仍在目标分支历史中，未改写候选SHA。
- src、scripts、pom.xml、third-party的Git对象与已保存1.0.19输入完全一致；目标分支Windows目录之外无任何文件变化。
- main-anpx采用普通回退提交4b7740f6eacc15fbdc66e753bfcfa1b1f30d5011，远端hash已核实；其完整Git树与误上传前22e49fbbc012ffc642b0d5a0da389dadf0c28e58完全相同（e303465ead5d46a1086a23e0462e5e4c8ebd723f）。没有强推、删分支或改写历史。
- 误上传及回退的历史痕迹保留，属于公开可审计历史；撤回的是文件改动，不声称从Git历史擦除。误上传之前协作者自己的Windows历史没有撤回。
- 已查本地远端reflog，能确认的本次两次误push均已撤回；没有证据把原协作者Windows提交算作本项目误上传。
- 本次纠错写main-anpx的单次授权已执行完毕，今后禁止再次写入。

## 持续保护

根AGENTS.md已记录唯一目标origin/win-zxy-harness及main-anpx禁写规则。旧文档的main-anpx仅为历史事实。

原工作区当前分支已从main-anpx改名codex/win-zxy-work，跟踪origin/win-zxy-harness；不checkout覆盖原源码和历史dirty。此前已有本地win-zxy-harness旧分支保存点保留，不将其旧指针冒充远端最新版本。

本仓库remote.origin.push固定为HEAD:refs/heads/win-zxy-harness。本地.git/hooks/pre-push已安装，只允许该目标ref；stdin模拟检查确认zxy放行、main-anpx/main拒绝，未用实际错误推送测试。此保护是本机Git钩子，不声称修改GitHub服务端分支保护。

远端迁移在隔离工作区完成，原工作区分支保存点没有强制快进以覆盖历史dirty。后续上传继续以最新zxy为基准、按Windows范围同步，不将其他分支作为默认目的地。

第一次zxy上传遇短暂TLS EOF，正常重试成功，未关闭TLS验证。

本轮无产品改动、构建、安装、设备写入或发布；Owner Preview PASS与VERIFY / DELIVERY_PREP事实保持。此结果记录作为zxy上的后续小提交保存。
