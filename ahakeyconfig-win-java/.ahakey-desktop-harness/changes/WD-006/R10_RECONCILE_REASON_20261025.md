# R10 修订原因与范围判断

Owner 已真实测试官网读取/下载链，并明确要求保留原安装路径、简化升级向导、改善失败恢复，随后直接批准修正和重打1.0.11/1.0.12完整EXE。依据 evidence/20261025-r10-install-upgrade-owner-authorization.md。无新产品取舍需要重复确认。

DLA 已读 WindowsUpdateInstaller、UpdateCenterService、UpdateCenterDialog、windows-update-worker.ps1、package-local-model.ps1及R9嵌入MSI。问题证据：worker安装只传/norestart；MSI RemoveExistingProducts=798、InstallInitialize=1500；相同版本不在旧升级范围；当前用户实际R9 1.0.11注册位置D:\ahakey\。本次是原更新功能缺陷与Owner新明确体验语义的revision，不另起活跃任务、不重置start，不自动验收旧UAT。

生效产品范围由 R10_INSTALL_UPGRADE_SCOPE_20261025.md 定义；R9的K1/HEX/BLE/语音功能保持。本轮直接生产变化限定更新Java/PowerShell、实际打包配方和其必要安装helper、相关测试，既有允许列表保留用于累计来源检查但不授权重写其他行为。新增 update 与 installer 深模块目录仅供此修正，不允许泛化任意命令执行器。

high_impact 独立审阅聊天01a17166-5e92-7180-aac2-9627749994e2已经启动，设计/实际实现发现必须在最终候选交付前闭合。工程资料由唯一DIB准备；DLA批准后DIB仅在合法IMPLEMENT模式开始。真实安装和回滚UAT由Owner执行；无真实反馈不写PASS。可用本机MSI只读接口、结构/纯逻辑测试和隔离包启动，不触发安装、Win32_Product、注册表写或用户进程终止。

保留旧revision8批准、合同、交付和构建记录到contract-revisions/20261025-r8-before-r10；旧R9EXE不覆盖。继承独立Git保存授权、无Windows push，源码候选将另存；最终两包取同一修复源码且版本仍1.0.11与1.0.12，发布固定密钥不轮换。官网部署已实测，本轮不更改官网或环境变量。
