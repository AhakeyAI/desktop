# WD-009 R4 Git 保存审查

Owner 于 2026-11-04 确认 1.0.19 实测通过并授权 Git 保存、上传。反馈绑定 preview-20261103T072949372746Z-2afea7；EXE 重新计算 SHA256 与原回执一致。

Harness guard-status 核对不可变起点、实现提交和实际 DLA 审阅通过；本轮复用与当前代码指纹一致的既有实际/独立审阅，不宣称重新执行审阅或机器回归。

candidate-plan 生成精确40项清单，其中26项生产/测试改动与当前 review_pack.changed_paths 一致，其余为合同、批准、起点及审阅证据。补充保存本轮 change/verification、Preview身份及结果、构建/包内检查报告和本次授权。没有暂存并列 BLE 源码、本机 config_server.json、历史回滚备份、旧任务或 Harness 脚本修改；不提交模型、EXE或target目录。

## 原始空白检查结果

生成计划的暂存操作已执行，其末尾 git diff --cached --check 返回2：486处仅在冻结 ACTUAL_DIFF.txt 中，3处仅在 ble-driver-fixes.patch 的统一diff空上下文行（单个空格）。前者是已绑定hash的历史代码差异，后者是补丁格式，不改其原字节以迎合格式检查。对其余全部暂存文件执行同一检查返回0。没有更改Harness校验代码、保护印章或Git配置；原始失败输出保留 target/wd009-git-save-20261104/staged-check-initial.txt。

## 远端同步

既有远端 origin=https://github.com/AhakeyAI/desktop.git，当前分支 main-anpx。fetch发现本地19个、远端44个分叉提交；远端差异仅macOS及其修复工作流。后续使用隔离工作区合并并核对Windows树不变，正常推送，不强推、不改写已有历史、不在当前工作区覆盖外来修改。

## 状态边界

本次保存的是Owner实测通过的精确Preview版本及其源码。正式candidate形成后另存回执；正式构建/测试包等尚未齐备，不伪造正式UAT或Release关闭。本次用户没有要求重建、重复测试或安装。
