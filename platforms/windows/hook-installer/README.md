# Hook Installer

## 这个目录是什么

Windows 侧 Claude / Cursor hook 安装、分发与 BLE 状态桥接相关源码目录。

## 当前包含什么

- `vibe_code_hook/`
  - `hook_install.py`
  - Claude / Cursor 事件脚本
  - `install_hook.py`
  - `install_cursor_hook.py`
  - `hook_install.spec`

## 当前不包含什么

- `hook/build/` 构建残留
- `hook/dist/` 发布产物
- `config_client.json` 本地配置
- 打包后的 `hook_install.exe`

## 如何构建

根据现有源码可判断的方式：

- 直接运行 `python hook_install.py`
- 或用 `python install_hook.py` / `python install_cursor_hook.py`
- 若需要打包，可参考 `hook_install.spec`

## GitHub Releases 对应发布物

未来会以 `hook_install.exe` 或最终 Windows 安装器中的 hook 安装组件形式发布到 GitHub Releases。
