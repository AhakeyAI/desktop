# R10：原目录升级、简化安装 UI、可验证失败恢复

Owner 授权见 evidence/20261025-r10-install-upgrade-owner-authorization.md。本轮是 WD-006 软件更新用户旅程 J008 的修订，关联 J007 模型版配置保持；bug_fix + architecture_change，沿用 high_impact 独立审阅。不重置原任务起点，不把此前完整固件验收改为可选；本次先交软件修正版。

## 产品语义与工程约束

1. 首次安装保留目录选择。已安装升级自动沿用真实已安装目录（含 D 盘、自定义名称、中文、空格），不擅自回到默认路径。读取 MSI 已安装身份/范围/位置并核对实际当前 launcher，歧义、目录不匹配或不可证实时保持原应用可用并明确失败，不能选择第一个结果或执行任意配置路径。
2. 应用内 OTA 仍需用户明确点击退出更新；只显示安装进度和必要 UAC，不重复首次安装向导。下载验签、实际 MSI/形态/版本身份、冻结包锁、worker ready/exit-permit/父进程身份、设备维护排他和真实安装结果确认仍保留。不能以 quiet/passive 掩盖安装失败。
3. 通过 Windows Installer 管理升级与注册信息，调整移除旧版动作进入可回滚的事务范围，不能由脚本预卸载或递归删除安装目录。记录实际退出码与结果；只有实际目标版本/形态/安装路径匹配才说升级完成。普通失败、拒绝UAC、程序占用、需要系统重启分清；不承诺断电等任意故障必然恢复。
4. 手动执行更新 EXE 也应继承现有目录；不能仅在应用内传目录。相同版本旧 R9 1.0.11→新 R10 1.0.11 起点必须能够替换实际内容、不创建两个安装项、不要求用户先卸载。严格阻止软件降级；同版本仅手动 bootstrap/重装适用，不改变云端版本比较逻辑。升级前后配置、绑定和模型形态保留。
5. 本轮两包均完整 local-model，版本1.0.11/1.0.12，同既有 UpgradeCode、固定签名公钥；每包新实际 ProductCode/构建身份。输出隔离目录标识 R10，旧 R9 EXE 及报告全部保留；严禁旧新同名包互相覆盖或上传错包。
6. 不变：固定官网 schema3 单版本双地址、签名封装/密钥、BLE/USB、K1/固件协议、HEX烧录、语音、官网代码。若必要新增实现文件，需在正式 allowed_paths 内或先交 DLA；不调整 Harness Core。

## 实现边界

现有 WindowsUpdateInstaller、UpdateCenterService、UpdateCenterDialog、windows-update-worker.ps1、package-local-model.ps1、verify-update-package.ps1及对应 update/packaging 离线测试。可新增深模块处理已安装实例解析/MSI模板补丁及其针对性测试，具体文件名在工程方案后绑定。

## 验证和交付

必须检查实际生成 EXE 的嵌入 MSI 表，而不仅检查打包脚本文本：升级范围含同版、准确原目录解析/早期查询、手动/OTA同一路径、RemoveExistingProducts 在 InstallInitialize 后且合法事务顺序、相同 UpgradeCode/不同 ProductCode、配置不删除。行为测试覆盖无安装/唯一/多实例/错路径、空格中文路径引号、篡改/错包/拒绝权限/失败退出/旧receipt等。实际装机和注册写入只能 Owner 执行；静态顺序检查不能写成实测rollback PASS。

构建完整EXE后实际验签、包内payload、GUI、模型WAV，以及1.0.11使用最终1.0.12的真实离线下载校验链。精确Git候选与阶段收据。Owner方案：保留配置→关闭旧软件后手装R10同版起点→确认仍原目录且新版构建已生效→云端1.0.11同版不更新→上传R10 1.0.12并改公共版本及对应URL→退出更新仅进度/UAC→原路径启动新版/配置保持/单一安装项→最新版。失败恢复按真实可执行结果说明，不自动安装或回滚用户系统。
