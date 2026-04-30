# macOS 打包与正式发布交接文档

更新时间：2026-04-12

本文档面向后续接手本项目的 AI / 开发者 / 发布同事，目标只有两个：

1. 在另一台较新的 Mac 上，稳定打出能正常使用的 `Vibecoding Keyboard.app / dmg / zip`
2. 用正式 `Developer ID + notarization` 的链路发布，尽量避免用户更新后反复丢失权限

如果后续只允许看一份文档，请优先看这一份。

如果当前接手人正在处理“新电脑第一次接管打包环境”，请同时看：

- [NEW_MAC_VENV_SETUP.md](<repo-root>/NEW_MAC_VENV_SETUP.md)

## 1. 当前结论

截至 2026-04-12，项目现状如下：

- 当前真正可信的 macOS 打包入口：`build_macos.sh`
- Finder 双击入口：`Build macOS.command`
- 主工程目录：`vibe_code_config_tool-master/`
- 蓝牙桥接器目录：`mac_bridge/`
- 语音运行时目录：`vibe_code_config_tool-master/capswriter/`

当前稳定功能已包括：

- 主界面启动
- BLE 桥接连接
- 语音输入
- `CapsLock`：完全交给 macOS 原生处理
- 语音触发键：`Voice Trigger (F18)`
- macOS `Fn` 中继方案：`Mac Fn Relay (F19)`
- 首次欢迎引导
- Hook 缺失提示
- 权限引导
- `Mode0` 预设显示：`Cap / YES / NO / Enter`
- 顶部栏提示音开关：`开提示音 / 关提示音`

Apple 签名 / 公证最新状态：

- `Developer ID Application` 证书已可用
- 新电脑上的 Xcode 冒烟测试结果为 `Accepted`
- 这说明 Apple Team 的 notarization 能力本身已可用
- 因此正式发布应迁移到新电脑执行
- 老电脑仍可用于开发、功能验证，但不建议继续作为正式发布机

## 2. 当前可信的“源码真相”

后续接手时，请优先相信下面这些文件，而不是历史 `dist/` 目录里的构建产物。

### 2.1 最重要的文件

- `build_macos.sh`
  当前唯一可信的 macOS 打包脚本。

- `Build macOS.command`
  Finder 双击包装层，本质还是调用 `build_macos.sh`。

- `vibe_code_config_tool-master/KeyboardConfig.mac.spec`
  PyInstaller 主包配置。

- `vibe_code_config_tool-master/src/app.py`
  Qt 应用入口。

- `vibe_code_config_tool-master/src/ui/main_window.py`
  主窗口总控，包含欢迎引导、Hook 提示、权限引导、语音启动、音效开关同步等。

- `vibe_code_config_tool-master/src/ui/pages/mode_page.py`
  模式配置页，包含 `Mode0` 预设显示、按键映射、动画管理等。

- `vibe_code_config_tool-master/src/ui/widgets/connection_bar.py`
  顶部栏，包含“启动语音输入”、语音状态显示、“提示音：开/关”、AhaType 等。

- `vibe_code_config_tool-master/capswriter/core_client_mac.py`
  macOS 语音客户端核心逻辑，包含：
  - 麦克风权限
  - 输入监控 / 辅助功能检查
  - `Voice Trigger (F18)` 的按下/松开监听
  - 文本回写
  - `Fn` 中继
  - 音效控制

- `vibe_code_config_tool-master/capswriter/core_server.py`
  语音服务端。

- `vibe_code_config_tool-master/capswriter/voice_hud.py`
  语音悬浮 HUD。

- `vibe_code_config_tool-master/src/core/voice_runtime.py`
  语音 bootstrap / 回退逻辑。它仍然是合法的 fallback，但不是当前 server/client 的首选启动路径。

- `vibe_code_config_tool-master/hook/hook_install.py`
  Hook 安装器逻辑。

- `mac_bridge/build_app.sh`
  蓝牙桥接器构建脚本。

### 2.2 哪些目录是构建产物，不是源码真相

