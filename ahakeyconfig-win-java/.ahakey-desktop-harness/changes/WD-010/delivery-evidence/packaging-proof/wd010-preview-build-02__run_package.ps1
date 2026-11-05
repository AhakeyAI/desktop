$ErrorActionPreference='Stop'
$taskRoot='C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java'
$inputs=Get-Content -LiteralPath "$taskRoot/target/wd010-preview-build-02/SOURCE_INPUTS.json" -Raw | ConvertFrom-Json
$command=@{
 SourceRoot=$inputs.derived_source
 OutputRoot="$taskRoot/target/WD010-Preview-R3-LocalModel-1.0.21"
 ModelRoot="$taskRoot/target/wd006-dependencies/verified-models"
 NativeJar="$taskRoot/target/wd006-dependencies/sherpa-onnx-native-lib-win-x64-v1.13.3.jar"
 MavenRepository="$taskRoot/.m2repo"
 BleDriver="$taskRoot/target/wd009-bridge-r2-build-02/bin/BLE_tcp_driver.exe"
 BleDriverManifest="$taskRoot/target/wd009-bridge-r2-build-02/BRIDGE_BUILD_MANIFEST.json"
 SherpaLicense="$taskRoot/target/wd006-dependencies/Sherpa-ONNX-LICENSE.txt"
 AppVersion='1.0.21'
 DtfRoot="$taskRoot/target/wd006-dependencies/wix-dtf-5.0.2"
 ProductCode=$inputs.product_code
 InstallerType='exe'
}
$command | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$taskRoot/target/wd010-preview-build-02/COMMAND.json" -Encoding utf8
$env:TEMP='D:\ahakey-wd010-preview-r3-20261105-temp'
$env:TMP=$env:TEMP
New-Item -ItemType Directory -Force -Path $env:TEMP | Out-Null
$exitCode=0
try { & "$($inputs.derived_source)/scripts/package-local-model.ps1" @command *> "$taskRoot/target/wd010-preview-build-02/package.log" }
catch { $_ | Out-String | Add-Content -LiteralPath "$taskRoot/target/wd010-preview-build-02/package.log"; $exitCode=1 }
$exitCode | Set-Content -LiteralPath "$taskRoot/target/wd010-preview-build-02/package-exit.txt"
exit $exitCode
