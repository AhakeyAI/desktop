# macOS 顶部版权声明迁移指南

更新时间：2026-04-11

本文档用于把 Windows 端主窗口右上角版权声明迁移到 macOS 端，并确保两个端的展示文案和交互保持一致。

## 1. 对齐目标

macOS 端需要展示与 Windows 端一致的版权声明：

```text
Copyright © 2026 南京锦心湾科技有限公司. All Rights Reserved.
```

对齐目标：

- 文案一致
- 位置尽量一致
- 不增加复杂交互
- 不影响已有菜单、首次引导、语音状态、AhaType 等功能

注意：这里迁移的是“版权声明展示”，不是防破解、授权校验或 DRM。

## 2. Windows 端参考实现

Windows 当前代码位置：

```text
vibe_code_config_tool-master/vibe_code_config_tool-master/src/ui/main_window.py
```

参考代码：

```python
self.copyright_label = QLabel(
    "Copyright © 2026 南京锦心湾科技有限公司. All Rights Reserved."
)
self.menuBar().setCornerWidget(self.copyright_label, Qt.TopRightCorner)
```

macOS 端如果同样使用 PySide6 / Qt，可以优先复用这个思路。

## 3. macOS 推荐实现方案

如果 macOS 端希望版权文字和 Windows 一样显示在应用窗口内部的菜单栏右上角，建议在主窗口菜单初始化后加入：

```python
self.copyright_label = QLabel(
    "Copyright © 2026 南京锦心湾科技有限公司. All Rights Reserved."
)
self.menuBar().setCornerWidget(self.copyright_label, Qt.TopRightCorner)
```

建议放在：

```text
vibe_code_config_tool-master/src/ui/main_window.py
MainWindow._setup_menu()
```

如果 macOS 当前代码中没有 `_setup_menu()`，则放在创建主窗口菜单栏的位置之后。

## 4. macOS 菜单栏注意点

macOS 的 Qt 菜单栏有一个特殊点：默认情况下，菜单栏可能会使用系统顶部原生菜单栏，而不是显示在应用窗口内部。

如果版权文字没有出现在窗口右上角，可以尝试让菜单栏使用窗口内菜单栏：

```python
self.menuBar().setNativeMenuBar(False)
self.copyright_label = QLabel(
    "Copyright © 2026 南京锦心湾科技有限公司. All Rights Reserved."
)
self.menuBar().setCornerWidget(self.copyright_label, Qt.TopRightCorner)
```

这样更容易和 Windows 的窗口内右上角展示保持一致。

## 5. 备选方案

如果 macOS 产品体验要求继续使用系统原生菜单栏，不建议强行把版权文字塞到系统菜单栏里。

可以改为放在主窗口顶部连接栏右侧，例如：

```text
连接 / 启动语音输入 / 语音状态 / 提示音开关 / AhaType / Copyright...
```

但如果采用这个方案，Windows 端也应评估是否要一起迁移到顶部连接栏右侧，否则两端位置会不一致。

当前更推荐的统一方案仍然是：

```text
窗口内菜单栏右上角
```

## 6. 交互要求

macOS 端请保持和 Windows 一致：

- 只展示文字
- 不需要点击事件
- 不打开浏览器
- 不弹窗
- 不进入设置页
- 不保存用户配置
- 不影响其他功能布局

## 7. 验收标准

macOS 端完成后，至少需要满足：

- 主窗口打开后可以看到版权声明
- 文案为 `Copyright © 2026 南京锦心湾科技有限公司. All Rights Reserved.`
- 显示位置尽量与 Windows 的右上角一致
- 不遮挡菜单项
- 不影响首次使用引导弹窗
- 不影响顶部连接栏和语音相关按钮
- 点击版权文字不会触发任何业务动作

## 8. 建议代码结构

建议保留成员变量：

```python
self.copyright_label = QLabel(...)
```

不要写成局部变量：

```python
copyright_label = QLabel(...)
```

原因是把它挂在 `self` 上更稳妥，避免控件生命周期被误回收，也方便后续统一改样式或隐藏显示。

## 9. 样式建议

第一版可以不加额外样式，保持系统默认字体即可。

如果后续需要弱化视觉存在感，可以加轻量样式：

```python
self.copyright_label.setStyleSheet("color: #8A9099; font-size: 11px;")
```

样式不是本次迁移必须项。当前优先级是先保证 Windows 和 macOS 文案、位置、行为一致。
