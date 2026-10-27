param([Parameter(Mandatory=$true)][string]$SourceRoot,[Parameter(Mandatory=$true)][string]$OutputDirectory,
      [Parameter(Mandatory=$true)][Guid]$ProductCode,[Parameter(Mandatory=$true)][string]$BuildId,
      [Parameter(Mandatory=$true)][string]$DtfRoot,
      [string]$JdkRoot='D:\jdk-17.0.19.10-hotspot',[string]$WixRoot='C:\Program Files (x86)\WiX Toolset v3.14\bin')
$ErrorActionPreference='Stop'
if($BuildId -notmatch '^[a-f0-9]{64}$'){throw 'Invalid build identity'}
$toolchain=& (Join-Path $PSScriptRoot 'resolve-dtf-toolchain.ps1') -DtfRoot $DtfRoot
if(Test-Path -LiteralPath $OutputDirectory){throw 'Installer resources require a new directory'}
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
$OutputDirectory=(Resolve-Path -LiteralPath $OutputDirectory).Path
$csc=Join-Path $env:SystemRoot 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
$shared=Join-Path $SourceRoot 'src/main/resources/update/InstalledApplication.cs'
$adapter=Join-Path $PSScriptRoot 'InstalledApplicationActions.cs'
$dtf=$toolchain.Runtime
$assembly=Join-Path $OutputDirectory 'AhaKey.Installation.dll'
& $csc /nologo /target:library /platform:x64 /codepage:65001 "/out:$assembly" "/reference:$dtf" $shared $adapter
if($LASTEXITCODE -ne 0){throw 'Installation custom action compilation failed'}
$binary=Join-Path $OutputDirectory 'AhaKey.Installation.CA.dll'
& $toolchain.Packager $binary $toolchain.Stub $assembly $dtf (Join-Path $PSScriptRoot 'CustomAction.config')
if($LASTEXITCODE -ne 0){throw 'Installation custom action packaging failed'}
Push-Location $OutputDirectory
try {& "$JdkRoot/bin/jar.exe" xf "$JdkRoot/jmods/jdk.jpackage.jmod" classes/jdk/jpackage/internal/resources/main.wxs;if($LASTEXITCODE -ne 0){throw 'Cannot read fixed JDK template'}}finally{Pop-Location}
$template=Get-Content -LiteralPath (Join-Path $OutputDirectory 'classes/jdk/jpackage/internal/resources/main.wxs') -Raw
function Replace-Once([string]$Old,[string]$New) {
    if(([regex]::Matches($script:template,[regex]::Escape($Old))).Count -ne 1){throw "Unsupported installer template anchor: $Old"}
    $script:template=$script:template.Replace($Old,$New)
}
Replace-Once 'Id="$(var.JpProductCode)"' ('Id="'+$ProductCode.ToString('B').ToUpperInvariant()+'"')
Replace-Once 'OnlyDetect="$(var.JpUpgradeVersionOnlyDetectUpgrade)"' 'OnlyDetect="no"'
Replace-Once 'IncludeMaximum="$(var.JpUpgradeVersionOnlyDetectUpgrade)"' 'IncludeMaximum="yes"'
Replace-Once 'OnlyDetect="$(var.JpUpgradeVersionOnlyDetectDowngrade)"' 'OnlyDetect="yes"'
Replace-Once 'IncludeMinimum="$(var.JpUpgradeVersionOnlyDetectDowngrade)"' 'IncludeMinimum="no"'
Replace-Once '<RemoveExistingProducts Before="CostInitialize"/>' '<RemoveExistingProducts After="InstallInitialize"/>'
$escaped=[Security.SecurityElement]::Escape($binary)
$extra=@"
<Property Id="AHAKEY_VARIANT" Value="local-model"/><Property Id="AHAKEY_ARCH" Value="x64"/>
<Property Id="AHAKEY_BUILD_ID" Value="$BuildId"/><Property Id="REBOOT" Value="ReallySuppress"/>
<Property Id="AHAKEY_OTA" Secure="yes"/><Property Id="AHAKEY_SOURCE_PRODUCT" Secure="yes"/>
<Property Id="AHAKEY_SOURCE_DIR" Secure="yes"/><Property Id="AHAKEY_SOURCE_VERSION" Secure="yes"/>
<Property Id="AHAKEY_SOURCE_MSI" Secure="yes"/>
<Property Id="AHAKEY_INITIAL_SOURCE" Secure="yes"/>
<Binary Id="AhaKeyInstallationCA" SourceFile="$escaped"/>
<CustomAction Id="AhaKeyResolveInstalled" BinaryKey="AhaKeyInstallationCA" DllEntry="ResolveInstalledApplication" Execute="immediate" Return="check"/>
<CustomAction Id="AhaKeyVerifyInstalled" BinaryKey="AhaKeyInstallationCA" DllEntry="VerifyInstalledApplication" Execute="immediate" Return="check"/>
<CustomAction Id="AhaKeyBlockDowngrade" Error="A newer AhaKeyStudio is installed. Downgrade is not allowed."/>
<InstallUISequence>
 <Custom Action="AhaKeyBlockDowngrade" After="FindRelatedProducts">JP_DOWNGRADABLE_FOUND AND NOT Installed</Custom>
 <Custom Action="AhaKeyResolveInstalled" Before="CostInitialize">NOT REMOVE~="ALL"</Custom>
 <Custom Action="AhaKeyVerifyInstalled" Before="ExecuteAction">NOT REMOVE~="ALL"</Custom>
</InstallUISequence>
"@
Replace-Once '<Media Id="1"' ($extra+'<Media Id="1"')
Replace-Once '<InstallExecuteSequence>' @'
<InstallExecuteSequence>
 <Custom Action="AhaKeyBlockDowngrade" After="FindRelatedProducts">JP_DOWNGRADABLE_FOUND AND NOT Installed</Custom>
 <Custom Action="AhaKeyResolveInstalled" Before="CostInitialize">NOT REMOVE~="ALL"</Custom>
 <Custom Action="AhaKeyVerifyInstalled" Before="InstallValidate">NOT REMOVE~="ALL"</Custom>
'@
$ui=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'AhaKeyUpgradeUI.wxs') -Raw
$ui=[regex]::Match($ui,'(?s)<Include[^>]*>(.*)</Include>').Groups[1].Value
if(-not $ui){throw 'Missing upgrade UI fragment'}
Replace-Once '<UIRef Id="JpUI"/>' ('<UIRef Id="JpUI"/>'+$ui)
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'main.wxs'),$template,[Text.UTF8Encoding]::new($false))
$inputs=@($shared,$adapter,(Join-Path $PSScriptRoot 'CustomAction.config'),(Join-Path $PSScriptRoot 'AhaKeyUpgradeUI.wxs'),$PSCommandPath,$csc)
@{productCode=$ProductCode.ToString('B').ToUpperInvariant();buildId=$BuildId;customActionSha256=(Get-FileHash -LiteralPath $binary).Hash.ToLowerInvariant();dtf=$toolchain.Provenance;inputs=@($inputs|ForEach-Object{@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash.ToLowerInvariant()}})}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $OutputDirectory 'INSTALLER_INPUTS.json') -Encoding UTF8
