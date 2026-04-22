# Releases

## 发布原则

- 安装包通过 GitHub Releases 分发。
- 源码通过 Git 仓库分发。
- 仓库中不保存 `exe`、`msi`、`dmg`、`zip` 安装包或打包目录。

## 当前预期的 Windows 发布物

- 主客户端打包产物
- BLE bridge 可执行文件
- hook installer 可执行文件
- 本地语音组件打包目录或对应安装器内容
- 最终 Windows 安装器

以上名称和装配方式仍需后续整理确认，但发布位置原则不变：只上 GitHub Releases，不进源码仓库。

## 当前明确不进入仓库的内容

- 发布二进制
- 打包缓存
- 本地组装目录
- 本地模型和运行时 DLL
- 本地配置
- 私钥、签名文件、token、secrets
