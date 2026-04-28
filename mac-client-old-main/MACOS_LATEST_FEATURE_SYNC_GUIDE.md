# macOS 最新功能同步指导

更新时间：2026-04-12

本文档用于把 Windows 端目前已经落地的最新版新增功能，整理成一份可直接指导 macOS 同事同步修改的说明文档。

目标不是复述最早的需求草稿，而是以当前 Windows 代码中的实际行为为准，帮助 macOS 端快速完成对齐，减少来回确认。

## 1. 本文档覆盖范围

本次建议 macOS 对齐的功能包括：

1. 首次使用引导弹窗
2. 问号说明按钮体系
3. 顶部语音状态灯与状态文字
4. 语音输入悬浮窗
5. Mode0 默认预设显示
6. 语音提示音开关
7. 右上角版权声明
8. 启动阶段的 BLE 驱动自启动思路

补充说明：

- 文档中的“Windows 当前实现位置”用于给同事核对最新逻辑。
- 文档中的“macOS 对齐建议”用于指导迁移，不要求 macOS 必须逐行照搬，只要求产品行为、文案语义和关键状态尽量一致。
- 如果 macOS 端已有更成熟的底层实现，可以保留原有机制，只同步用户可见体验。



## 3. 首次使用引导弹窗

### 3.1 产品目标

首次打开应用时，不直接把所有复杂功能一次性暴露给用户，而是先通过一个轻量弹窗告诉用户：

- 先从哪里开始
- 语音输入怎么启动
- 设备连接和按键配置怎么开始

这个弹窗只自动出现一次，但用户后续可以从菜单中手动再次打开。

### 3.2 Windows 当前行为

当前 Windows 端实现如下：

- 主窗口首次显示后，通过 `QTimer.singleShot(700, ...)` 延迟约 `700ms` 触发
- 不是应用构造时立刻弹出，而是等窗口稳定显示后再弹
- 弹窗为模态窗口
- 用户点击“我知道了”后才会把已看过状态写入本地配置
- 菜单中提供“查看功能引导”入口，可手动再次打开
- 引导关闭后，Windows 目前保留了一个 `_run_post_guide_startup_checks()` 扩展点，但当前为 no-op

### 3.3 当前 Windows 最新文案

窗口标题：

```text
欢迎使用 Vibecoding Keyboard
```

副标题：

```text
你可以先从下面两个功能开始：
```

卡片 1 标题：

```text
启动语音
```

卡片 1 当前含义要点：

- 点击顶部“启动语音输入”，可以把说话内容快速转换成文字
- 首次使用时，系统会提示开启相关权限
- 如果启动后弹出黑色控制台窗口，直接叉掉也没关系，它会隐藏到电脑右下角通知区域继续运行
- 当右侧状态变成绿色“语音已就绪”后，可以按下 `键盘语音键`，也就是Key1 键开始录音


卡片 2 标题：

```text
连接设备和配置按键
```

卡片 2 当前含义要点：

- 点击顶部“连接”后查看设备状态
- 进入“模式配置”页后配置按键功能并写入设备
- 如果需要灯效或动图显示，可在“动画管理”中添加图片或 GIF

底部提示：

```text
建议第一次使用时，先体验“启动语音”，再连接设备配置按键。
```

确认按钮：

```text
我知道了
```

### 3.4 只显示一次的规则

Windows 当前使用 `QSettings` 保存：

- `ui/welcome_guide_seen`
- `ui/welcome_guide_version`

当前版本标记：

```text
{APP_VERSION}-guide-6
```

规则建议继续保持：

- 若引导内容有更新，提升 `guide` 版本号
- 版本号变化后，旧用户会再看到一次新引导
- 版本号不变时，看过的用户不再自动弹出

### 3.5 Windows 当前实现位置

- `vibe_code_config_tool-master/vibe_code_config_tool-master/src/ui/main_window.py`
  - `WelcomeGuideDialog`
  - `showEvent()`
  - `_run_startup_guidance_flow()`
  - `_maybe_show_welcome_guide()`
  - `_show_welcome_guide()`
  - `_run_post_guide_startup_checks()`
  - 菜单项“查看功能引导”

### 3.6 macOS 对齐建议

建议 macOS 保持以下一致：

- 延迟触发时机保持为主窗口显示后约 `700ms`
- 保留“只自动出现一次 + 菜单可再次打开”机制
- 标题、两张卡片、底部提示、确认按钮结构保持一致
- `guide` 版本号建议同步提升为 `guide-6`

macOS 可以保留平台自己的后置流程，例如：

- 欢迎引导关闭后继续进入权限检查
- 或继续进入 Hook 缺失检查

但建议不要改变用户能看到的引导内容和整体时机。

## 4. 问号说明按钮体系

### 4.1 产品目标

对不适合在主界面展开解释、但新用户容易困惑的功能，在标题旁边加一个轻量的 `?` 问号按钮。

点击后弹出标准信息框，说明：

- 这个功能是做什么的
- 什么场景适合用
- 关键操作从哪里开始

### 4.2 通用交互定义

Windows 当前统一实现特点：