下面这些目录可以查看结果，但不应当作源码编辑入口：

- `dist-macos/`
- `vibe_code_config_tool-master/dist/`
- `vibe_code_config_tool-master/build/`
- `vibe_code_config_tool-master/hook/dist/`
- `vibe_code_config_tool-master/hook/build/`
- `mac_bridge/dist/`
- `mac_bridge/build/`
- `dist-macos/dmg-root/`

额外提醒：

- `dist-macos/` 在 `build_macos.sh` 开始时会先被清空。
- 如果一次打包中途失败或被手动中断，`dist-macos/` 可能处于“半成品”状态。
- 这种情况下不要把 `dist-macos/` 里的残留产物当真。
- 应优先以：
  - `vibe_code_config_tool-master/dist/Vibecoding Keyboard.app`
  - 或重新完整跑完一次 `./build_macos.sh`
  作为判断依据。

### 2.3 哪些目录不是当前发布主链

- `mac_installer/`
  历史安装器方向，不是当前 `drag-and-drop app + dmg/zip` 主链。

- `wxcloudrun-flask-main/`
  云端后端代码，不参与本地 macOS 包构建。

## 3. 新电脑正式发布环境

正式发布建议固定在一台较新的 Apple Silicon Mac 上进行。

### 3.1 必要条件

- macOS 版本尽量新
- 已安装 Xcode 或 Xcode Command Line Tools
- 可用 Python 版本：`3.10 / 3.11 / 3.12 / 3.13`
- 已导入 `Developer ID Application` 证书和私钥（`.p12`）
- 已配置 `notarytool` keychain profile

### 3.2 上线前必须通过的本机检查

先跑：

```bash
security find-identity -v -p codesigning
```

输出中必须能看到：

```text
Developer ID Application: <Your Name> (<TEAM_ID>)
```

再跑：

```bash
xcrun notarytool history --keychain-profile <notary-profile-name>
```

如果这两步都正常，再开始正式打包。

### 3.3 项目依赖

`build_macos.sh` 会自动处理：

- 根目录 `.venv`
- 主程序依赖
- `capswriter` 的 macOS 依赖
- PyInstaller
- 主 app 构建
- `hook_install.app`
- `BLETcpBridge.app`
- `capswriter` 独立 `.python-runtime`
- 最终 `.app`
- `zip`
- `dmg`
- `notarization`（仅当 `NOTARY_PROFILE` 已配置时）

如果要重建蓝牙桥接器，本机还需要：

- `dotnet`
- `swiftc`

如果这两个命令缺失，但 `mac_bridge/dist/BLETcpBridge.app` 已存在，脚本会优先复用现有 bridge。

## 4. 正式签名与 notarization

### 4.1 当前推荐命令

在新电脑上：

```bash
cd <repo-root>

CODESIGN_IDENTITY="Developer ID Application: <Your Name> (<TEAM_ID>)" \
NOTARY_PROFILE="<notary-profile-name>" \
NOTARIZE_TARGET="dmg" \
./build_macos.sh
```

如果只想先验证 app / zip 能否稳定产出，可先跳过 `dmg`：

```bash
cd <repo-root>

SKIP_DMG=1 \
CODESIGN_IDENTITY="Developer ID Application: <Your Name> (<TEAM_ID>)" \
./build_macos.sh
```

### 4.2 notarization 目标

当前脚本支持两种目标：

- `NOTARIZE_TARGET=dmg`
- `NOTARIZE_TARGET=zip`

正式面向用户的拖拽安装发布，优先推荐：

```text
NOTARIZE_TARGET=dmg
```

### 4.3 产物输出位置

- App：`dist-macos/Vibecoding Keyboard.app`
- DMG：`dist-macos/release/VibecodingKeyboard-macOS-<version>.dmg`
- ZIP：`dist-macos/release/VibecodingKeyboard-macOS-<version>.zip`

## 5. 如何尽量避免用户更新后反复丢权限

这里必须说实话：

