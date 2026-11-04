# R10 当前安装只读观察

2026-10-25，DLA 仅通过指定 Windows 卸载注册表项与 Get-Process 读取。未执行 Win32_Product（避免触发修复），未写注册表/安装/关闭进程。

- HKLM/SOFTWARE/Microsoft/Windows/CurrentVersion/Uninstall 下 AhaKeyStudio。
- ProductCode `{F4E20CB3-81B5-3C96-9D6B-60AF0D70A960}`，与 R9 1.0.11 已交付 MSI 一致。
- DisplayVersion `1.0.11`；Publisher `AhaKey`。
- InstallLocation `D:\ahakey\`。
- 两个名为 AhaKeyStudio 的进程均报告路径 `D:\ahakey\AhaKeyStudio.exe`（PID39928、57716）。仅观察，不把启动器/子进程数量直接当作两个安装实例，不 kill。

这直接支持 Owner 的原目录保留需求。新 R10 1.0.11 手动 bootstrap 和1.0.12 OTA 都必须保留这个已注册目录；不能假设 Program Files。运行中的应用在 Owner 实际安装前由 Owner 正常退出，机器验证不干预它。