- 问号按钮为圆形 `?`
- 尺寸较小，不抢主界面注意力
- 鼠标悬停时轻微高亮
- 点击后使用 `QMessageBox.information(...)` 弹出标准信息框

Windows 当前通用组件位置：

- `vibe_code_config_tool-master/vibe_code_config_tool-master/src/ui/widgets/help_button.py`
  - `HelpButton`

macOS 若同样使用 Qt，建议直接保留这一交互模型，不需要改成悬浮说明层或网页跳转。

### 4.3 语音输入按钮右侧问号

位置：

- 顶部连接栏中，“启动语音输入”按钮右侧

当前标题：

```text
语音输入说明
```

当前正文语义：

```text
单纯语音转文字不收费。

如果你只是使用本地语音识别，把说话内容转换成文字，可以直接使用。

只有在启用 AhaType 后，识别结果才会再经过云端整理和润色。
```

Windows 当前实现位置：

- `vibe_code_config_tool-master/vibe_code_config_tool-master/src/ui/widgets/connection_bar.py`
  - `self.voice_help_btn`

macOS 对齐建议：

- 保留这个说明入口
- 明确强调“单纯语音转文字不收费”
- 不要把 AhaType 和普通语音输入混成一个说明

### 4.4 AhaType 问号

位置：

- 顶部连接栏中，“启动AhaType”按钮右侧

标题：

```text
AhaType 说明
```

正文：

```text
AhaType 会把语音识别结果再做一次整理和润色。

适合用于口语转书面语、补全标点，或让输入内容更适合直接发送和记录。

使用前需要先登录，并且云端服务可用。
```

Windows 当前实现位置：

- `vibe_code_config_tool-master/vibe_code_config_tool-master/src/ui/widgets/connection_bar.py`
  - `self.typeless_help_btn`

### 4.5 模式说明问号

位置：

- `Mode 0 / Mode1 / Mode 2` 模式切换区域右侧

标题：

```text
模式说明
```

当前正文以最新版为准：

```text
软件里的 Mode 0 / Mode1 / Mode 2，分别对应键盘上的左数 1、2 灯亮 / 3、4 灯亮 / 5、6 灯亮。

单击电源键切换模式。

你当前切换到哪个 Mode，修改的就是键盘对应模式下的按键功能和动画配置。

点击连接后，就可以修改当前模式下的按键和动画配置。
```

特别说明：

- 之前有一条“例如你在 Mode1 里设置快捷键并保存到设备……”的举例说明，现版本已按要求删除
- macOS 同步时不要把那条旧示例再加回来

Windows 当前实现位置：

- `vibe_code_config_tool-master/vibe_code_config_tool-master/src/ui/widgets/mode_selector.py`
  - `self.mode_help_btn`

### 4.6 按键映射问号

位置：

- “模式配置”页中，“按键映射”标题右侧

标题：

```text
按键映射说明
```

当前正文要点：

- 这里可以给当前模式下的每个按键分配功能
- 第一步必须先点击顶部“连接”，连接成功后才可以更改键盘设置并写入设备
- `Key1` 对应的是键盘最左边的语音键
- 适合配置快捷键、组合键、文本输入或不同模式下的专用布局
- 当前正文中已经包含详细的快捷键示例和宏示例

当前已加入的快捷键示例：

```text
示例：把 Key1 设置为 Ctrl+C 复制
a. 进入“模式配置”页，选择要配置的模式，例如 Mode1。
b. 在左侧 4 键示意图里点击 Key1。
c. 在“按键描述”里输入便于识别的名字，例如 CTRL_C_COPY。按键描述会显示在键盘屏幕上，建议使用英文、数字或下划线。
d. 在“按键类型”中选择“快捷键”。
e. 在键码下拉框中选择 Left Ctrl，点击“添加”。
f. 再选择字母 C，点击“添加”。
g. 确认列表里已经有 Left Ctrl 和 C，最后点击“应用按键到设备”。
```

当前宏示例语义：

- 将按键类型改成“宏”
- 按顺序添加一组按下、延时、释放动作
- 现版本示例为一个类似复制流程的宏

Windows 当前实现位置：

- `vibe_code_config_tool-master/vibe_code_config_tool-master/src/ui/pages/mode_page.py`
  - `_build_keymap_group()`
  - `_build_group_header()`

macOS 对齐建议：

- 保留“先连接再改配置”的提醒
- 保留 `Key1` 是“最左边的语音键”这一版新表述
- 保留快捷键和宏定义的实操示例，避免只给概念解释

### 4.7 动画管理问号

位置：

- “模式配置”页中，“动画管理”标题右侧

标题：

```text
动画管理说明
```

当前正文要点：

- 这里可以上传图片或 GIF，生成设备显示用的动画帧
- 第一步同样要先点击顶部“连接”，连接成功后才能修改并写入设备
- 适合上传开机动画、模式显示效果或不同模式的视觉反馈
- 当前正文中已加入静态图片和 GIF 两个具体示例

当前示例语义：

- 示例 1：上传 `png/jpg` 作为静态图
- 示例 2：上传 `GIF` 后可先调整 `FPS`，再预览，再写入设备