- macOS 的 `输入监控 / 辅助功能 / 麦克风` 权限并不是完全由我们控制
- 无法承诺“永远绝不重新授权”
- 但可以通过稳定签名和稳定包结构，把反复失效的概率降到最低

### 5.1 发布时必须保持不变的点

- 主 bundle id 不变：
  - `com.vibekeyboard.keyboardconfig`
- 主 app 名称不变：
  - `Vibecoding Keyboard.app`
- 用户安装路径尽量固定：
  - `/Applications/Vibecoding Keyboard.app`
- 内嵌 helper app 的 bundle id 不要随意改
- 后续更新继续使用同一张 `Developer ID Application` 证书
- 后续正式发布继续做 notarization

### 5.2 这些行为容易导致权限体验变差

- 用 ad-hoc 包覆盖正式签名版本
- 改 bundle id
- 改 helper app 的签名链
- 让用户从桌面副本、下载目录副本直接运行
- 正式版和测试版反复互相覆盖

### 5.3 推荐发布原则

用户侧统一原则：

- 只让用户安装 `/Applications/Vibecoding Keyboard.app`
- 后续更新也继续覆盖这一路径
- 不要把桌面临时副本当正式版本

开发侧统一原则：

- 本地开发包、临时测试包、正式发布包分开
- 正式发布只在新电脑执行
- 不再用老机器的 ad-hoc 包覆盖正式发布版本

## 6. 当前正确的语音启动路径

这一节必须和真实源码保持一致，否则后续 AI 很容易误判。

### 6.1 当前正确的主链

当前正式打包链中，macOS 的 voice server / client 首选启动方式应当是：

```text
"/Applications/.../Contents/Resources/capswriter/core_server"
"/Applications/.../Contents/Resources/capswriter/core_client_mac"
```

这两个文件不是历史残留，而是 `build_macos.sh` 在打包时生成的 shell launcher。

对应源码位置：

- `build_macos.sh`
  - `prepare_capswriter_python_runtime()`
  - `write_capswriter_python_launcher()`
  - `prepare_capswriter_launchers()`
- `vibe_code_config_tool-master/src/ui/main_window.py`
  - `_voice_launch_argv()`

真实行为是：

1. `build_macos.sh` 把 `capswriter/` 复制进 `Contents/Resources/capswriter`
2. 再把独立 `.python-runtime` 嵌进去
3. 再生成两个可执行 launcher：
   - `core_server`
   - `core_client_mac`
4. 主程序启动语音时，优先直接执行这两个 launcher

### 6.2 什么是 fallback，不要误判成主链

下面这条仍然存在，但它现在是 fallback / bootstrap 机制，不是 server/client 的首选启动方式：

```text
"/Applications/.../Contents/MacOS/KeyboardConfig" --capswriter-bootstrap ...
```

对应源码位置：

- `vibe_code_config_tool-master/src/core/voice_runtime.py`

需要明确区分：

- 对 `core_server` / `core_client_mac`：
  - 当前应优先走 `Resources/capswriter/core_server`
  - 当前应优先走 `Resources/capswriter/core_client_mac`
- 对 `voice_hud`：
  - 当前仍允许走 `KeyboardConfig --capswriter-bootstrap voice_hud`
  - 这是当前设计的一部分，不算错误

所以判断标准不是“日志里绝不能出现 bootstrap”，而是：

- `core_server` / `core_client_mac` 不应长期回退成纯 bootstrap 主链
- `voice_hud` 走 bootstrap 仍然是可接受、当前真实存在的路径

## 7. 功能与文件映射

### 7.1 首次欢迎引导

主要文件：

- `vibe_code_config_tool-master/src/ui/main_window.py`

关键点：

- `WelcomeGuideDialog`
- `_run_startup_guidance_flow()`
- `_maybe_show_welcome_guide()`
- `_show_welcome_guide()`
- `_WELCOME_GUIDE_VERSION`

当前版本标记：

```text
{APP_VERSION}-guide-9
```

