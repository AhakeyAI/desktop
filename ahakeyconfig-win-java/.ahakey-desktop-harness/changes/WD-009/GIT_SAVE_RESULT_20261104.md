# WD-009 / 1.0.19 Git 保存结果

Owner 授权及真实反馈：../../evidence/20261104-wd009-r4-owner-pass-git-push.md。

- 产品及证据提交：b9466fb1e0d8fa517d9869de07b92fe2c598d363。
- 精确保存62项：26项已审生产/测试路径，加36项相关Harness记录。
- Harness candidate-check：PASS，candidate.json绑定上述提交、build_round 4、现有审批与审阅。
- 代码指纹：b184b8b7478757a45d39a65e803a677914a1ab8eb2c7d17a24704e6cedc47775。
- 1.0.19 EXE重新计算SHA256与Preview回执一致：a4d4d880fc163d8372573c9b62023b444cdae11b057bccce261a8b831ccaf7e3。
- OWNER_PREVIEW_RESULT已按正式命令登记PASS，并保存到本任务和对应token目录。未覆写旧token的失败证据。
- 暂存范围与review_pack的26项生产/测试路径完全一致；凭据特征扫描未发现私钥/GitHub token/AWS key字面量；没有模型和EXE加入提交。
- 原始diff/补丁格式空白告警已分类记录；其他暂存文件检查通过。未重新构建或改变已测试源码。
- 15项既有未暂存跟踪文件已记录本地hash用于最终比对。历史资料和并列项目不加入本轮提交。

此回执随候选记录追加保存。后续远端同步使用隔离工作区合并origin/main-anpx，再正常push，必须以远端实际hash确认成功，不能以本地提交代替上传成功。

本次Owner已确认预览版本实测通过；任务仍处于VERIFY，正式构建/测试包/逐项覆盖等缺口未通过Git保存自动关闭。本次不是Release发布，也没有恢复其他暂停任务。
