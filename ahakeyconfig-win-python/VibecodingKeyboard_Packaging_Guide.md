# Vibecoding Keyboard 打包手册

本文档用于后续 AI 或工程人员在当前工作区内重复构建 `VibecodingKeyboard_Setup.exe`。  
目标不是解释项目背景，而是给出一份可直接执行、尽量少踩坑的操作说明。

最后一次按本文档验证成功的日期：`2026-04-10`  
最后一次成功产物：
- 安装包：`C:\Users\20825\Desktop\windows软件打包\VibecodingKeyboard_Setup.exe`
- SHA-256：`A7F9F9D152E03113CB2F1FA2451523062CAEBF33259BB5A156A0B53D0F0EF423`

---

## 1. 目标产物

完整 Windows 安装包应包含以下本地组件：

- `KeyboardConfig.exe`
- `KeyboardConfig` 对应的 `_internal` 目录
- `BLE_tcp_driver.exe`
- `hook_install.exe`
- `config_client.json`
- `Capswriter` 整个目录
- `VC_redist.x64.exe`

最终这些文件先汇总到：

- `C:\Users\20825\Desktop\windows软件打包\all_in_one`

然后由 Inno Setup 脚本：

- `C:\Users\20825\Desktop\windows软件打包\VibecodingKeyboard_Setup.iss`

打成最终安装包：

- `C:\Users\20825\Desktop\windows软件打包\VibecodingKeyboard_Setup.exe`

---

## 2. 当前工作区中哪些是可用的

### 2.1 必须使用的目录

#### 2.1.1 配置工具源码

可用目录：

- `C:\Users\20825\Desktop\windows软件打包\vibe_code_config_tool-master\vibe_code_config_tool-master`

说明：

- 这是 `KeyboardConfig.exe` 的真实源码根目录。
- 注意是“双层目录”里的内层目录，不是外层包装目录。
- 当前验证可用的 PyInstaller 规格文件是：
  - `KeyboardConfig_onedir.spec`
- 当前版本号文件是：
  - `src\core\app_version.py`

#### 2.1.2 Hook 安装器源码

可用目录：

- `C:\Users\20825\Desktop\windows软件打包\vibe_code_config_tool-master\vibe_code_config_tool-master\hook`

说明：

- 必须从这里构建 `hook_install.exe`。
- 当前验证可用的规格文件是：
  - `hook_install.spec`
- `hook_install.exe` 是无外部 Python 依赖的可执行文件。

#### 2.1.3 本地语音输入源码

可用目录：

- `C:\Users\20825\Desktop\windows软件打包\Capswriter-master\Capswriter-master`

说明：

- 也是双层目录，必须使用内层目录。
- 当前验证可用的规格文件是：
  - `build.spec`
- 不能只拿 `start_client.exe` 和 `start_server.exe` 两个文件；必须带上整个 `CapsWriter-Offline` 目录。

#### 2.1.4 蓝牙桥接器源码

源码目录：

- `C:\Users\20825\Desktop\windows软件打包\BLE_tcp_bridge_for_vibe_code-master (1)\BLE_tcp_bridge_for_vibe_code-master`

说明：

- 当前打包流程里，实际直接使用的是 `all_in_one` 中已经存在的 `BLE_tcp_driver.exe`。
- 该项目源码用于定位依赖和必要性，不是本次主打包流程里最稳定的重建入口。
- 该程序依赖 `.NET Framework 4.7.2`，见：
  - `App.config`

#### 2.1.5 云端后端源码

可用目录：

- `C:\Users\20825\Desktop\windows软件打包\wxcloudrun-flask-main\wxcloudrun-flask-main`

说明：

- 这是微信云托管后端。
- 它不应打进桌面安装包。
- 但它必须部署在线上，否则登录、付费、Typeless 文本优化、检查更新都不完整。

#### 2.1.6 安装器暂存目录

可用目录：

- `C:\Users\20825\Desktop\windows软件打包\all_in_one`

说明：

- 这是当前安装器的唯一装配目录。
- `VibecodingKeyboard_Setup.iss` 使用通配符整目录打包：
  - `Source: "{#SourceRoot}\*"; ... recursesubdirs createallsubdirs`
- 这意味着：`all_in_one` 里有什么，安装器就会带什么。
- 这里必须保持干净，不要放无关文件。

### 2.2 当前验证可用的虚拟环境

#### 2.2.1 配置工具 / Hook 安装器

可用环境：

- `C:\Users\20825\Desktop\windows软件打包\.venv_qt68`

