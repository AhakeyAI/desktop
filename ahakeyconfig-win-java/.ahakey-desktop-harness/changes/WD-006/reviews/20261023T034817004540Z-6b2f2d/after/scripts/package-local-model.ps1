<# Builds only into a new directory. Never installs, starts the app, or stops processes. #>
param(
    [Parameter(Mandatory=$true)][string]$SourceRoot,
    [Parameter(Mandatory=$true)][string]$OutputRoot,
    [Parameter(Mandatory=$true)][string]$ModelRoot,
    [Parameter(Mandatory=$true)][string]$NativeJar,
    [Parameter(Mandatory=$true)][string]$MavenRepository,
    [Parameter(Mandatory=$true)][string]$BleDriver,
    [Parameter(Mandatory=$true)][string]$SherpaLicense,
    [string]$JdkRoot = 'D:\jdk-17.0.19.10-hotspot',
    [string]$Maven = 'C:\Program Files\apache-maven-3.9.12\bin\mvn.cmd',
    [string]$WixRoot = 'C:\Program Files (x86)\WiX Toolset v3.14\bin'
)
$ErrorActionPreference = 'Stop'
$SourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
$ModelRoot = (Resolve-Path -LiteralPath $ModelRoot).Path
$NativeJar = (Resolve-Path -LiteralPath $NativeJar).Path
$MavenRepository = (Resolve-Path -LiteralPath $MavenRepository).Path
$BleDriver = (Resolve-Path -LiteralPath $BleDriver).Path
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
    Copy-Item -LiteralPath $BleDriver -Destination (Join-Path $inputDir 'BLE_tcp_driver.exe')
    if (Test-Path -LiteralPath ($BleDriver + '.config')) {
        Copy-Item -LiteralPath ($BleDriver + '.config') -Destination $inputDir
    }
    $models = Join-Path $inputDir 'models'
    New-Item -ItemType Directory -Path $models | Out-Null
    foreach ($name in $expectedModels.Keys) { Copy-Item -LiteralPath (Join-Path $ModelRoot $name) -Destination $models }
    Copy-Item -LiteralPath (Join-Path $ModelRoot 'README.md') -Destination (Join-Path $models 'UPSTREAM-README.md')
    Copy-Item -LiteralPath $SherpaLicense -Destination (Join-Path $inputDir 'Sherpa-ONNX-LICENSE.txt')
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
    $runtime = Join-Path $OutputRoot 'runtime'
    & "$JdkRoot/bin/jlink.exe" --add-modules java.base,java.desktop,java.logging,java.sql,java.naming,java.xml,java.net.http,java.management,jdk.unsupported,jdk.crypto.ec,jdk.zipfs --output $runtime --strip-debug --no-header-files --no-man-pages --compress=2
    if ($LASTEXITCODE -ne 0) { throw "jlink failed: $LASTEXITCODE" }
    $imageDest = Join-Path $OutputRoot 'image'
    & "$JdkRoot/bin/jpackage.exe" --type app-image --name AhaKeyStudio --app-version 1.0.6 --vendor AhaKey --description 'AhaKey Studio WD-006 Local Model Preview' --input $inputDir --main-jar $jarName --main-class com.example.ahakey.Main --dest $imageDest --runtime-image $runtime --icon (Join-Path $SourceRoot 'VibeCodeKeyboard.ico') --java-options '-Dfile.encoding=UTF-8'
    if ($LASTEXITCODE -ne 0) { throw "app-image failed: $LASTEXITCODE" }
    $appImage = Join-Path $imageDest 'AhaKeyStudio'
    $launcher = Get-Content -LiteralPath (Join-Path $appImage 'app/AhaKeyStudio.cfg') -Raw
    if ($launcher -notmatch 'sherpa-onnx-java-api-1.13.3.jar' -or $launcher -notmatch 'sherpa-onnx-native-lib-win-x64-v1.13.3.jar') {
        throw 'Launcher classpath does not include both Sherpa artifacts.'
    }
    $installer = Join-Path $OutputRoot 'installer'
    & "$JdkRoot/bin/jpackage.exe" --type exe --name AhaKeyStudio --app-version 1.0.6 --vendor AhaKey --description 'AhaKey Studio WD-006 Local Model Preview' --app-image $appImage --dest $installer --win-dir-chooser --win-menu --win-menu-group AhaKey --win-shortcut
    if ($LASTEXITCODE -ne 0) { throw "installer failed: $LASTEXITCODE" }
    $inventory = Get-ChildItem -LiteralPath $appImage -File -Recurse | ForEach-Object {
        @{ path = $_.FullName.Substring($appImage.Length + 1); bytes = $_.Length; sha256 = (Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant() }
    }
    @{ variant='model-bundled'; scope='OWNER_PREVIEW_ONLY_NOT_FORMAL_UAT'; source=$SourceRoot; model_revision='8e40c43232a1c5c66c82111efc5820d3accca11b'; files=@($inventory); installer=@(Get-ChildItem -LiteralPath $installer -Filter '*.exe' | ForEach-Object { @{path=$_.FullName; bytes=$_.Length; sha256=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()} }) } |
        ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $OutputRoot 'PACKAGE_IDENTITY.json')
} finally {
    $env:JAVA_HOME = $oldJavaHome
    $env:PATH = $oldPath
    Stop-Transcript | Out-Null
}
