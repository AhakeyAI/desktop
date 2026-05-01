# Releases

## 这个目录是什么

发布相关约定与入口说明目录。
这个目录本身不是二进制产物的存放位置。

## 当前包含什么

- 当前仅保留 `README.md` 作为入口说明
- 更完整的发布约定请查看 [`docs/releases.md`](../docs/releases.md)

## 当前不包含什么

- `exe`
- `msi`
- `dmg`
- `zip`
- 打包缓存或本地组装目录
- 任何安装包二进制
- 私钥、签名文件、token 或其他 secrets

## 如何构建

当前目录不提供独立构建入口。
平台源码、脚本和构建细节应分别查看对应平台子目录与文档。

## GitHub Releases 对应发布物

真正的安装包与发布二进制应上传到 GitHub Releases，
而不是提交到仓库中的 `releases/` 目录。
