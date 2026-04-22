# Desktop Main

## 这个目录是什么

Windows 主桌面客户端源码目录。

## 当前包含什么

- `vibe_code_config_tool/`
  - PySide6 主程序源码
  - UI、设备状态、TCP 通信、云端接口封装
  - 打包说明与 PyInstaller spec 文件

## 当前不包含什么

- hook installer 源码
- BLE bridge 源码
- 云端后端
- 安装包和发布 exe

## 如何构建

根据现有源码可判断的入口：

- `pip install -r requirements.txt`
- `python main.py`
- 打包入口优先看 `KeyboardConfig_onedir.spec`

## GitHub Releases 对应发布物

未来会以 Windows 主客户端打包产物或最终安装器中的主程序形式出现在 GitHub Releases。
