# Windows Scripts

## 这个目录是什么

Windows 平台专属构建 / 打包脚本目录。

## 当前包含什么

- `inno-setup/`
  - `VibecodingKeyboard_Setup.iss`
  - `ChineseSimplified.isl`

## 当前不包含什么

- `all_in_one` 之类的本地装配目录
- 安装包二进制
- 已确认可直接复用的正式发布流水线

## 如何构建

当前目录中的 Inno Setup 文件按“历史打包脚本 / 待整理”保留。

- 它们反映了过去的本机构建方式
- 但其中仍包含本机路径与历史约束
- 目前不能宣称已经可直接复用

## GitHub Releases 对应发布物

未来若保留 Inno Setup 方案，最终 Windows 安装器会发布到 GitHub Releases；但这些脚本本身只作为源码与历史资料保存在仓库中。
