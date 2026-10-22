# Installation and upgrade / Установка и обновление / 安装与升级

## EN

Supported platform: Windows 11 x64, AhaKey X1 / CH582M running firmware 1.4.8 and protocol 3.2. Do not update firmware for this release. HEX and WCH drivers/tools are not included.

1. Compare MSI or ZIP SHA-256 with SHA256SUMS.txt: `Get-FileHash -Algorithm SHA256 <package>`.
2. Finish any device operation, then choose Exit from Studio's tray menu. The installer does not force-close Studio or another process. Wait if Studio reports an active operation.
3. Run the MSI for the current Windows user. It includes .NET; no developer tools or separate .NET installation are required. The Start menu shortcut is installed; the desktop shortcut is optional.
4. To upgrade alpha.9, run the 2.0.0 MSI after exiting. Its internal MSI version 2.0.101 is above alpha.9's 2.0.90. Projects/settings stay in `%LOCALAPPDATA%/AhaKey/Studio2`. Export projects before migration; exports are drafts, not full hardware backups.
5. For portable use, extract the ZIP to a permanent folder and start `AhaKey Studio.exe`. Portable and installed copies share the same per-user data and single-instance ownership. If Windows startup is enabled for a portable copy, keep its folder unchanged or re-enable startup after moving it.
6. Enable Windows startup, physical integrations, profile activation and voice actions explicitly in Settings/Integrations. Closing the window hides it in the tray; reopen from the tray and use Exit to stop Studio.
7. Uninstall through Windows Settings after Exit. Uninstall removes application files, shortcuts and Studio-owned startup registration; user projects/settings are preserved. Re-enable startup after reinstall if desired. Clean VM installation/upgrade/uninstall and actual Windows sign-out/sign-in still require acceptance before stable publication.

Packages in this candidate are unsigned. Do not claim certificate verification or a signed publisher.

## RU

Цель: Windows 11 x64, AhaKey X1 / CH582M, firmware 1.4.8, protocol 3.2. Обновление firmware не требуется; HEX и WCH-компонентов в пакете нет.

Сверьте SHA-256 с SHA256SUMS.txt. Завершите операцию с устройством и выберите «Выход» в tray. Запустите MSI для текущего пользователя: .NET включён. Для обновления alpha.9 используйте MSI 2.0.0; внутренняя версия 2.0.101 обеспечивает повышение относительно 2.0.90. Данные сохраняются в `%LOCALAPPDATA%/AhaKey/Studio2`. Экспорт проекта сохраняет черновик, а не полный backup устройства.

Portable ZIP распакуйте в постоянную папку. Установленная и portable копии используют общие пользовательские данные и single instance. Автозапуск, физические интеграции, активация профиля и голосовые действия включаются явно. Закрытие окна скрывает Studio в tray; «Выход» завершает приложение. Удаление через параметры Windows после «Выхода» сохраняет проекты и настройки. Пакеты кандидата не подписаны. Чистая VM, upgrade/uninstall и реальный вход в Windows остаются обязательными проверками перед stable.

## ZH

目标：Windows 11 x64、AhaKey X1 / CH582M、固件 1.4.8、协议 3.2。不需要更新固件，软件包不包含 HEX 或 WCH 组件。

先将 SHA-256 与 SHA256SUMS.txt 比较。完成设备操作并从托盘退出 Studio 后，为当前用户运行 MSI；软件包内含 .NET。2.0.0 MSI 的内部版本 2.0.101 高于 alpha.9 的 2.0.90，用户数据保存在 `%LOCALAPPDATA%/AhaKey/Studio2`。项目导出仅保存草稿，并非完整设备备份。

将 portable ZIP 解压到固定目录。安装版与便携版共享当前用户数据和单实例控制。开机启动、物理集成、配置切换和语音动作均需明确启用。关闭窗口会隐藏到托盘；通过托盘重新打开或退出。退出后在 Windows 设置中卸载，项目和设置保留。候选包未签名；正式发布前仍需完成干净虚拟机安装、升级、卸载以及真实 Windows 登录测试。
