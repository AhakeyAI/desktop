# Speech

## 这个目录是什么

Windows 本地语音输入与转写相关源码目录。

## 当前包含什么

- `Capswriter/`
  - 客户端 / 服务端入口
  - 音频、快捷键、转写、LLM、UI、WebSocket 相关源码
  - `build.spec`

## 当前不包含什么

- 预编译 DLL
- 发布后的完整 `CapsWriter-Offline` 目录
- 本地模型目录
- 安装包与 exe

## 如何构建

根据现有源码可判断的方式：

- `pip install -r requirements.txt`
- `python start_server.py`
- `python start_client.py`
- 打包入口可参考 `build.spec`

注意：当前仓库没有把预编译 DLL 和模型一起导入，因此这里只是源码迁移，不表示已经形成可直接复现的完整发布环境。

## GitHub Releases 对应发布物

未来会以完整的 Windows 语音组件目录或最终安装器中的语音模块形式发布到 GitHub Releases。
