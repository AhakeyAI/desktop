<# Builds only into a new directory. Never installs, starts the app, or stops processes. #>
param(
    [Parameter(Mandatory=$true)][string]$SourceRoot,
    [Parameter(Mandatory=$true)][string]$OutputRoot,
    [Parameter(Mandatory=$true)][string]$ModelRoot,
    [Parameter(Mandatory=$true)][string]$NativeJar,
    [Parameter(Mandatory=$true)][string]$MavenRepository,
    [Parameter(Mandatory=$true)][string]$BleDriver,
    [Parameter(Mandatory=$true)][string]$BleDriverManifest,
    [Parameter(Mandatory=$true)][string]$SherpaLicense,
    [Parameter(Mandatory=$true)][string]$AppVersion,
    [Parameter(Mandatory=$true)][string]$DtfRoot,
    [ValidateSet('exe')][string]$InstallerType = 'exe',
    [Guid]$ProductCode = [Guid]::NewGuid(),
    [string]$JdkRoot = 'D:\jdk-17.0.19.10-hotspot',
    [string]$Maven = 'C:\Program Files\apache-maven-3.9.12\bin\mvn.cmd',
    [string]$WixRoot = 'C:\Program Files (x86)\WiX Toolset v3.14\bin'
)
$ErrorActionPreference = 'Stop'
$SourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
$dtfToolchain = & (Join-Path $SourceRoot 'scripts/installer/resolve-dtf-toolchain.ps1') -DtfRoot $DtfRoot
$DtfRoot = $dtfToolchain.Root
$ModelRoot = (Resolve-Path -LiteralPath $ModelRoot).Path
$NativeJar = (Resolve-Path -LiteralPath $NativeJar).Path
$MavenRepository = (Resolve-Path -LiteralPath $MavenRepository).Path
$BleDriver = (Resolve-Path -LiteralPath $BleDriver).Path
$BleDriverManifest = (Resolve-Path -LiteralPath $BleDriverManifest).Path
$SherpaLicense = (Resolve-Path -LiteralPath $SherpaLicense).Path
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
if (Test-Path -LiteralPath $OutputRoot) { throw 'OutputRoot must be a new isolated directory.' }
function Assert-Hash([string]$Path, [string]$Expected) {
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Expected) {
        throw "Unverified input: $Path"
    }
}
$expectedModels = @{
    'encoder.int8.onnx' = '81a70226a8934e6ed92aa1d4fc486b428b5398e2f2619ed4897b7294cab90e9a'
    'decoder.int8.onnx' = 'f3cca9f77bb9d93c8fcbfb63ae617b6b1ee96818df3aa3b151c40658fe38594f'
    'tokens.txt' = '59aba8873a2ed1e122c25fee421e25f283b63290efbde85c1f01a853d83cb6e6'
}
foreach ($name in $expectedModels.Keys) { Assert-Hash (Join-Path $ModelRoot $name) $expectedModels[$name] }
Assert-Hash $NativeJar '560926df020860b1e4549d299ac365eda3715660cc36f41e9c547cb7493302c7'
$api = Join-Path $SourceRoot 'third-party/sherpa-onnx-java-api-1.13.3.jar'
Assert-Hash $api '4a1fabf547d5e3bb5c9b0ddfc767142692cabe658da84f16adfafd519149b082'
$bridge = Get-Content -LiteralPath $BleDriverManifest -Raw | ConvertFrom-Json
if ($bridge.schema_version -ne 1 -or $bridge.build_exit -ne 0 -or $bridge.test_exit -ne 0 -or $null -eq $bridge.regression_exit -or $bridge.regression_exit -ne 0) {
    throw 'A successful isolated bridge build manifest is required.'
}
Assert-Hash $bridge.inputs.path $bridge.inputs.sha256
$bridgeInputs = Get-Content -LiteralPath $bridge.inputs.path -Raw | ConvertFrom-Json
Assert-Hash (Join-Path $SourceRoot 'scripts/ble-driver-fixes.patch') $bridgeInputs.patch.sha256
$bridgeRoot = (Resolve-Path -LiteralPath $bridge.output_root).Path
if ($BleDriver -ne (Join-Path $bridgeRoot 'BLE_tcp_driver.exe')) { throw 'Driver does not match manifest output root.' }
if (-not ($bridge.files | Where-Object { $_.path -eq 'BLE_tcp_driver.exe' -and $_.runtime })) { throw 'Manifest omits driver.' }
foreach ($file in $bridge.files) {
    $path = [IO.Path]::GetFullPath((Join-Path $bridgeRoot $file.path))
    if (-not $path.StartsWith($bridgeRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe bridge manifest path.' }
    Assert-Hash $path $file.sha256
}
New-Item -ItemType Directory -Path $OutputRoot | Out-Null
Start-Transcript -Path (Join-Path $OutputRoot 'build.log') | Out-Null
$oldJavaHome = $env:JAVA_HOME
$oldPath = $env:PATH
try {
    $env:JAVA_HOME = $JdkRoot
    $env:PATH = "$JdkRoot\bin;$WixRoot;$env:PATH"
    Push-Location $SourceRoot
    try {
        & $Maven -o "-Dmaven.repo.local=$MavenRepository" '-DskipTests' package
        if ($LASTEXITCODE -ne 0) { throw "Maven failed: $LASTEXITCODE" }
    } finally { Pop-Location }
    $inputDir = Join-Path $OutputRoot 'input'
    $libDir = Join-Path $inputDir 'lib'
    New-Item -ItemType Directory -Path $libDir | Out-Null
    $jarName = 'ahakey-studio-1.0.0.jar'
    Copy-Item -LiteralPath (Join-Path $SourceRoot "target/$jarName") -Destination $inputDir
    Get-ChildItem -LiteralPath (Join-Path $SourceRoot 'target/lib') -Filter '*.jar' |
        Where-Object { $_.Name -notlike 'onnxruntime*' } | Copy-Item -Destination $libDir
    Copy-Item -LiteralPath $api -Destination $libDir
    Copy-Item -LiteralPath $NativeJar -Destination $libDir
    foreach ($file in $bridge.files | Where-Object { $_.runtime }) {
        $destination = Join-Path $inputDir $file.path
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        Copy-Item -LiteralPath (Join-Path $bridgeRoot $file.path) -Destination $destination
        Assert-Hash $destination $file.sha256
    }
    Copy-Item -LiteralPath $BleDriverManifest -Destination (Join-Path $OutputRoot 'BRIDGE_BUILD_MANIFEST.json')
    Copy-Item -LiteralPath $bridge.inputs.path -Destination (Join-Path $OutputRoot 'BRIDGE_BUILD_INPUTS.json')
    $wchSource=Join-Path $SourceRoot 'src/main/resources/firmware/wch'
    $wchProfile=Get-Content -LiteralPath (Join-Path $SourceRoot 'src/main/resources/firmware/wch-runtime-profiles.json') -Raw | ConvertFrom-Json
    if($wchProfile.schema -ne 2 -or @($wchProfile.files.PSObject.Properties).Count -ne 6 -or @($wchProfile.drivers.PSObject.Properties).Count -ne 7){throw 'Incomplete bundled WCH profile'}
    $wchInventory=@()
    foreach($group in @(@{entries=$wchProfile.files;source=$wchSource;destination='tools/wchisp'},@{entries=$wchProfile.drivers;source=(Join-Path $wchSource 'driver');destination='drivers/wch-ch375'})) {
        foreach($entry in $group.entries.PSObject.Properties) {
            if($entry.Name -match '(^[/\\]|\.\.|:)'){throw 'Unsafe WCH resource path'}
            $source=Join-Path $group.source $entry.Name;$destination=Join-Path (Join-Path $inputDir $group.destination) $entry.Name
            Assert-Hash $source $entry.Value;New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination)|Out-Null
            Copy-Item -LiteralPath $source -Destination $destination;Assert-Hash $destination $entry.Value
            $wchInventory+=@{path=($group.destination+'/'+$entry.Name);bytes=(Get-Item -LiteralPath $destination).Length;sha256=$entry.Value}
        }
    }
    @{profile=$wchProfile.profile;license_evidence=$wchProfile.license_evidence;files=$wchInventory}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $OutputRoot 'WCH_BUNDLE_IDENTITY.json') -Encoding UTF8
    $models = Join-Path $inputDir 'models'
    New-Item -ItemType Directory -Path $models | Out-Null
    foreach ($name in $expectedModels.Keys) { Copy-Item -LiteralPath (Join-Path $ModelRoot $name) -Destination $models }
    Copy-Item -LiteralPath (Join-Path $ModelRoot 'README.md') -Destination (Join-Path $models 'UPSTREAM-README.md')
    Copy-Item -LiteralPath $SherpaLicense -Destination (Join-Path $inputDir 'Sherpa-ONNX-LICENSE.txt')
    $dtfNotices=Join-Path $inputDir 'licenses/WiX-DTF-5.0.2'
    New-Item -ItemType Directory -Path $dtfNotices | Out-Null
    foreach($name in @('DTF-LICENSE.txt','DTF-NOTICE.txt','dtf-toolchain.json')) {
        Copy-Item -LiteralPath (Join-Path $SourceRoot ('scripts/installer/'+$name)) -Destination (Join-Path $dtfNotices $name)
    }
    # Overlay only the staged JAR; the reviewed source remains model-disabled.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::Open((Join-Path $inputDir $jarName), 'Update')
    try {
        $entry = $zip.GetEntry('model_config.properties')
        if ($null -eq $entry) { throw 'Missing model configuration in built JAR.' }
        $reader = [IO.StreamReader]::new($entry.Open())
        try { $config = $reader.ReadToEnd() } finally { $reader.Dispose() }
        if ($config -notmatch '(?m)^model.enabled=false\r?$') { throw 'Expected disabled source configuration.' }
        $entry.Delete()
        $entry = $zip.CreateEntry('model_config.properties')
        $writer = [IO.StreamWriter]::new($entry.Open(), [Text.UTF8Encoding]::new($false))
        try { $writer.Write(($config -replace '(?m)^model.enabled=false', 'model.enabled=true')) } finally { $writer.Dispose() }
    } finally { $zip.Dispose() }
    # Bind installed identity to the staged package, not the development JAR/pom version.
    $buildInputs=@((Get-FileHash -LiteralPath (Join-Path $inputDir $jarName)).Hash,$ProductCode.ToString('B'),$AppVersion)
    $recipeFiles=@($PSCommandPath)+@(Get-ChildItem -LiteralPath (Join-Path $SourceRoot 'scripts/installer') -File -Recurse | Sort-Object FullName | ForEach-Object FullName)
    foreach($recipe in $recipeFiles){$buildInputs+=(Get-FileHash -LiteralPath $recipe).Hash}
    $digest=[Security.Cryptography.SHA256]::Create()
    try{$buildId=([BitConverter]::ToString($digest.ComputeHash([Text.Encoding]::UTF8.GetBytes(($buildInputs -join "`n"))))).Replace('-','').ToLowerInvariant()}finally{$digest.Dispose()}
    $metadata = "version=$AppVersion`nvariant=local-model`narch=x64`nproductId=AhaKeyStudio`nupgradeCode={03E5A934-FFCA-3815-B455-7D49BF1CA1DC}`nbuildId=$buildId`ninstalled=true`n"
    $zip = [IO.Compression.ZipFile]::Open((Join-Path $inputDir $jarName), 'Update')
    try {
        $entry = $zip.GetEntry('update/app-release.properties')
        if ($null -eq $entry) { throw 'Missing update metadata template.' }
        $entry.Delete(); $entry = $zip.CreateEntry('update/app-release.properties')
        $writer = [IO.StreamWriter]::new($entry.Open(), [Text.UTF8Encoding]::new($false))
        try { $writer.Write($metadata) } finally { $writer.Dispose() }
    } finally { $zip.Dispose() }
    $resourceDir = Join-Path $OutputRoot 'jpackage-resources'
    & (Join-Path $SourceRoot 'scripts/installer/prepare-upgrade-resources.ps1') -SourceRoot $SourceRoot -OutputDirectory $resourceDir -ProductCode $ProductCode -BuildId $buildId -DtfRoot $DtfRoot -JdkRoot $JdkRoot -WixRoot $WixRoot
    $runtime = Join-Path $OutputRoot 'runtime' 
    # JavaFX lives on the classpath, so jlink cannot infer its transitive JDK modules.
    $detectedModules = & "$JdkRoot/bin/jdeps.exe" --ignore-missing-deps --multi-release 17 --print-module-deps --class-path "$libDir/*" (Join-Path $inputDir $jarName)
    if ($LASTEXITCODE -ne 0) { throw "Runtime dependency analysis failed: $LASTEXITCODE" }
    $runtimeModules = ((@('java.base','java.desktop','java.logging','java.sql','java.naming','java.xml','java.net.http','java.management','java.scripting','jdk.unsupported','jdk.crypto.ec','jdk.zipfs') + ($detectedModules -split ',')) | Sort-Object -Unique) -join ','
    & "$JdkRoot/bin/jlink.exe" --add-modules $runtimeModules --output $runtime --strip-debug --no-header-files --no-man-pages --compress=2
    if ($LASTEXITCODE -ne 0) { throw "jlink failed: $LASTEXITCODE" }
    $imageDest = Join-Path $OutputRoot 'image'
    & "$JdkRoot/bin/jpackage.exe" --type app-image --name AhaKeyStudio --app-version $AppVersion --vendor AhaKey --description 'AhaKey Studio Local Model' --input $inputDir --main-jar $jarName --main-class com.example.ahakey.Main --dest $imageDest --runtime-image $runtime --icon (Join-Path $SourceRoot 'VibeCodeKeyboard.ico') --java-options '-Dfile.encoding=UTF-8'
    if ($LASTEXITCODE -ne 0) { throw "app-image failed: $LASTEXITCODE" }
    $appImage = Join-Path $imageDest 'AhaKeyStudio'
    $launcher = Get-Content -LiteralPath (Join-Path $appImage 'app/AhaKeyStudio.cfg') -Raw
    if ($launcher -notmatch 'sherpa-onnx-java-api-1.13.3.jar' -or $launcher -notmatch 'sherpa-onnx-native-lib-win-x64-v1.13.3.jar') {
        throw 'Launcher classpath does not include both Sherpa artifacts.'
    }
    $unsignedDirectory = Join-Path $OutputRoot 'unsigned-installer'
    & "$JdkRoot/bin/jpackage.exe" --type $InstallerType --name AhaKeyStudio --app-version $AppVersion --vendor AhaKey --description 'AhaKey Studio Local Model' --app-image $appImage --dest $unsignedDirectory --win-dir-chooser --win-menu --win-menu-group AhaKey --win-shortcut --win-upgrade-uuid 03E5A934-FFCA-3815-B455-7D49BF1CA1DC --resource-dir $resourceDir
    if ($LASTEXITCODE -ne 0) { throw "installer failed: $LASTEXITCODE" }
    $unsigned=@(Get-ChildItem -LiteralPath $unsignedDirectory -Filter '*.exe');if($unsigned.Count -ne 1){throw 'Expected exactly one unsigned EXE'}
    $identityFile=Join-Path $OutputRoot 'unsigned-installer-identity.json'
    $powershell=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
    & $powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $SourceRoot 'src/main/resources/update/windows-update-worker.ps1') -Mode Inspect -Executable $unsigned[0].FullName -Result $identityFile
    if($LASTEXITCODE -ne 0){throw 'Cannot extract actual MSI identity before signing'}
    $actual=Get-Content -LiteralPath $identityFile -Raw | ConvertFrom-Json
    if($actual.version -cne $AppVersion -or $actual.variant -cne 'local-model' -or $actual.arch -cne 'x64' -or $actual.productCode -ine $ProductCode.ToString('B') -or $actual.buildId -cne $buildId){throw 'Unsigned MSI differs from requested build identity'}
    $installer=Join-Path $OutputRoot 'installer';New-Item -ItemType Directory -Path $installer|Out-Null
    $final=Join-Path $installer $unsigned[0].Name
    # Inherit the authorized signing environment, never an isolated application's probe LOCALAPPDATA. No key initialization or rotation here.
    & $powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $SourceRoot 'scripts/sign-release-installer.ps1') -Executable $unsigned[0].FullName -Output $final -IdentityJson $identityFile
    if($LASTEXITCODE -ne 0){throw 'Final EXE signing failed'}
    & (Join-Path $SourceRoot 'scripts/verify-update-package.ps1') -AppImage $appImage -Installer $final -ExpectedVersion $AppVersion -OutputDirectory (Join-Path $OutputRoot 'update-verification') -InstallerInputs (Join-Path $resourceDir 'INSTALLER_INPUTS.json')
    $verified=Get-Content -LiteralPath (Join-Path $OutputRoot 'update-verification/actual-installer.json') -Raw | ConvertFrom-Json
    if($verified.msiSha256 -cne $actual.msiSha256 -or $verified.productCode -cne $actual.productCode){throw 'Signing changed embedded MSI identity or bytes'}
    $inventory = Get-ChildItem -LiteralPath $appImage -File -Recurse | ForEach-Object {
        @{ path = $_.FullName.Substring($appImage.Length + 1); bytes = $_.Length; sha256 = (Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant() }
    }
    @{ variant='local-model'; scope='BUILT_NOT_OWNER_UAT'; source=$SourceRoot; model_revision='8e40c43232a1c5c66c82111efc5820d3accca11b'; files=@($inventory); installer=@(Get-ChildItem -LiteralPath $installer -Filter "*.$InstallerType" | ForEach-Object { @{path=$_.FullName; bytes=$_.Length; sha256=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()} }) } |
        ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $OutputRoot 'PACKAGE_IDENTITY.json')
} finally {
    $env:JAVA_HOME = $oldJavaHome
    $env:PATH = $oldPath
    Stop-Transcript | Out-Null
}