如果希望已安装用户再次弹出引导，可以继续提高这个版本标记。

### 7.2 Hook 提示与 Hook 管理器

主要文件：

- `vibe_code_config_tool-master/src/core/hook_integration.py`
- `vibe_code_config_tool-master/hook/hook_install.py`
- `vibe_code_config_tool-master/src/core/install_cleanup.py`
- `vibe_code_config_tool-master/src/ui/main_window.py`

当前打包进 app 的 hook 管理器位于：

```text
Contents/Resources/bundled_apps/hook_install.app
```

### 7.3 Mode0 预设显示

主要文件：

- `vibe_code_config_tool-master/src/ui/pages/mode_page.py`

关键点：

- `_MODE0_DISPLAY_PRESETS = ("Cap", "YES", "NO", "Enter")`
- `_effective_key_labels()`

当前原则：

- 只做显示层默认值
- 不静默改写真实配置

### 7.4 语音提示音开关

主要文件：

- `vibe_code_config_tool-master/src/ui/widgets/connection_bar.py`
- `vibe_code_config_tool-master/src/ui/main_window.py`
- `vibe_code_config_tool-master/capswriter/core_client_mac.py`

关键点：

- 顶部栏按钮文案是“动作”，不是“状态”
- 当前显示逻辑：
  - 提示音已开启时：显示 `关提示音`
  - 提示音已关闭时：显示 `开提示音`
- UI 持久化键：`voice/audio_cue_enabled`
- 共享配置文件：`/tmp/capswriter_config.json`
- 字段：`enable_audio_cue`

### 7.5 macOS Fn 中继

主要文件：

- `vibe_code_config_tool-master/src/core/fn_relay_mac.py`
- `vibe_code_config_tool-master/src/core/keycodes.py`
- `vibe_code_config_tool-master/capswriter/core_client_mac.py`

当前方案：

- 设备端映射成标准 HID `F19`
- macOS 客户端监听后转成 `Fn/Globe` 风格触发

### 7.6 语音输入

主要文件：

- `vibe_code_config_tool-master/capswriter/core_server.py`
- `vibe_code_config_tool-master/capswriter/core_client_mac.py`
- `vibe_code_config_tool-master/capswriter/voice_hud.py`
- `vibe_code_config_tool-master/src/core/voice_runtime.py`
- `vibe_code_config_tool-master/src/ui/main_window.py`
- `build_macos.sh`

当前稳定事实：

1. 语音运行时是“独立 Python runtime + shell 启动器”
2. `build_macos.sh` 会生成：
   - `Resources/capswriter/core_server`
   - `Resources/capswriter/core_client_mac`
3. `main_window.py` 启动 server/client 时优先执行上面两个 launcher
4. `voice_hud.py` 当前允许通过 bootstrap 主程序拉起
5. 当前按键语义是：
   - `CapsLock`：完全交给 macOS 原生处理
   - `Voice Trigger (F18)`：按下开始录音，松开结束录音并转写
   - `Mac Fn Relay (F19)`：给 Typeless / Fn 中继使用
6. 正式打包依赖：
   - `capswriter/models`
   - `capswriter/.python-runtime`
   - `websockets`
   - `rich`
   - `numpy`
   - `sounddevice` 相关依赖

### 7.5 2026-04-12 语音打包经验封存

这一节非常重要，后续 AI / 开发者如果忽略这里，极容易把语音链又改回错误路线。

#### 7.5.1 真正稳定的语音主链

本轮反复验证后，当前在这台老电脑上真正稳定的语音主链是：

```text
Contents/Resources/capswriter/core_server
Contents/Resources/capswriter/core_client_mac
```

也就是：

- `server/client` 走 `Resources/capswriter/` 里的 shell launcher
- launcher 再带起独立 `.python-runtime`
- `voice_hud` 可以继续走 `KeyboardConfig --capswriter-bootstrap voice_hud`

不要把 `server/client` 默认改成：

