param([Parameter(Mandatory=$true)][string]$OutputDirectory,[Parameter(Mandatory=$true)][string]$DtfRoot,[switch]$StaticOnly,[string]$JdkRoot='D:\jdk-17.0.19.10-hotspot',[string]$WixRoot='C:\Program Files (x86)\WiX Toolset v3.14\bin')
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $OutputDirectory){throw 'Test output must be new'}
New-Item -ItemType Directory -Path $OutputDirectory|Out-Null
$OutputDirectory=(Resolve-Path -LiteralPath $OutputDirectory).Path
$sourceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Start-Transcript -Path (Join-Path $OutputDirectory 'checks.log')|Out-Null
try {
    $shared=Join-Path $sourceRoot 'src/main/resources/update/InstalledApplication.cs'
    $exe=Join-Path $OutputDirectory 'checks.exe'
    & "$env:SystemRoot/Microsoft.NET/Framework64/v4.0.30319/csc.exe" /nologo /target:exe /codepage:65001 "/out:$exe" $shared (Join-Path $PSScriptRoot 'tests/InstalledApplicationChecks.cs')
    if($LASTEXITCODE -ne 0){throw 'Checks compilation failed'}
    & $exe;if($LASTEXITCODE -ne 0){throw 'Installed instance behavior checks failed'}
    Add-Type -Path $shared
    $captured=Join-Path $OutputDirectory 'captured-arguments.txt'
    $expected=@('/passive','/norestart','AHAKEY_SOURCE_DIR=D:\我的 软件 (A)&B\AhaKey\','AHAKEY_SOURCE_PRODUCT={11111111-1111-4111-8111-111111111111}')
    $arguments=@('--echo',$captured)+$expected
    $line=($arguments|ForEach-Object{[AhaKey.Installation.InstalledApplication]::Quote($_)}) -join ' '
    $p=Start-Process -FilePath $exe -WindowStyle Hidden -PassThru -ArgumentList $line;$p.WaitForExit()
    if($p.ExitCode -ne 0){throw 'Argument capture failed'}
    $actual=[IO.File]::ReadAllLines($captured)
    if(($actual -join "`n") -cne ($expected -join "`n")){throw 'Start-Process argument roundtrip failed'}
    Write-Output 'PASS actual Start-Process argv roundtrip with Unicode, spaces, punctuation and trailing backslash'
    $resources=Join-Path $OutputDirectory 'resources'
    & (Join-Path $PSScriptRoot 'prepare-upgrade-resources.ps1') -SourceRoot $sourceRoot -OutputDirectory $resources -ProductCode '20a91011-f263-47fa-a2dd-546b61af043c' -BuildId ('a'*64) -DtfRoot $DtfRoot -JdkRoot $JdkRoot -WixRoot $WixRoot
    # Tiny MSI fixture validates linking/sequences only. It is never executed and is not a deliverable package.
    [IO.File]::WriteAllText((Join-Path $OutputDirectory 'fixture.txt'),'NON-INSTALLABLE TEST PAYLOAD')
    [IO.File]::WriteAllText((Join-Path $resources 'overrides.wxi'),'<Include/>')
    $payload=[Security.SecurityElement]::Escape((Join-Path $OutputDirectory 'fixture.txt'))
    $fixture=@"
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi"><Fragment>
 <DirectoryRef Id="TARGETDIR"><Directory Id="ProgramFiles64Folder"><Directory Id="INSTALLDIR" Name="AhaKeyFixture"><Component Id="Payload" Guid="*" Win64="yes"><File Id="PayloadFile" Source="$payload" KeyPath="yes"/></Component></Directory></Directory></DirectoryRef>
 <ComponentGroup Id="Files"><ComponentRef Id="Payload"/></ComponentGroup><ComponentGroup Id="Shortcuts"/><ComponentGroup Id="FileAssociations"/>
 <Property Id="WIXUI_INSTALLDIR" Value="INSTALLDIR"/><UI Id="JpUI"><UIRef Id="WixUI_InstallDir"/><Publish Dialog="WelcomeDlg" Control="Next" Event="NewDialog" Value="InstallDirDlg" Order="6">NOT Installed</Publish></UI>
</Fragment></Wix>
"@
    [IO.File]::WriteAllText((Join-Path $OutputDirectory 'fixture.wxs'),$fixture)
    $loc='<WixLocalization Culture="en-us" xmlns="http://schemas.microsoft.com/wix/2006/localization"><String Id="MainFeatureTitle">AhaKey</String><String Id="DisallowUpgradeErrorMessage">No upgrade</String><String Id="DowngradeErrorMessage">No downgrade</String></WixLocalization>'
    [IO.File]::WriteAllText((Join-Path $OutputDirectory 'fixture.wxl'),$loc)
    $defines=@('-dJpIsSystemWide=yes','-dJpAllowUpgrades=yes','-dJpAllowDowngrades=yes',"-dJpConfigDir=$resources",'-dJpProductUpgradeCode=03E5A934-FFCA-3815-B455-7D49BF1CA1DC','-dJpAppName=AhaKeyStudio','-dJpAppVersion=1.0.11','-dJpAppVendor=AhaKey','-dJpAppDescription=Fixture','-dJpAppSizeKb=1')
    & "$WixRoot/candle.exe" -nologo -arch x64 -ext WixUtilExtension @defines -out "$OutputDirectory\" (Join-Path $resources 'main.wxs') (Join-Path $OutputDirectory 'fixture.wxs')
    if($LASTEXITCODE -ne 0){throw 'Fixture candle failed'}
    # StaticOnly avoids Windows Installer ICE execution; table assertions below still run.
    $validationArgs=@();if($StaticOnly){$validationArgs=@('-sval');Write-Output 'ICE execution skipped: static-only validation'}
    & "$WixRoot/light.exe" -nologo @validationArgs -ext WixUIExtension -ext WixUtilExtension -loc (Join-Path $OutputDirectory 'fixture.wxl') -out (Join-Path $OutputDirectory 'fixture.msi') (Join-Path $OutputDirectory 'main.wixobj') (Join-Path $OutputDirectory 'fixture.wixobj')
    if($LASTEXITCODE -ne 0){throw 'Fixture light failed'}
    & (Join-Path $PSScriptRoot 'verify-installer-structure.ps1') -Msi (Join-Path $OutputDirectory 'fixture.msi') -Inputs (Join-Path $resources 'INSTALLER_INPUTS.json') -Output (Join-Path $OutputDirectory 'structure.json') -MinimalFixture
    Write-Output 'PASS linked actual fixture MSI structure (not an installation or rollback test)'
} finally {Stop-Transcript|Out-Null}