已验证版本：

- Python `3.11.9`
- PyInstaller `6.19.0`
- PySide6 `6.8.2`

用途：

- 构建 `KeyboardConfig` 的 onedir 版本
- 构建 `hook_install.exe`

#### 2.2.2 Capswriter

可用环境：

- `C:\Users\20825\Desktop\windows软件打包\.venv_clean311`

已验证版本：

- Python `3.11.9`
- PyInstaller `6.19.0`
- sherpa-onnx `1.12.36`
- websockets `16.0`
- pynput `1.8.1`
- keyboard `0.13.5`

用途：

- 构建 `CapsWriter-Offline`

### 2.3 当前不建议使用的环境或目录

#### 2.3.1 `.venv_build`

目录：

- `C:\Users\20825\Desktop\windows软件打包\.venv_build`

不建议作为完整打包环境的原因：

- 当前只有 `PySide6 6.11.0`
- 没有 `sherpa-onnx`
- 不适合完整复现本地语音输入打包链

#### 2.3.2 Anaconda 或其他污染环境

不要用的原因：

- 之前曾用到污染环境打 `KeyboardConfig.exe`，结果运行时报错：
  - `ImportError: DLL load failed while importing QtWidgets`
- 这个坑已经踩过，不要再用系统 Python / Anaconda 直接打 PySide6 桌面程序。

#### 2.3.3 `Vibe_admin-main`

目录：

- `C:\Users\20825\Desktop\windows软件打包\Vibe_admin-main`

说明：

- 这是后台管理端，不属于用户安装包。
- 不应打进 `VibecodingKeyboard_Setup.exe`。

#### 2.3.4 `typeless_upload`

目录：

- `C:\Users\20825\Desktop\windows软件打包\typeless_upload`

说明：

- 这是上传到 GitHub 的镜像仓库，不是构建源目录。
- 不用于打包。

#### 2.3.5 各类 zip 文件

例如：

- `Capswriter-master.zip`
- `wxcloudrun-flask-main.zip`
- `Vibe_admin-main.zip`
- `BLE_tcp_bridge_for_vibe_code-master (1).zip`

说明：

- 这些只是压缩包备份，不参与当前构建流程。

#### 2.3.6 固件文件

例如：

- `HID_Keyboard_582m_vibe_coding.hex`

说明：

- 当前安装流程不包含固件刷写。
- 没有配套刷写器时，不要把它当成安装包必需项。

---

## 3. 当前已经验证有效的关键配置

### 3.1 配置工具版本号

文件：

- `C:\Users\20825\Desktop\windows软件打包\vibe_code_config_tool-master\vibe_code_config_tool-master\src\core\app_version.py`

当前值：

- `APP_VERSION = "1.0.3"`

要求：

- 发布新版本时必须和安装器版本一起改。

### 3.2 安装器版本号

文件：

- `C:\Users\20825\Desktop\windows软件打包\VibecodingKeyboard_Setup.iss`

当前值：

- `#define AppVersion "1.0.3"`

要求：

- 必须与 `app_version.py` 保持一致。

### 3.3 默认云端地址

文件：

- `C:\Users\20825\Desktop\windows软件打包\vibe_code_config_tool-master\vibe_code_config_tool-master\src\core\cloud_settings.py`

当前默认值：

- `DEFAULT_API_BASE = "https://typeless-220629-6-1398334410.sh.run.tcloudbase.com"`

说明：

- 如果云托管域名变了，这里要改。
- 旧地址兼容列表 `LEGACY_API_BASES` 也要同步维护。
- 用户本机若已经缓存过旧地址，仅改源码不一定立即生效；缓存存放于 `QSettings` / 注册表。

### 3.4 Capswriter 访问 Typeless 的默认地址

文件：

- `C:\Users\20825\Desktop\windows软件打包\Capswriter-master\Capswriter-master\text_optimizer.py`

当前内置默认值：

- `_FALLBACK_TYPELESS_API_BASE = "https://typeless-220629-6-1398334410.sh.run.tcloudbase.com"`

说明：

- 如果云域名变了，这里也要改。
- 桌面配置工具和 Capswriter 的云端地址必须一致。

### 3.5 云端更新检查接口

接口实现文件：

- `C:\Users\20825\Desktop\windows软件打包\wxcloudrun-flask-main\wxcloudrun-flask-main\wxcloudrun\api\v1\client_routes.py`

路由聚合文件：

- `C:\Users\20825\Desktop\windows软件打包\wxcloudrun-flask-main\wxcloudrun-flask-main\wxcloudrun\api\v1\routes.py`