```text
KeyboardConfig --capswriter-bootstrap core_server
KeyboardConfig --capswriter-bootstrap core_client_mac
```

这条 bootstrap 路线可以作为兜底，但不应再当主链。

#### 7.5.2 为什么之前会误判成“应该走 bootstrap”

原因不是单一 bug，而是几个因素叠在一起：

1. 旧日志里曾出现过 `--capswriter-bootstrap ...`
2. `voice_hud` 本来就允许走 bootstrap
3. 在受限终端 / 沙箱里手工跑 `core_server` 时，`multiprocessing.Manager()` 会报：
   - `PermissionError: [Errno 1] Operation not permitted`
4. 这个错误看起来像“包坏了”，但实际更像终端执行环境限制，不代表 app 本身一定坏

所以经验结论是：

- 在 Codex / 受限终端里失败，不等于真实 app 在 Finder / 正常终端里也失败
- 语音链判断要优先看：
  - 真实日志里主窗口拉起的命令
  - 非沙箱环境下 direct launcher 能否跑到“开始服务”

#### 7.5.3 如何验证语音主链是否又走偏

后续每次改完语音相关代码，先不要靠感觉判断，直接核这两件事：

1. 主窗口日志里 `server/client` 是否显示为：

```text
.../Contents/Resources/capswriter/core_server
.../Contents/Resources/capswriter/core_client_mac
```

2. 不应长期优先出现：

```text
.../Contents/MacOS/KeyboardConfig --capswriter-bootstrap core_server
.../Contents/MacOS/KeyboardConfig --capswriter-bootstrap core_client_mac
```

允许继续存在的 bootstrap 只有：

```text
.../Contents/MacOS/KeyboardConfig --capswriter-bootstrap voice_hud
```

#### 7.5.4 这次实际踩到的缺依赖

这轮在错误路线里，主程序 bootstrap `core_server` 时实际缺过这些模块：

- `websockets`
- `rich`
- `logging.handlers`

它们并不是 `capswriter/.python-runtime` 缺，而是“主程序 frozen bootstrap 路线”自身没把脚本运行所需模块带全。

这也是为什么结论最终回到了：

- `server/client` 还是应该优先走 direct launcher
- 不要再强行把它们收回 bootstrap 主链

#### 7.5.5 `System Events` 弹窗的真实来源

macOS 上那种额外的系统弹窗：

- “允许控制 System Events”
- 或用户感觉成“又多弹了一个辅助功能/自动化相关弹窗”

根因不是我们自己的 `VoicePermissionGuideDialog`，而是语音客户端里仍然存在一些 `osascript + System Events` 回退路径。

历史主要来源文件：

- `vibe_code_config_tool-master/capswriter/core_client_mac.py`
  - `_paste_via_applescript()`
  - `_paste_via_menu_action()`
  - `_type_text_via_applescript()`
- `vibe_code_config_tool-master/capswriter/correction_learner.py`
  - 历史 `System Events` 学习读取路径

当前处理结论：

- 如果目标是“只保留我们自己的权限引导，不再额外弹系统自动化授权框”，主流程不应再走 `System Events`
- 当前主流程应优先保留：
  - Quartz Unicode 直输
  - AX helper 直写
  - Quartz 粘贴
- `System Events` 相关回退不应再作为自动主链使用

#### 7.5.6 以后遇到 `-9` / “未生成日志文件”怎么判断

如果用户日志里出现：

- `语音客户端 已停止，退出码=-9`
- `语音服务器 已停止，退出码=-9`
- `当前尚未生成日志文件`

优先按下面顺序排查：

1. `main_window.py` 的 `_voice_launch_argv()` 是否又把 `server/client` 选成 bootstrap
2. `Resources/capswriter/core_server` / `core_client_mac` 是否仍存在并可执行
3. `capswriter/.python-runtime/site-packages` 里是否仍包含：
   - `websockets`
   - `rich`
   - `numpy`
   - `sounddevice`
   - `sherpa_onnx`
4. 再去看权限 / 模型 / 焦点写回问题

