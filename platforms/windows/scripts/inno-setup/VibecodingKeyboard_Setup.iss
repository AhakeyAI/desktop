#define AppName "Vibecoding Keyboard"
#define AppVersion "1.3.0"
#define AppPublisher "Nanjing Jinxinwan Technology Co., Ltd."
#define AppExeName "KeyboardConfig.exe"
#define BleExeName "BLE_tcp_driver.exe"
#define HookExeName "hook_install.exe"
#define SourceRoot "D:\实习-键盘\windows软件打包\windows软件打包\all_in_one"
#define SetupIcon "D:\实习-键盘\windows软件打包\windows软件打包\vibe_code_config_tool-master\vibe_code_config_tool-master\ico\VibeCodeKeyboard.ico"

[Setup]
AppId={{3B782A84-4F88-4F63-98EF-BE03E7708D53}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf64}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=D:\实习-键盘\windows软件打包\windows软件打包
OutputBaseFilename=VibecodingKeyboard_Setup
Compression=lzma2/fast
SolidCompression=no
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
UninstallDisplayIcon={app}\{#AppExeName}
SetupIconFile={#SetupIcon}
VersionInfoVersion={#AppVersion}
VersionInfoCompany={#AppPublisher}
VersionInfoDescription={#AppName} Setup
WizardSizePercent=105
ShowLanguageDialog=yes
UsePreviousLanguage=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:DesktopIconTask}"; GroupDescription: "{cm:AdditionalTasksGroup}"
Name: "installvcredist"; Description: "{cm:InstallVCRedistTask}"; GroupDescription: "{cm:AdditionalTasksGroup}"

[Dirs]
Name: "{app}"; Permissions: users-modify

[Files]
Source: "{#SourceRoot}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "Capswriter\logs\*"

[Icons]
Name: "{autoprograms}\{#AppName}\{cm:KeyboardConfigShortcut}"; Filename: "{app}\{#AppExeName}"
Name: "{autoprograms}\{#AppName}\{cm:BleDriverShortcut}"; Filename: "{app}\{#BleExeName}"
Name: "{autoprograms}\{#AppName}\{cm:HookInstallerShortcut}"; Filename: "{app}\{#HookExeName}"
Name: "{autoprograms}\{#AppName}\{cm:UninstallShortcut}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\VC_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "{cm:RunVCRedistStatus}"; Flags: runhidden waituntilterminated; Tasks: installvcredist; Check: FileExists(ExpandConstant('{app}\VC_redist.x64.exe'))
Filename: "{app}\{#HookExeName}"; Description: "{cm:RunHookInstaller}"; Flags: nowait postinstall skipifsilent
Filename: "{app}\{#AppExeName}"; Description: "{cm:RunKeyboardConfig}"; Flags: nowait postinstall skipifsilent
Filename: "{app}\{#BleExeName}"; Description: "{cm:RunBleDriver}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: files; Name: "{app}\config_server.json"
Type: filesandordirs; Name: "{app}\Capswriter\log"

[CustomMessages]
english.AdditionalTasksGroup=Additional tasks:
english.DesktopIconTask=Create a desktop shortcut
english.InstallVCRedistTask=Install Visual C++ Redistributable (recommended)
english.KeyboardConfigShortcut=Keyboard Config Tool
english.BleDriverShortcut=BLE TCP Driver
english.HookInstallerShortcut=Hook Installer
english.UninstallShortcut=Uninstall {#AppName}
english.RunVCRedistStatus=Installing Visual C++ Redistributable...
english.RunHookInstaller=Open Hook Installer
english.RunKeyboardConfig=Launch Keyboard Config Tool
english.RunBleDriver=Launch BLE TCP Driver

chinesesimplified.AdditionalTasksGroup=附加任务:
chinesesimplified.DesktopIconTask=创建桌面快捷方式
chinesesimplified.InstallVCRedistTask=安装 Visual C++ 运行库（推荐）
chinesesimplified.KeyboardConfigShortcut=键盘配置工具
chinesesimplified.BleDriverShortcut=蓝牙桥接驱动
chinesesimplified.HookInstallerShortcut=Hook 安装器
chinesesimplified.UninstallShortcut=卸载 {#AppName}
chinesesimplified.RunVCRedistStatus=正在安装 Visual C++ 运行库...
chinesesimplified.RunHookInstaller=打开 Hook 安装器
chinesesimplified.RunKeyboardConfig=启动键盘配置工具
chinesesimplified.RunBleDriver=启动蓝牙桥接驱动
