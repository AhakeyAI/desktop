# BLE Bridge

## 这个目录是什么

Windows 侧 BLE 与 TCP 之间的桥接程序源码目录。

## 当前包含什么

- `BLE_tcp_bridge_for_vibe_code/`
  - `.sln` / `.csproj`
  - WinForms 界面
  - BLE 通信与 TCP server 实现
  - 协议定义与配置文件

## 当前不包含什么

- 预编译 `BLE_tcp_driver.exe`
- 安装包
- 云端服务

## 如何构建

根据现有源码可判断的方式：

- 使用 Visual Studio 打开 `BLE_tcp_driver.sln`
- 或基于 `BLE_tcp_driver.csproj` 在 .NET Framework 4.7.2 环境下构建

## GitHub Releases 对应发布物

未来会以 `BLE_tcp_driver.exe` 或最终安装器中的 BLE bridge 组件形式发布到 GitHub Releases。
