param([Parameter(Mandatory=$true)][string]$AppImage,[Parameter(Mandatory=$true)][string]$Installer,
      [Parameter(Mandatory=$true)][string]$ExpectedVersion,[Parameter(Mandatory=$true)][string]$OutputDirectory,
      [Parameter(Mandatory=$true)][string]$InstallerInputs)
$ErrorActionPreference='Stop'
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Verification output must be new.' }
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
foreach($name in @('DTF-LICENSE.txt','DTF-NOTICE.txt','dtf-toolchain.json')) {
    $expectedNotice=Join-Path $PSScriptRoot ('installer/'+$name)
    $actualNotice=Join-Path $AppImage ('app/licenses/WiX-DTF-5.0.2/'+$name)
    if((Get-FileHash -LiteralPath $actualNotice -Algorithm SHA256).Hash -cne (Get-FileHash -LiteralPath $expectedNotice -Algorithm SHA256).Hash){throw ('DTF notice mismatch: '+$name)}
}
$jar=Join-Path $AppImage 'app/ahakey-studio-1.0.0.jar'
$zip=[IO.Compression.ZipFile]::OpenRead($jar)
try {
    $required=@('update/app-release.properties','update/release-public-key.json','update/windows-update-worker.ps1','update/InstalledApplication.cs',
        'firmware/wch-capture-worker.ps1','firmware/wch-driver-worker.ps1','firmware/catalog.json','firmware/wch-runtime-profiles.json')
    foreach($name in $required) {
        $entry=$zip.GetEntry($name); if(-not $entry) { throw "Missing resource: $name" }
        $file=Join-Path $OutputDirectory ([IO.Path]::GetFileName($name))
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$file)
    }
    $catalog=Get-Content -LiteralPath (Join-Path $OutputDirectory 'catalog.json') -Raw | ConvertFrom-Json
    foreach($firmware in $catalog.entries){
        if($firmware.resource -match '[/\\:]|\.\.'){throw 'Unsafe bundled firmware resource'}
        $entry=$zip.GetEntry('firmware/'+$firmware.resource);if(-not $entry){throw 'Bundled firmware resource missing'}
        $file=Join-Path $OutputDirectory $firmware.resource;[IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$file)
        if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ine $firmware.sha256){throw 'Bundled catalog HEX hash mismatch'}
    }
} finally { $zip.Dispose() }
$metadata=Get-Content -LiteralPath (Join-Path $OutputDirectory 'app-release.properties') -Raw
foreach($line in @("version=$ExpectedVersion",'variant=local-model','arch=x64','productId=AhaKeyStudio','upgradeCode={03E5A934-FFCA-3815-B455-7D49BF1CA1DC}','installed=true')) {
    if(-not ($metadata -split '\r?\n' -contains $line)) { throw "Incorrect metadata: $line" }
}
foreach($name in @('encoder.int8.onnx','decoder.int8.onnx','tokens.txt')) { if(-not (Test-Path -LiteralPath (Join-Path $AppImage "app/models/$name"))) { throw "Missing model $name" } }
$profile=Get-Content -LiteralPath (Join-Path $OutputDirectory 'wch-runtime-profiles.json') -Raw | ConvertFrom-Json
if($profile.schema -ne 2 -or @($profile.files.PSObject.Properties).Count -ne 6 -or @($profile.drivers.PSObject.Properties).Count -ne 7){throw 'Incomplete WCH bundle profile'}
$bundled=@()
foreach($group in @(@{entries=$profile.files;directory='app/tools/wchisp'},@{entries=$profile.drivers;directory='app/drivers/wch-ch375'})){
    $dir=Join-Path $AppImage $group.directory
    if(@(Get-ChildItem -LiteralPath $dir -Recurse -File).Count -ne @($group.entries.PSObject.Properties).Count){throw 'Unexpected WCH bundle files'}
    foreach($entry in $group.entries.PSObject.Properties){
        if($entry.Name -match '(^[/\\]|\.\.|:)'){throw 'Unsafe WCH bundle path'}
        $file=Join-Path $dir $entry.Name
        if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ine $entry.Value){throw ('WCH bundle mismatch: '+$entry.Name)}
        $bundled+=@{path=($group.directory+'/'+$entry.Name);sha256=$entry.Value;bytes=(Get-Item -LiteralPath $file).Length}
    }
}
$public=Get-Content -LiteralPath (Join-Path $OutputDirectory 'release-public-key.json') -Raw | ConvertFrom-Json
$worker=Get-Content -LiteralPath (Join-Path $OutputDirectory 'windows-update-worker.ps1') -Raw
if($public.schema -ne 1 -or $public.exponent -cne 'AQAB' -or -not $worker.Contains($public.modulus)){throw 'Java and worker fixed public keys differ'}
foreach($script in @('windows-update-worker.ps1','wch-capture-worker.ps1','wch-driver-worker.ps1')) {
    $errors=$null;$tokens=$null
    [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $OutputDirectory $script),[ref]$tokens,[ref]$errors)
    if($errors.Count) { throw ($errors | Out-String) }
}
$inspection=Join-Path $OutputDirectory 'actual-installer.json'
& (Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe') -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $OutputDirectory 'windows-update-worker.ps1') -Mode Inspect -Executable $Installer -Result $inspection
if($LASTEXITCODE -ne 0) { throw 'Actual installer read-only inspection failed' }
$identity=Get-Content -LiteralPath $inspection -Raw | ConvertFrom-Json
if($identity.productName -ne 'AhaKeyStudio' -or $identity.version -ne $ExpectedVersion -or $identity.variant -ne 'local-model' -or $identity.arch -ne 'x64' -or $identity.upgradeCode -ine '{03E5A934-FFCA-3815-B455-7D49BF1CA1DC}') { throw 'Actual MSI/metadata mismatch' }
if(-not ($metadata -split '\r?\n' -contains ('buildId='+$identity.buildId)) -or $identity.buildId -notmatch '^[a-f0-9]{64}$'){throw 'JAR and actual MSI build identity differ'}
Add-Type -Path (Join-Path $OutputDirectory 'InstalledApplication.cs')
$actualMsi=Join-Path $OutputDirectory 'actual-installer.msi'
[IO.File]::WriteAllBytes($actualMsi,[AhaKey.Installation.InstalledApplication]::Resource([IO.Path]::GetFullPath($Installer),'MSI'))
$wrapperCode=[Text.Encoding]::UTF8.GetString([AhaKey.Installation.InstalledApplication]::Resource([IO.Path]::GetFullPath($Installer),'product_code')).Trim([char]0)
if(([Guid]$wrapperCode) -ne ([Guid]$identity.productCode)){throw 'EXE wrapper and MSI ProductCode differ'}
& (Join-Path $PSScriptRoot 'installer/verify-installer-structure.ps1') -Msi $actualMsi -Inputs $InstallerInputs -Output (Join-Path $OutputDirectory 'actual-msi-structure.json')
$signatureFile=Join-Path $OutputDirectory 'worker-release-signature.json'
& (Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe') -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $OutputDirectory 'windows-update-worker.ps1') -Mode VerifyRelease -Executable $Installer -Result $signatureFile
if($LASTEXITCODE -ne 0){throw 'Packaged worker rejected final release signature'}
$javaFile=Join-Path $OutputDirectory 'java-release-signature.json'
& (Join-Path $AppImage 'runtime/bin/java.exe') '-Dfile.encoding=UTF-8' -cp ($jar+';'+(Join-Path $AppImage 'app/lib/*')) com.example.ahakey.update.ReleaseSignature $Installer | Set-Content -LiteralPath $javaFile -Encoding UTF8
if($LASTEXITCODE -ne 0){throw 'Packaged Java rejected final release signature'}
foreach($file in @($signatureFile,$javaFile)) {
    $signature=Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach($property in @('version','variant','arch','upgradeCode','productCode')){if($signature.$property -cne $identity.$property){throw ('Signed identity differs from actual MSI: '+$property)}}
    if($signature.productId -cne $identity.productName){throw 'Signed product identity differs from actual MSI'}
}
@{scope='package-content-and-signature-only-not-install-or-device-test';installer_sha256=(Get-FileHash -LiteralPath $Installer).Hash.ToLowerInvariant();identity=$identity;resources=@($required);wch=$bundled} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'result.json') -Encoding UTF8
