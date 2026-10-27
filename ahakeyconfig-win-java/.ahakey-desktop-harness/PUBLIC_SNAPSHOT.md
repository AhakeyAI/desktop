# Windows 当前代码快照：1.0.12 / R13

更新日期：2026-10-27。目标分支：`AhakeyAI/desktop:win-zxy-harness`。

本次上传的是已交付 R13 本地模型测试包对应的源码与筛选后的 Harness 资料，不是软件正式发布或实机验收通过。轻量版与本地模型版共用软件版本号，按安装形态选择更新包；本次实际构建、核验的是本地模型版。

## 当前实现

- 软件更新：从官网更新接口获取统一版本及对应形态的安装地址，验证发行签名后安装；支持首次全量安装及识别原安装目录的更新。
- 固件烧录：随包 WCH 工具、boot 设备检测、清空 CodeFlash 和 DataFlash、写入后独立校验、正常重连后读取实际版本。未知 HEX 不声称已核对目标版本。
- R13 修复：解析 WCH 实际 JSON 结果及百分比进度，错误和超时优先；失败工具已结束时，关闭入口结束维护链路。主窗口 × 收起到托盘，托盘 Exit 才退出软件。
- 保留此前 BLE/USB 切换修复、CP2.5/CP2.6 Windows K1 普通按键路由适配，以及本地模型版 F18 的“本地语音输入”提示。

## 版本与证据

R13 Preview：`preview-20261026T105435810998Z-dfc116`。

- EXE：`AhaKeyStudio-1.0.12.exe`，296237624 字节。
- EXE SHA256：`21de9ab7c4e5c5b915cbd92c7f0f3d62b003ef90f9df20ceb962b46ae0b36af7`。
- 包内 JAR SHA256：`7ec21ce3538cd5a1eb0efb6749118bba03567197d296933704b7c6ed3a54b340`。
- buildId：`96d9a365a0296b9dcf5e4e5f9782f13cd6cd706ab4ff4884a21c37c5a664a988`。

已完成 206 项针对性源码检查；最终安装包的 313 项载荷、发行签名、现场日志回放及隔离窗口关闭测试通过。实际 R13 安装、硬件独立校验和重连读版本仍待 Owner 反馈。之前的软件 OTA 成功记录不能替代 R13 实机验收。

入口资料：

- [任务约定](changes/WD-006/CONTRACT.md)
- [R13 修复说明](changes/WD-006/r13-dib-20261026/DIB_REPORT.md)
- [R13 代码审阅](changes/WD-006/r13-dla-20261026/DLA_PREVIEW_FIX_REVIEW.json)
- [R13 包检查](changes/WD-006/r13-dla-20261026/DLA_ARTIFACT_REVIEW.json)
- [构建说明](changes/WD-006/BUILD_REPORT_R13_20261026.md)
- [实机测试流程](changes/WD-006/R13_OWNER_TEST_FLOW.md)
- [本次上传清单](PUBLIC_UPLOAD_MANIFEST.json)

## 筛选规则

上传 R13 的 176 项精确构建输入（163 项快照文件及 13 项已核验安装配方）、当前 AGENTS/三项 Harness 技能及脚本、流程模板、Journey Registry、当前任务约定、关键审阅和构建/固件身份记录。保留构建所需的固定 WCH 运行组件、驱动、小型 Sherpa Java API JAR 和内置固件资源；其身份及现有授权证据状态沿用仓内清单，不追加授权声明。

不新增安装包、app-image、编译目录、模型权重、Maven 缓存、签名私钥、本机 `local.json`、原始设备/安装日志、重复源码快照和回滚备份。其他平台及远端已有历史保持原样。

为避免将本地中间记录整批公开，此提交直接以远端原分支为父提交；本地 R4～R12 候选历史保留在原工作区。历史文档中的候选 SHA、绝对路径和被排除的证据引用可能只在原工作区有效。此上传是可追踪的源码与资料快照，不是完整本机 Harness 工作区备份，不应据此自动宣布旧候选、测试或交付门禁通过。

`STATE.json` 保留原流程记录；当前实际可交测状态以 R13 的 `PREVIEW_RECEIPT` 和包审阅为准。不要为消除显示差异改写历史状态或指纹。

## 构建与接续

Java 17、Maven、WiX 和 DTF 的参数及校验以 `scripts/package-local-model.ps1`、`scripts/installer/dtf-toolchain.json` 为准。构建时显式传入 `-AppVersion 1.0.12`；源码默认资源版本和 Maven 工程版本不等同于最终安装包版本。

完整本地模型包还需要脚本所固定的模型权重、Sherpa 原生 JAR、BLE 驱动及其构建清单、许可证文件和本地 Maven 依赖缓存。模型输入身份见 `changes/WD-006/MODEL_INPUTS_20261023.json`；BLE 构建脚本和补丁随源码保留。安装包和这些较大外部依赖不作为此次 Git 上传产物。

发行验证公钥属于客户端源码，可以公开。生产发行私钥留在受控签名环境；新机器不能通过生成新密钥冒充原发行者。普通源码编译不需要生产私钥，制作能被现有客户端接受的正式升级包需要原签名环境。

新环境先按 `local.example.json` 配置真实只读参考路径；缺少原本机证据时明确标记缺失，再按 Harness 接续，不能伪造通过。此次上传未安装软件、启动应用、烧录设备或改动 Firmware/eternal 仓库。