环境变量读取文件：

- `C:\Users\20825\Desktop\windows软件打包\wxcloudrun-flask-main\wxcloudrun-flask-main\config.py`

当前接口：

- `GET /api/v1/client/config-tool/release`

依赖环境变量：

- `CONFIG_TOOL_LATEST_VERSION`
- `CONFIG_TOOL_DOWNLOAD_URL`
- `CONFIG_TOOL_RELEASE_NOTES`

---

## 4. 这套产品真正需要打包的内容

### 4.1 需要打包进 Windows 安装包的

- `KeyboardConfig.exe`
- `KeyboardConfig` 的 `_internal`
- `BLE_tcp_driver.exe`
- `hook_install.exe`
- `config_client.json`
- `Capswriter` 整目录
- `VC_redist.x64.exe`

### 4.2 不需要打包进 Windows 安装包的

- `wxcloudrun-flask-main`
- `Vibe_admin-main`
- 各种 zip 备份包
- `typeless_upload`
- Python 虚拟环境目录
- 构建缓存目录 `build` / `dist` / `__pycache__`
- 固件 `.hex` 文件

### 4.3 当前可删但即使带上也不会影响运行的文件

文件：

- `C:\Users\20825\Desktop\windows软件打包\all_in_one\install_hook.py`

说明：

- 当前用户安装流程实际使用的是 `hook_install.exe`。
- `install_hook.py` 是旧的 Python 脚本版安装器。
- 因为安装器脚本对 `all_in_one` 使用了整目录通配符，所以它会被顺带打进去。
- 它不是必需文件，后续若要精简可移除。

---

## 5. 构建顺序

必须按下面顺序执行：

1. 构建 `KeyboardConfig` 的 onedir 版本
2. 构建 `hook_install.exe`
3. 构建 `CapsWriter-Offline`
4. 整理 `all_in_one`
5. 编译 Inno Setup 安装包
6. 上传新安装包到 COS 或其他 HTTPS 下载源
7. 更新微信云托管环境变量

---

## 6. 详细构建步骤

以下命令全部在 PowerShell 中执行。

### 6.1 构建 KeyboardConfig

进入源码目录：

```powershell
Set-Location 'C:\Users\20825\Desktop\windows软件打包\vibe_code_config_tool-master\vibe_code_config_tool-master'
```

建议先清理旧产物：

```powershell
Remove-Item -Recurse -Force .\build -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force .\dist\KeyboardConfig -ErrorAction SilentlyContinue
```

注意：

- 不要依赖 `dist\KeyboardConfig.exe` 这个单文件旧产物。
- 当前验证稳定可用的是 `KeyboardConfig_onedir.spec` 生成的目录版产物。

执行构建：

```powershell
& 'C:\Users\20825\Desktop\windows软件打包\.venv_qt68\Scripts\python.exe' -m PyInstaller --noconfirm .\KeyboardConfig_onedir.spec
```

成功后可用产物是：

- `dist\KeyboardConfig\KeyboardConfig.exe`
- `dist\KeyboardConfig\_internal\...`

不要拿这个旧单文件当最终产物：

- `dist\KeyboardConfig.exe`

原因：

- 之前单文件版本曾触发 `QtWidgets` DLL 加载失败。
- 当前工作区中 `all_in_one\KeyboardConfig.exe` 已明确来自 `dist\KeyboardConfig\KeyboardConfig.exe`，不是来自 `dist\KeyboardConfig.exe`。

### 6.2 构建 hook_install.exe

进入 Hook 目录：

```powershell
Set-Location 'C:\Users\20825\Desktop\windows软件打包\vibe_code_config_tool-master\vibe_code_config_tool-master\hook'
```

建议先清理旧产物：

```powershell
Remove-Item -Recurse -Force .\build -ErrorAction SilentlyContinue
Remove-Item -Force .\dist\hook_install.exe -ErrorAction SilentlyContinue
```

执行构建：

```powershell
& 'C:\Users\20825\Desktop\windows软件打包\.venv_qt68\Scripts\python.exe' -m PyInstaller --noconfirm .\hook_install.spec
```

成功后产物：

- `dist\hook_install.exe`

补充说明：

- `hook_install.exe` 的源码入口是 `launcher.py`，它内部调用 `hook_install.main()`。
- 当前安装流程用的是这个 exe，不再要求用户机器必须安装 Python。

### 6.3 构建 CapsWriter-Offline

进入目录：