不要第一时间回退去改 F18、CapsLock、HUD 或权限引导，那通常不是根因。

#### 7.5.7 为什么“不签名能跑，Developer ID 签名后反而更容易出问题”

这是这轮最容易让人误判的一点。

现象：

- 本地开发态 / ad-hoc 包里，语音 `server/client` 看起来能跑
- 一旦切到 `Developer ID + hardened runtime`，就会出现：
  - 点击“启动语音输入”后主界面像卡住
  - `core_client_mac` 没有正常产生日志
  - 或者 `server/client` 被系统直接干掉

根因不是“签名把功能签坏了”，而是正式签名把原来被系统宽松放过的问题暴露出来了：

1. 语音独立 `.python-runtime` 里如果还残留指向系统 Python 的动态库路径，正式签名后更容易在启动阶段被系统拦掉
2. `PyObjC/AppKit/Quartz` 这条链在打包 runtime 里非常脆弱
3. `core_client_mac.py` 如果继续在 Python 里直接 `import AppKit` / `import Quartz`，在正式签名包里可能表现成“进程不崩，但一直卡住”

这轮最后稳定下来的处理方式是：

- 保留 `core_server` / `core_client_mac` 的独立 launcher 主链
- 修正 `.python-runtime` 的动态库引用，避免继续指向系统 Python
- 不再让 `core_client_mac.py` 依赖 Python 侧的 `AppKit/Quartz` 事件链
- 改成由独立 Swift helper 去做：
  - 输入监控预检
  - 键盘事件监听
  - 鼠标点击回焦
  - 粘贴 / 文本输入

关键文件：

- `vibe_code_config_tool-master/capswriter/core_client_mac.py`
- `vibe_code_config_tool-master/capswriter/voice_input_bridge.swift`
- `build_macos.sh`
- `macos_hardened_runtime.entitlements`

经验结论：

- “不签名能跑”不等于“正式签名也一定能跑”
- 只要语音链改动涉及：
  - `.python-runtime`
  - `PyObjC`
  - `Quartz/AppKit`
  - `install_name_tool`
  - `codesign --options runtime`
  就必须用正式签名包再做一轮真实验证

## 8. 为什么包会大

当前包大的主要原因不是垃圾文件，而是功能结构决定的：

- Qt / Python Frameworks
- 语音模型
- 独立 `.python-runtime`
- Hook helper app
- 蓝牙 bridge helper app

在 `prepare_capswriter_python_runtime()` 中，已经明确剔除了这些不必要依赖：

- `PySide6`
- `PIL`
- `qdarktheme`
- `bleak`
- `qrcode`
- `pip / setuptools / wheel / PyInstaller`

后续不要再轻易动下面这些：

- `websockets`
- `rich`
- `numpy`
- `sounddevice`
- `capswriter/models`
- `capswriter/.python-runtime`

## 9. 新电脑正式发布后的最小验收

在新电脑上打出正式 `dmg` 后，至少做下面这轮最小验收：

1. 首次打开：
   - 能正常启动主界面
   - 首次欢迎引导能弹出

2. 权限：
   - 麦克风权限正常
   - 输入监控 / 辅助功能按引导开启

3. 语音：
   - `CapsLock` 仍是 macOS 原生大小写 / 输入法切换
   - 某个设备键映射成 `Voice Trigger (F18)` 后，按下开始录音，松开结束录音并转写
   - `Mac Fn Relay (F19)` 如需启用 Typeless，应能单独工作
   - 文本能正常回写
   - “开提示音 / 关提示音”生效

4. 设备：
   - BLE 连接正常
   - `Mode0` 预设显示正常

5. 分发：
   - `spctl -a -vv` 不再显示未公证
   - 新电脑和用户电脑上首次打开体验正常

## 10. 最后建议

后续发布策略建议固定为：

- 老电脑：开发 / 本地验证
- 新电脑：正式签名 / notarization / `dmg` 产出

这是当前最稳、最不容易再次把权限链和公证链弄乱的做法。