Windows 当前实现位置：

- `vibe_code_config_tool-master/vibe_code_config_tool-master/src/ui/pages/mode_page.py`
  - `_build_display_group()`
  - `_build_group_header()`

macOS 对齐建议：

- 动画管理问号不要只写概念说明
- 建议跟 Windows 一样加入“先连接”的前置提醒和至少两个操作示例


## 7. Mode0 默认预设显示

### 7.1 产品目标

用户第一次进入 `Mode0` 时，不应该看到像“未配置”一样的空白状态。

应直接显示默认预设标签：

```text
Key1 -> F18
Key2 -> YES
Key3 -> NO
Key4 -> Enter
```

### 7.2 当前 Windows 行为

Windows 当前实现原则：

- 只有当前模式是 `Mode0` 时，才显示这组预设文案
- 如果该键位已经有真实配置，优先显示真实配置
- 如果该键位没有真实配置，仅在显示层回退到预设文案
- 不会静默写回设备或本地配置

也就是说，这是一种“界面显示层默认值”，不是“偷偷帮用户改配置”。

### 7.3 Windows 当前实现位置

- `vibe_code_config_tool-master/vibe_code_config_tool-master/src/ui/pages/mode_page.py`
  - `_MODE0_DISPLAY_PRESETS = ("Cap", "YES", "NO", "Enter")`
  - `_effective_key_labels()`
  - `_refresh_ui()`
  - `_on_binding_changed()`

### 7.4 macOS 对齐建议

macOS 端建议完全保留这个原则：

- 直接显示预设
- 但不写回真实绑定
- 用户改过之后以真实值覆盖显示

这是一个很重要的体验细节，能避免用户误以为 Mode0 没有预设能力。

## 8. 语音提示音开关

### 8.1 产品目标

录音开始和结束时的提示音，不应强制用户接受。

要给用户一个显式开关，让用户自己选择：

- 保留提示音
- 关闭提示音

### 8.2 当前 Windows 按钮逻辑

Windows 当前已经修正为“按钮文案表示点击动作”，不是表示当前状态：

- 当前已开启提示音时，按钮显示：`关闭提示音`
- 当前已关闭提示音时，按钮显示：`开启提示音`

Tooltip：

```text
控制开始录音和结束录音时的提示音
```

### 8.3 当前 Windows 持久化与运行时同步

本地持久化键：

```text
voice/audio_cue_enabled
```

同步给语音运行时的共享配置文件：

```text
%TEMP%/capswriter_config.json
```

写入字段：

```json
{
  "enable_audio_cue": true
}
```

### 8.4 Windows 当前实现位置

顶部按钮：

- `vibe_code_config_tool-master/vibe_code_config_tool-master/src/ui/widgets/connection_bar.py`
  - `audio_cue_toggled = Signal(bool)`
  - `self.audio_cue_btn`
  - `_on_audio_cue_click()`
  - `_update_audio_cue_button_text()`
  - `set_audio_cue_enabled()`

主窗口持久化与同步：

- `vibe_code_config_tool-master/vibe_code_config_tool-master/src/ui/main_window.py`
  - `_load_audio_cue_enabled()`
  - `_on_audio_cue_toggled()`
  - `_apply_audio_cue_enabled()`
  - `_write_capswriter_shared_config()`

### 8.5 macOS 对齐建议

建议 macOS 同步以下体验：

- 顶部连接栏保留这个显式开关
- 采用与 Windows 一致的按钮文案逻辑
- 用户点击后立即生效
- 下次启动后记住上次选择
- 同步给语音侧运行时配置

如果 macOS 当前已有自己的配置文件路径，可以不要求路径完全一致，但建议字段语义继续使用：

```json
{
  "enable_audio_cue": true
}
```

## 9. 右上角版权声明

### 9.1 当前 Windows 文案

```text
Copyright © 2026 南京锦心湾科技有限公司. All Rights Reserved.
```

### 9.2 当前 Windows 实现方式

Windows 当前将版权文字挂到主窗口菜单栏右上角。

实现位置：

- `vibe_code_config_tool-master/vibe_code_config_tool-master/src/ui/main_window.py`
  - `self.copyright_label = QLabel(...)`
  - `self.menuBar().setCornerWidget(self.copyright_label, Qt.TopRightCorner)`

### 9.3 macOS 对齐建议

建议 macOS 保持：

- 文案完全一致
- 尽量显示在窗口内右上角
- 仅作为静态说明文字，不要附带跳转或弹窗

如果 macOS 因原生菜单栏机制导致 `setCornerWidget(...)` 不适合使用，可参考已有文档：

- `MACOS_COPYRIGHT_NOTICE_MIGRATION_GUIDE.md`

但最终对外体验建议仍尽量与 Windows 一致。



### 11.2 AhaType 登录前置

Windows 当前逻辑：

- 用户尝试开启 AhaType 时，如果未登录，会弹出提示并跳转到用户页
- 不允许在未登录时误开启

如果 macOS 端尚未做这层保护，建议一并同步。

## 12. macOS 同步优先级建议

如果需要分批实现，建议优先级如下：