```powershell
Set-Location 'C:\Users\20825\Desktop\windows软件打包\Capswriter-master\Capswriter-master'
```

建议先清理旧产物：

```powershell
Remove-Item -Recurse -Force .\build -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force .\dist\CapsWriter-Offline -ErrorAction SilentlyContinue
```

执行构建：

```powershell
& 'C:\Users\20825\Desktop\windows软件打包\.venv_clean311\Scripts\python.exe' -m PyInstaller --noconfirm .\build.spec
```

成功后产物目录：

- `dist\CapsWriter-Offline`

必须确认这个目录里不仅有 exe，还要有：

- `models`
- `assets`
- `util`
- `LLM`
- `log`

原因：

- `build.spec` 已经明确把这些目录复制进发布目录。
- 缺任何一个，语音功能都可能起不来或起不完整。

### 6.4 整理 all_in_one

回到工作区根目录：

```powershell
Set-Location 'C:\Users\20825\Desktop\windows软件打包'
```

先确认 `all_in_one` 中已有以下外部文件：

- `BLE_tcp_driver.exe`
- `VC_redist.x64.exe`

然后用下面的方式覆盖装配目录：

```powershell
Copy-Item '.\vibe_code_config_tool-master\vibe_code_config_tool-master\dist\KeyboardConfig\KeyboardConfig.exe' '.\all_in_one\KeyboardConfig.exe' -Force

Remove-Item -Recurse -Force '.\all_in_one\_internal' -ErrorAction SilentlyContinue
Copy-Item '.\vibe_code_config_tool-master\vibe_code_config_tool-master\dist\KeyboardConfig\_internal' '.\all_in_one\_internal' -Recurse -Force

Copy-Item '.\vibe_code_config_tool-master\vibe_code_config_tool-master\hook\dist\hook_install.exe' '.\all_in_one\hook_install.exe' -Force
Copy-Item '.\vibe_code_config_tool-master\vibe_code_config_tool-master\hook\config_client.json' '.\all_in_one\config_client.json' -Force

Remove-Item -Recurse -Force '.\all_in_one\Capswriter' -ErrorAction SilentlyContinue
Copy-Item '.\Capswriter-master\Capswriter-master\dist\CapsWriter-Offline' '.\all_in_one\Capswriter' -Recurse -Force
```

重要：

- `CapsWriter-Offline` 在安装包里最终目录名应为 `Capswriter`。
- 这是为了匹配配置工具对语音目录的搜索逻辑。
- 代码会检查例如：
  - `CapsWriter\dist\CapsWriter-Offline`
  - `Capswriter\dist\CapsWriter-Offline`
  - `CapsWriter`
  - `Capswriter`
  - `CapsWriter-Offline`

所以当前最稳的安装目录命名就是：

- `all_in_one\Capswriter`

### 6.5 编译安装包

在根目录执行：

```powershell
Set-Location 'C:\Users\20825\Desktop\windows软件打包'
& 'C:\Users\20825\AppData\Local\Programs\Inno Setup 6\ISCC.exe' '.\VibecodingKeyboard_Setup.iss'
```

成功后产物：

- `C:\Users\20825\Desktop\windows软件打包\VibecodingKeyboard_Setup.exe`

### 6.6 安装器语言文件说明

当前脚本使用：

- `ShowLanguageDialog=yes`
- `UsePreviousLanguage=no`

并启用了：

- `english`
- `chinesesimplified`

注意：

- 这台机器安装的 Inno Setup 缺简体中文语言包。
- 所以必须保留这个文件在安装脚本旁边：
  - `C:\Users\20825\Desktop\windows软件打包\ChineseSimplified.isl`
- 如果删掉它，安装器会重新编译失败。

---

## 7. 当前安装器已经实现的行为

文件：

- `C:\Users\20825\Desktop\windows软件打包\VibecodingKeyboard_Setup.iss`

当前行为如下：

- 安装开始时先让用户选择安装界面语言：
  - `English`
  - `简体中文`
- 不记忆上次语言
- 桌面快捷方式默认勾选
- `VC_redist` 默认勾选
- 安装完成后默认勾选：
  - 打开 Hook 安装器
  - 启动键盘配置工具
  - 启动蓝牙桥接驱动

---

## 8. 云端发布联动

桌面安装包构建完成后，若要让“检查更新”功能正常工作，还必须完成下面步骤。

### 8.1 上传安装包到 HTTPS 下载源

当前实际可行方案：

- 微信云托管对象存储 / 腾讯云 COS

要求：

