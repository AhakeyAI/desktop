param([Parameter(Mandatory=$true)][string]$ReferenceImage,[Parameter(Mandatory=$true)][string]$OutputDirectory,[Parameter(Mandatory=$true)][string]$DtfRoot,
      [string]$JdkRoot='D:\jdk-17.0.19.10-hotspot',[string]$WixRoot='C:\Program Files (x86)\WiX Toolset v3.14\bin')
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $OutputDirectory){throw 'Fixture output must be new'}
New-Item -ItemType Directory -Path $OutputDirectory|Out-Null
$OutputDirectory=(Resolve-Path -LiteralPath $OutputDirectory).Path
Start-Transcript -Path (Join-Path $OutputDirectory 'template.log')|Out-Null
$savedPath=$env:PATH
try {
    $env:PATH="$JdkRoot\bin;$WixRoot;$savedPath"
    $root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $image=Join-Path $OutputDirectory 'non-runnable-image'
    New-Item -ItemType Directory -Path (Join-Path $image 'app'),(Join-Path $image 'runtime')|Out-Null
    foreach($relative in @('AhaKeyStudio.exe','app/.jpackage.xml','app/AhaKeyStudio.cfg')) {
        Copy-Item -LiteralPath (Join-Path $ReferenceImage $relative) -Destination (Join-Path $image $relative)
    }
    [IO.File]::WriteAllText((Join-Path $image 'runtime/NON_RUNNABLE_FIXTURE.txt'),'No JVM, JAR, model or device resources. Never execute this fixture installer.')
    $resources=Join-Path $OutputDirectory 'resources'
    & (Join-Path $PSScriptRoot 'prepare-upgrade-resources.ps1') -SourceRoot $root -OutputDirectory $resources -ProductCode '20a91011-f263-47fa-a2dd-546b61af043c' -BuildId ('a'*64) -DtfRoot $DtfRoot -JdkRoot $JdkRoot -WixRoot $WixRoot
    & "$JdkRoot/bin/jpackage.exe" --type exe --name AhaKeyStudio --app-version 1.0.11 --vendor AhaKey --description 'NON RUNNABLE TEMPLATE FIXTURE' --app-image $image --dest (Join-Path $OutputDirectory 'non-deliverable') --temp (Join-Path $OutputDirectory 'jpackage-temp') --win-dir-chooser --win-menu --win-menu-group AhaKey --win-shortcut --win-upgrade-uuid 03E5A934-FFCA-3815-B455-7D49BF1CA1DC --resource-dir $resources
    if($LASTEXITCODE -ne 0){throw 'Actual jpackage template fixture failed'}
    Add-Type -Path (Join-Path $root 'src/main/resources/update/InstalledApplication.cs')
    $exe=Join-Path $OutputDirectory 'non-deliverable/AhaKeyStudio-1.0.11.exe'
    $msi=Join-Path $OutputDirectory 'actual.msi'
    [IO.File]::WriteAllBytes($msi,[AhaKey.Installation.InstalledApplication]::Resource($exe,'MSI'))
    $wrapper=[Text.Encoding]::UTF8.GetString([AhaKey.Installation.InstalledApplication]::Resource($exe,'product_code')).Trim([char]0)
    $product=[AhaKey.Installation.InstalledApplication]::Property($msi,'ProductCode')
    if([Guid]$wrapper -ne [Guid]$product){throw 'Actual jpackage EXE resource does not follow overridden MSI ProductCode'}
    & (Join-Path $PSScriptRoot 'verify-installer-structure.ps1') -Msi $msi -Inputs (Join-Path $resources 'INSTALLER_INPUTS.json') -Output (Join-Path $OutputDirectory 'structure.json')
    @{scope='NON_RUNNABLE_TEMPLATE_FIXTURE_NOT_INSTALLATION_NOT_DELIVERABLE';productCode=$product;wrapperProductCode=$wrapper;exeSha256=(Get-FileHash -LiteralPath $exe).Hash;bytes=(Get-Item -LiteralPath $exe).Length;notExecuted=$true}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $OutputDirectory 'RESULT.json') -Encoding UTF8
    Write-Output 'PASS actual fixed-JDK wrapper ProductCode and generated MSI template; fixture not executed'
} finally {$env:PATH=$savedPath;Stop-Transcript|Out-Null}
