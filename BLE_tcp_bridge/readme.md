### 使用vs .NetFramework开发的 BLE - TCP 桥接

给python写的vibe code 上位机和设备间通信用的

### Interface languages / Языки интерфейса

The bridge embeds English, Russian and Chinese catalogs under `Localization/`.
Studio passes `--language=ru`, `--language=en` or `--language=zh` at launch.
Standalone launch reads `AhaKeySelectedLanguage` from
`~/.ahakey/preferences.properties`, then falls back to the Windows UI language.
Restart the bridge after changing language. Unknown locales use English.
The preference file is read only; wire protocol and diagnostic IDs are unchanged.

```powershell
MSBuild .\BLE_tcp_driver.csproj /restore /p:Configuration=Release
.\tests\Test-Localization.ps1
.\bin\Release\BLE_tcp_driver.exe --language=ru --show
```

Keep each key and its format placeholders present in all three RESX files.
The resources are embedded in the executable; no language DLLs need deployment.