- `CONFIG_TOOL_DOWNLOAD_URL` 必须是浏览器可直接下载的 HTTPS 地址
- 不能填 `cloud://...` 这种 File ID

补充：

- 带 `sign=...` 和 `t=...` 的签名链接可以临时使用，但会过期
- 如果要长期稳定更新，最好使用长期公网可读地址

### 8.2 云托管环境变量

微信云托管里必须有这些变量：

```json
{
  "CONFIG_TOOL_LATEST_VERSION": "1.0.3",
  "CONFIG_TOOL_DOWNLOAD_URL": "https://你的公网下载地址/VibecodingKeyboard_Setup.exe",
  "CONFIG_TOOL_RELEASE_NOTES": "1. 修复云端地址\n2. 优化更新检查"
}
```

支付回调地址也要确保是新域名：

- `WECHAT_PAY_NOTIFY_URL`

### 8.3 每次发布时必须同步的地方

#### 桌面端

- `src\core\app_version.py`
- `VibecodingKeyboard_Setup.iss` 里的 `AppVersion`

#### 云端

- `CONFIG_TOOL_LATEST_VERSION`
- `CONFIG_TOOL_DOWNLOAD_URL`
- `CONFIG_TOOL_RELEASE_NOTES`

#### 如果域名有变化

- `cloud_settings.py`
- `text_optimizer.py`
- 微信支付回调环境变量

---

## 9. 这套系统已经踩过的坑

### 9.1 不要再用单文件 KeyboardConfig 作为最终发布版

症状：

- 启动时报错：
  - `ImportError: DLL load failed while importing QtWidgets`

原因：

- 之前打包链路混用了不稳定环境和单文件分发。

正确做法：

- 只使用 `KeyboardConfig_onedir.spec`
- 最终取 `dist\KeyboardConfig\KeyboardConfig.exe`
- 连同 `dist\KeyboardConfig\_internal` 一起复制

### 9.2 不要用污染环境直接打 PySide6

症状：

- `QtWidgets` DLL 缺失

正确做法：

- 统一使用 `.venv_qt68`

### 9.3 Capswriter 不能只带两个 exe

错误做法：

- 只复制 `start_client.exe` 和 `start_server.exe`

结果：

- 模型、资源、工具依赖缺失
- 语音功能不可用或不完整

正确做法：

- 复制整个 `dist\CapsWriter-Offline` 目录

### 9.4 配置工具和 Capswriter 的云端地址必须一致

如果只改了其中一边，会出现：

- 配置工具登录走新域名
- Capswriter 文本优化还打到旧域名

正确做法：

- 同时改：
  - `cloud_settings.py`
  - `text_optimizer.py`

### 9.5 用户机器缓存了旧 API 地址

说明：

- `cloud_settings.py` 默认地址不是唯一数据源
- 用户本机可能在注册表中缓存过旧地址

位置：

- `HKCU\Software\VibeKeyboard\VibeCodeConfigTool\cloud\api_base`

如果要强制回到源码默认地址：

- 删除该注册表项
- 或调用 `clear_stored_api_base()`

### 9.6 Inno Setup 本机不自带简体中文语言包

症状：

- 编译时报找不到 `ChineseSimplified.isl`

正确做法：

- 把 `ChineseSimplified.isl` 放在 `VibecodingKeyboard_Setup.iss` 同目录

### 9.7 `all_in_one` 是整目录打包，脏文件会一起进安装包

说明：

- 安装器脚本当前没有做白名单枚举
- 而是直接递归复制 `all_in_one\*`

后果：

- 任何无关文件都会被打进安装包

正确做法：

- 打包前人工或脚本检查 `all_in_one`

### 9.8 语音输入可能被虚拟麦克风抢走

当前已修复逻辑：

- `Capswriter-master\Capswriter-master\util\client\audio\stream.py`

当前行为：

- 会主动规避类似 `ToDesk` 这类虚拟输入设备
- 若默认输入看起来像虚拟设备，会自动切换到更合理的麦克风

但仍建议：

- 用户测试前把 Windows 默认录音设备切到真实麦克风

### 9.9 BLE 驱动更新时如果程序正在运行，安装器会提示关闭

这不是打包错误。

原因：

- `BLE_tcp_driver.exe` 正在运行，占用了旧文件

正确处理：

- 允许安装器自动关闭
- 或手动退出旧进程后再安装

---

## 10. 当前已经修过的关键逻辑

### 10.1 语音启动逻辑

文件：

