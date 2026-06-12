# Windows Mode0 预设与语音提示音对齐文档

更新时间：2026-04-11

本文档用于让 Windows 端同事直接对齐两个已经在 macOS 端落地的交互能力：

1. `Mode0` 默认预设显示
2. 语音提示音的可开关控制

目标是让同事只看这一份文档，就能理解需求、文案、交互、状态和参考代码位置，不需要额外口头解释。

## 1. 对齐目标

Windows 端需要补齐以下两项体验：

- 当用户第一次进入模式配置页时，`Mode0` 需要直接显示预设键位含义，避免用户误以为没有预设。
- 在主界面顶部给用户一个“提示音开/关”的显式入口，让用户自己决定录音开始/结束时是否播放提示音。

这两项都属于“默认体验说明”类能力：

- `Mode0` 解决的是“用户不知道我们有预设”
- `提示音开关` 解决的是“有些用户觉得提示音太吵”

## 2. Mode0 默认预设显示

### 2.1 产品目标

用户第一次看到 `Mode0` 时，不应该是空白、未知或看起来像未配置状态。

Windows 端需要在 `Mode0` 上直接显示以下预设标签：

```text
Key1 -> Cap
Key2 -> YES
Key3 -> NO
Key4 -> Enter
```

### 2.2 交互要求

请按下面的规则实现：

- 仅当当前模式是 `Mode0` 时，显示这组预设标签
- 如果某个键位还没有真实自定义值，则显示预设标签
- 如果用户已经自己改过该键位，则优先显示用户真实配置
- 不要在界面加载时静默把这些预设写回设备或本地配置
- 这是一种“显示层默认值”，不是“偷偷改配置”

### 2.3 用户预期

用户进入 `Mode0` 后，应该直接看到类似：

```text
Key1  Cap
Key2  YES
Key3  NO
Key4  Enter
```

而不是四个看起来空白的按钮或占位项。

### 2.4 macOS 已实现位置

参考代码位置：

- [mode_page.py](/Users/macbookforpp/Desktop/macmac/待适配mac/vibe_code_config_tool-master/src/ui/pages/mode_page.py)

关键实现点：

- `_MODE0_DISPLAY_PRESETS = ("Cap", "YES", "NO", "Enter")`
- `_effective_key_labels()`
- `_refresh_ui()`
- `_on_binding_changed()`

当前 macOS 的实现方式是：

- 先判断是否是 `Mode0`
- 再判断当前槽位是否已有真实绑定
- 如果没有真实绑定，则仅在界面上显示预设文案
- 不会偷偷回写实际配置

Windows 端请保持这个原则一致。

## 3. 语音提示音开关

### 3.1 产品目标

语音输入开始和结束时，当前 macOS 会播放提示音。

但有些用户反馈这个声音在日常办公场景里偏吵，所以需要给用户显式选择权：

- 想保留提示音的人，可以继续用
- 不想听提示音的人，可以自己关掉

### 3.2 控件位置

请将这个入口放在主界面顶部连接栏，靠近“启动语音输入”区域。

macOS 当前布局顺序大致是：

```text
连接 / 启动语音输入 / 语音状态灯 / 语音状态文字 / 提示音开关 / 启动AhaType
```

### 3.3 按钮文本

开启时：

```text
提示音：开
```

关闭时：

```text
提示音：关
```

### 3.4 Tooltip 文案

建议 Tooltip：

```text
控制开始录音和结束录音时的提示音
```

### 3.5 交互要求

- 点击一次：在“开 / 关”之间切换
- 切换后，按钮文本立即更新
- 新状态要立即同步给语音客户端
- 用户下次打开应用时，沿用上一次的选择

### 3.6 默认值

当前 macOS 默认值是：

```text
开启
```

也就是首次进入时，按钮默认显示：

```text
提示音：开
```

### 3.7 持久化要求

macOS 当前将其持久化到 UI 设置中，键为：

```text
voice/audio_cue_enabled
```

Windows 端如果使用不同配置系统，可以不要求键名完全一致，但建议保留相同语义。

### 3.8 同步到语音运行时

macOS 当前会把状态同步给共享配置文件：

```text
/tmp/capswriter_config.json
```

写入字段：

```json
{
  "enable_audio_cue": true
}
```

Windows 端不一定要使用相同路径，但请保留这个能力：

- UI 改动后
- 语音模块能收到“是否播放提示音”的最新值

### 3.9 macOS 已实现位置

顶部按钮组件：

- [connection_bar.py](/Users/macbookforpp/Desktop/macmac/待适配mac/vibe_code_config_tool-master/src/ui/widgets/connection_bar.py)

关键点：

- `audio_cue_toggled = Signal(bool)`
- `self.audio_cue_btn = QPushButton("提示音：开")`
- `_on_audio_cue_click()`
- `_update_audio_cue_button_text()`
- `set_audio_cue_enabled()`

主窗口持久化与同步：

- [main_window.py](/Users/macbookforpp/Desktop/macmac/待适配mac/vibe_code_config_tool-master/src/ui/main_window.py)

关键点：

- `_AUDIO_CUE_CONFIG_PATH = Path("/tmp/capswriter_config.json")`
- `_on_audio_cue_toggled()`
- `_apply_audio_cue_enabled()`
- `_write_capswriter_shared_config()`

## 4. Windows 端验收标准

Windows 端完成后，至少需要满足下面 5 条：

1. `Mode0` 进入后直接看到 `Cap / YES / NO / Enter`
2. 这些预设只做显示，不静默改写真实配置
3. 顶部主界面能看到“提示音：开/关”按钮
4. 点击按钮后文字立即更新且即时生效
5. 重启应用后，仍保持上一次用户选择

## 5. 最终建议

请 Windows 端直接按以下原则实现：

- `Mode0`：显示预设，但不静默改写真实配置
- `提示音开关`：显式入口、即时生效、持久保存
- 文案尽量与 macOS 保持一致
- 不需要额外加复杂设置页，先在现有主界面完成对齐
