# Releases

## 发布原则

- 安装包和固件同时上传 GitHub Releases，供维护者留档。
- 中国大陆用户通过现有 CloudBase 对象存储下载，不直接依赖 GitHub。
- `https://ahakey.com/stable.json` 是客户端唯一稳定版更新入口。
- 源码通过 Git 仓库分发。
- 仓库中不保存 `exe`、`msi`、`dmg`、`zip` 安装包或打包目录。

## 当前预期的 Windows 发布物

- 主客户端打包产物
- BLE bridge 可执行文件
- hook installer 可执行文件
- 本地语音组件打包目录或对应安装器内容
- 最终 Windows 安装器

当前稳定版命名：

- `AhaKeyStudio-1.2.0-windows-x64.exe`
- `AhaKey-X1-firmware-1.1.1-ch582.hex`

客户端与固件独立版本管理。发布工作流先上传不可变资产，最后更新
`releases/stable.json`，避免客户端读取到尚未上传完成的文件。

## 当前明确不进入仓库的内容

- 发布二进制
- 打包缓存
- 本地组装目录
- 本地模型和运行时 DLL
- 本地配置
- 私钥、签名文件、token、secrets
