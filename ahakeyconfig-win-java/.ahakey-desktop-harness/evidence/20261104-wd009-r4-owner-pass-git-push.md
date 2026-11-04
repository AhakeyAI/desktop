# WD-009 R4 / 1.0.19 Owner 实测通过与 Git 保存上传授权

日期：2026-11-04（Asia/Shanghai）。来源：当前 Owner 对话。

Owner 原话：
> 1.0.19已经实测通过了，可以安排harness去git保存， 同时git上传下了

## 对应版本

- 任务：WD-009，build_round 4。
- Preview token：preview-20261103T072949372746Z-2afea7。
- 安装包：target/WD009-Preview-R4-LocalModel-1.0.19/installer/AhaKeyStudio-1.0.19.exe。
- 安装包 SHA256：a4d4d880fc163d8372573c9b62023b444cdae11b057bccce261a8b831ccaf7e3。
- 工作代码指纹：b184b8b7478757a45d39a65e803a677914a1ab8eb2c7d17a24704e6cedc47775。

## 反馈与授权边界

记录 Owner 对此精确版本的整体实测通过反馈，不编造逐项操作、设备型号或已刷固件身份。按现有 Harness 将其登记为该版本 Owner Preview PASS；正式 UAT/Release 的独立证据缺口不通过此记录自动消除。

Owner 已明确授权本轮 Git 保存与上传。允许审核精确文件清单后提交 WD-009 代码、测试与相关 Harness 记录，核对候选并推送当前分支到既有 origin。无需重复请求提交/推送许可。

延续既有 WD-009 隔离要求，保留历史外来修改、运行配置、并列项目与回滚备份，不混入本轮候选；既有 Git 历史随正常分支推送保留。大模型与安装 EXE 不加入源码提交。此授权不包含重新构建、安装、设备写入、烧录、发布 Release 或恢复已暂停任务。
