# Windows 顶部版权声明实现说明

更新时间：2026-04-11

本文档说明 Windows 端主窗口右上角版权声明是怎么实现的，方便后续维护、验收，以及与 macOS 端保持统一。

## 1. 功能目标

Windows 端在主窗口菜单栏右上角展示一条固定版权声明：

```text
Copyright © 2026 南京锦心湾科技有限公司. All Rights Reserved.
```

它的作用是：

- 在主界面常驻展示公司版权归属
- 与产品窗口保持一体化，不额外弹窗打扰用户
- 给 Windows 和 macOS 端提供统一的品牌与版权露出位置

注意：这里的“版权保护”指的是界面上的版权声明展示，不是软件加密、防复制、防破解、许可证校验或 DRM。

## 2. 当前 Windows 实现位置

代码位置：

```text
vibe_code_config_tool-master/vibe_code_config_tool-master/src/ui/main_window.py
```

所在函数：

```text
MainWindow._setup_menu()
```

核心实现：

```python
self.copyright_label = QLabel(
    "Copyright © 2026 南京锦心湾科技有限公司. All Rights Reserved."
)
self.menuBar().setCornerWidget(self.copyright_label, Qt.TopRightCorner)
```

## 3. 实现方式说明

Windows 端使用的是 Qt / PySide6 自带的菜单栏角落控件能力：

- `QLabel` 负责展示版权文案
- `self.menuBar()` 获取主窗口菜单栏
- `setCornerWidget()` 把控件挂到菜单栏角落
- `Qt.TopRightCorner` 指定显示在右上角

因为版权文字挂在菜单栏上，所以它会跟随主窗口一起显示，不需要额外布局容器，也不会影响下面的主功能区域。

## 4. 交互表现

当前版权声明是静态文本：

- 不可点击
- 不打开浏览器
- 不弹出说明框
- 不参与业务逻辑
- 不保存用户配置
- 不影响语音、设备连接、按键配置等功能

它只负责展示版权信息。

## 5. 维护规则

如果后续需要修改版权文案，请优先保持 Windows 和 macOS 一致。

推荐统一文案：

```text
Copyright © 2026 南京锦心湾科技有限公司. All Rights Reserved.
```

如果年份、公司名或英文后缀要调整，需要同步通知两个端一起改，避免出现 Windows 和 macOS 文案不一致。

## 6. 验收标准

Windows 端至少需要满足：

- 启动配置工具后，主窗口右上角可以看到版权声明
- 文案为 `Copyright © 2026 南京锦心湾科技有限公司. All Rights Reserved.`
- 版权声明不遮挡菜单项
- 版权声明不影响顶部连接栏、语音按钮、AhaType、提示音开关等控件
- 点击版权文字不会触发额外业务动作

## 7. 已知边界

这个实现只是 UI 展示层能力。

如果未来要做真正的版权保护或授权校验，需要另起需求，例如：

- 安装包签名
- 可执行文件签名
- 授权码校验
- 设备绑定
- 反篡改校验
- License 服务端验证

这些都不属于当前右上角版权声明的范围。
