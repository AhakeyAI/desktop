# AhaKey Studio 2.0.0-alpha.9 — Windows preview / Windows 预览版

## English

Community preview from the contributor fork, not an official AhakeyAI stable release.

- **Install:** per-user Windows x64 MSI and portable self-contained ZIP; no separate .NET installation or BLE bridge. Close Studio through the tray's Exit command before upgrading.
- **BLE:** daily lightweight operations for source-matched X1 firmware 1.4.8 / Windows protocol 3.2: K2–K4 shortcuts, partial readback, lighting, brightness and profile switching.
- **Tray:** closing hides the window while integrations/Bluetooth continue. Reopen and Exit are in the tray; Windows login startup is opt-in.
- **Display:** static images and GIF animation uploads use USB. English, Simplified Chinese and Russian; light/dark themes.
- **Firmware:** the integrated updater is prepared in source, but this public package contains NO firmware HEX/provenance or WCH flashing components. Firmware reinstall is unavailable without the separately authorized package. No physical updater success is claimed.

Validation: 393 tests passed locally. On one AD1E reporting 1.4.8 / 3.2, BLE controls/readback and USB GIF upload were exercised; the operator confirmed keys, lighting, brightness and animation. Installed tray/background feedback, clean exit, install/uninstall and candidate-to-candidate upgrade were checked. All 235 snapshotted user files survived upgrade.

Known limits: unsigned alpha; clean Windows VM and actual Windows login-startup cycle remain untested. No complete configuration/pixel backup. K4's final automated key observation differed from the expected key; the operator separately confirmed all physical keys. Do not treat partial readback as a full backup. User data is preserved by default during uninstall. This does not replace the existing Java/macOS clients.

## 简体中文

这是贡献者 Fork 发布的社区预览版，并非 AhakeyAI 官方稳定版本。

- **安装：** Windows x64 当前用户 MSI 安装包与自包含便携 ZIP，无需另装 .NET，也无需单独启动 BLE Bridge。升级前请在托盘菜单选择“退出”。
- **蓝牙：** 面向已匹配源码的 X1 固件 1.4.8 / Windows 协议 3.2，支持 K2–K4 快捷键、部分回读、灯光、亮度及配置方案切换。
- **托盘：** 关闭窗口后蓝牙和集成继续运行，可从托盘重新打开或退出；登录自启动需用户主动开启。
- **屏幕：** 静态图片与 GIF 动画通过 USB 上传；支持英语、简体中文、俄语及深浅主题。
- **固件：** 源码已准备集成更新流程，但公开发行包不包含固件 HEX/来源文件或 WCH 烧录组件。未取得独立授权的固件包时，无法重装固件；尚未声称实体烧录验证成功。

验证：本地 393 项测试通过。在一台报告 1.4.8 / 3.2 的 AD1E 上完成 BLE 控制/部分回读及 USB GIF 上传，操作者确认按键、灯光、亮度和动画正常。已检查安装版托盘后台反馈、正常退出、安装/卸载及候选版升级，升级前后 235 个用户文件均保持不变。

限制：未签名 Alpha，尚未验证干净 Windows 虚拟机与真实登录自启动周期。没有完整配置或屏幕像素备份。K4 最后一次自动按键记录与预期不符，操作者另行确认所有实体按键正常。部分回读不能视为完整备份。卸载默认保留用户数据，不替换现有 Java/macOS 客户端。