- `C:\Users\20825\Desktop\windows软件打包\vibe_code_config_tool-master\vibe_code_config_tool-master\src\ui\main_window.py`

说明：

- 之前冻结后如果走 `sys.executable start_client.py`，会把配置工具自己再拉起一次。
- 当前已修成优先运行 `start_server.exe` / `start_client.exe`。

### 10.2 语音目录搜索

文件：

- `C:\Users\20825\Desktop\windows软件打包\vibe_code_config_tool-master\vibe_code_config_tool-master\src\ui\main_window.py`

说明：

- 当前会识别 `Capswriter` / `CapsWriter` / `CapsWriter-Offline` 等目录。
- 但实操上仍建议统一只用：
  - `Capswriter`

### 10.3 Capswriter 的模型路径检查

文件：

- `C:\Users\20825\Desktop\windows软件打包\Capswriter-master\Capswriter-master\config_server.py`
- `C:\Users\20825\Desktop\windows软件打包\Capswriter-master\Capswriter-master\util\server\server_check_model.py`

说明：

- 之前冻结运行时模型根目录处理不稳。
- 当前已按冻结目录结构修过。

### 10.4 Hook 安装器

文件：

- `C:\Users\20825\Desktop\windows软件打包\vibe_code_config_tool-master\vibe_code_config_tool-master\hook\launcher.py`
- `C:\Users\20825\Desktop\windows软件打包\vibe_code_config_tool-master\vibe_code_config_tool-master\hook\hook_install.spec`

说明：

- 当前使用 exe 版 Hook 安装器
- 不再依赖用户机器有 Python

---

## 11. 打包完成后的自检清单

### 11.1 文件级检查

确认 `all_in_one` 中存在：

- `KeyboardConfig.exe`
- `_internal`
- `BLE_tcp_driver.exe`
- `hook_install.exe`
- `config_client.json`
- `Capswriter`
- `VC_redist.x64.exe`

### 11.2 安装器界面检查

运行 `VibecodingKeyboard_Setup.exe`，确认：

- 开始即弹出安装界面语言选择
- 有 `English` 和 `简体中文`
- 附加任务默认全选
- 完成页默认全选

### 11.3 安装后功能检查

安装完成后确认：

- `KeyboardConfig.exe` 能打开且不报 Qt DLL 错
- `BLE_tcp_driver.exe` 能启动
- `hook_install.exe` 能启动
- 点“启动语音输入”会拉起：
  - `Capswriter\start_server.exe`
  - `Capswriter\start_client.exe`
- 不会再错误地弹出第二个配置工具窗口

### 11.4 云端联调检查

确认这些接口正常：

- `GET /healthz`
- `POST /api/v1/auth/login`
- `GET /api/v1/client/config-tool/release?current_version=1.0.2`

预期：

- 服务可达
- 登录接口正常返回业务响应
- 更新接口能按环境变量返回版本信息

---

## 12. 最稳妥的发布流程

每次发新版时，按下面执行即可：

1. 修改桌面端版本号
2. 如有需要，修改默认云端地址
3. 用 `.venv_qt68` 重打 `KeyboardConfig`
4. 用 `.venv_qt68` 重打 `hook_install.exe`
5. 用 `.venv_clean311` 重打 `CapsWriter-Offline`
6. 覆盖整理 `all_in_one`
7. 用 Inno Setup 重编安装包
8. 本机完整安装一次做冒烟测试
9. 上传新安装包到 COS
10. 更新微信云托管环境变量中的版本号、下载地址、更新说明
11. 用线上接口做一次更新检查验证

---

## 13. 给后续 AI 的结论

如果只是要“稳定打包”，直接遵守下面四条即可：

1. `KeyboardConfig` 只能用 `.venv_qt68 + KeyboardConfig_onedir.spec`
2. `Capswriter` 只能打完整目录，不能只拿两个 exe
3. 安装器只从 `all_in_one` 取料，因此 `all_in_one` 必须先整理干净
4. 打完本地安装包后，还要更新微信云托管环境变量，否则“检查更新”不会闭环

如果后续 AI 不确定该用哪个目录，优先原则如下：

- 配置工具：永远使用 `vibe_code_config_tool-master\vibe_code_config_tool-master`
- Hook：永远使用 `vibe_code_config_tool-master\vibe_code_config_tool-master\hook`
- 语音：永远使用 `Capswriter-master\Capswriter-master`
- 云端：永远使用 `wxcloudrun-flask-main\wxcloudrun-flask-main`
- 安装器装配：永远使用 `all_in_one`

