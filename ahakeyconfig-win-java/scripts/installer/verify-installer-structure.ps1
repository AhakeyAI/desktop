param([Parameter(Mandatory=$true)][string]$Msi,[Parameter(Mandatory=$true)][string]$Inputs,[Parameter(Mandatory=$true)][string]$Output,[switch]$MinimalFixture)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Structure result already exists'}
$expected=Get-Content -LiteralPath $Inputs -Raw -Encoding UTF8|ConvertFrom-Json
if(-not ('AhaKey.Installation.InstalledApplication' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot '../../src/main/resources/update/InstalledApplication.cs')}
$engine=New-Object -ComObject WindowsInstaller.Installer
$db=$engine.OpenDatabase([IO.Path]::GetFullPath($Msi),0)
function Rows([string]$Table,[string[]]$Columns) {
    if($Table -in @('RemoveFile','Registry') -and $Table -notin $script:tableNames){return}
    $names=($Columns|ForEach-Object{'`'+$_+'`'}) -join ','
    try{$view=$db.OpenView('SELECT '+$names+' FROM `'+$Table+'`')}catch{throw ('Cannot query MSI table '+$Table+': '+$_.Exception.Message)}
    try{[void]$view.Execute();while($row=$view.Fetch()){try{$item=@{};for($i=0;$i -lt $Columns.Count;$i++){$item[$Columns[$i]]=$row.StringData($i+1)};$item}finally{[void][Runtime.InteropServices.Marshal]::ReleaseComObject($row)}}}
    finally{[void]$view.Close();[void][Runtime.InteropServices.Marshal]::ReleaseComObject($view)}
}
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
try {
    $script:tableNames=@(Rows _Tables @('Name')|ForEach-Object{$_.Name})
    $properties=@{};Rows Property @('Property','Value')|ForEach-Object{$properties[$_.Property]=$_.Value}
    Require ($properties.ProductCode -ieq $expected.productCode) 'Actual ProductCode differs from recipe'
    Require ($properties.ProductCode -inotmatch 'F4E20CB3-81B5-3C96-9D6B-60AF0D70A960|D9E08382-A828-309D-B592-DC8EC41861EC') 'Old ProductCode reused'
    Require ($properties.AHAKEY_BUILD_ID -ceq $expected.buildId) 'Actual BuildId differs from recipe'
    Require ($properties.UpgradeCode -ieq '{03E5A934-FFCA-3815-B455-7D49BF1CA1DC}') 'Wrong family'
    Require ($properties.ALLUSERS -eq '1' -and $properties.REBOOT -eq 'ReallySuppress') 'Scope/reboot policy changed'
    $upgrade=@(Rows Upgrade @('UpgradeCode','VersionMin','VersionMax','Attributes','ActionProperty'))
    $lower=@($upgrade|Where-Object ActionProperty -eq 'JP_UPGRADABLE_FOUND');$higher=@($upgrade|Where-Object ActionProperty -eq 'JP_DOWNGRADABLE_FOUND')
    Require ($lower.Count -eq 1 -and $higher.Count -eq 1 -and $upgrade.Count -eq 2) 'Unexpected upgrade ranges'
    Require ($lower[0].VersionMax -eq $properties.ProductVersion -and (([int]$lower[0].Attributes -band 512) -ne 0) -and (([int]$lower[0].Attributes -band 2) -eq 0)) 'Same version upgrade range missing'
    Require ($higher[0].VersionMin -eq $properties.ProductVersion -and (([int]$higher[0].Attributes -band 256) -eq 0) -and (([int]$higher[0].Attributes -band 2) -ne 0)) 'Higher-version detection range invalid'
    $execute=@(Rows InstallExecuteSequence @('Action','Condition','Sequence'));$ui=@(Rows InstallUISequence @('Action','Condition','Sequence'))
    foreach($sequence in @($execute,$ui)) {
        $lookup=@{};foreach($row in $sequence){$lookup[$row.Action]=$row}
        Require ([int]$lookup.FindRelatedProducts.Sequence -lt [int]$lookup.AhaKeyResolveInstalled.Sequence -and [int]$lookup.AhaKeyResolveInstalled.Sequence -lt [int]$lookup.CostInitialize.Sequence) 'Directory resolution is not before costing in both sequences'
        Require ($lookup.AhaKeyBlockDowngrade.Condition -match 'JP_DOWNGRADABLE_FOUND') 'Missing downgrade guard'
        Require ($lookup.ContainsKey('AhaKeyVerifyInstalled')) 'Missing independent final directory verification'
    }
    $e=@{};foreach($row in $execute){$e[$row.Action]=$row}
    Require ([int]$e.InstallInitialize.Sequence -lt [int]$e.RemoveExistingProducts.Sequence -and [int]$e.RemoveExistingProducts.Sequence -lt [int]$e.ProcessComponents.Sequence) 'Old removal is outside early transaction window'
    Require ([int]$e.AhaKeyVerifyInstalled.Sequence -lt [int]$e.InstallValidate.Sequence) 'Final check is too late'
    $between=@($execute|Where-Object{[int]$_.Sequence -gt [int]$e.InstallInitialize.Sequence -and [int]$_.Sequence -lt [int]$e.RemoveExistingProducts.Sequence})
    Require ($between.Count -eq 0) 'Unexpected action before old removal in transaction'
    $ca=@(Rows CustomAction @('Action','Type','Source','Target'))
    foreach($name in @('AhaKeyResolveInstalled','AhaKeyVerifyInstalled')){$a=@($ca|Where-Object Action -eq $name);Require ($a.Count -eq 1 -and $a[0].Source -eq 'AhaKeyInstallationCA' -and [int]$a[0].Type -eq 1) 'Directory action is not checked immediate DLL action'}
    $binaryHash=[AhaKey.Installation.InstalledApplication]::BinaryHash([IO.Path]::GetFullPath($Msi),'AhaKeyInstallationCA')
    Require ($binaryHash -ceq $expected.customActionSha256) 'Actual custom action binary differs from compiled input'
    $welcome=@($ui|Where-Object Action -eq 'WelcomeDlg');$exit=@($ui|Where-Object Action -eq 'ExitDialog')
    Require ($welcome.Count -eq 1 -and $welcome[0].Condition -match 'NOT AHAKEY_UPGRADE' -and $exit[0].Condition -match 'NOT AHAKEY_UPGRADE') 'Upgrade still displays first-install dialogs'
    $events=@(Rows ControlEvent @('Dialog_','Control_','Event','Argument','Condition','Ordering'))
    Require (@($events|Where-Object{$_['Dialog_'] -eq 'WelcomeDlg' -and $_.Argument -eq 'InstallDirDlg'}).Count -ge 1) 'First install directory chooser missing'
    $remove=@(Rows RemoveFile @('FileKey','Component_','FileName','DirProperty','InstallMode'))
    $registry=@(Rows Registry @('Registry','Root','Key','Name','Value','Component_'))
    Require (@($remove|Where-Object{$_.DirProperty -match 'AppData|UserProfile|AHAKEY' -or $_.FileName -eq '*'}).Count -eq 0) 'Unexpected user-data cleanup'
    $files=@(Rows File @('File','Component_','FileName'));$components=@(Rows Component @('Component','ComponentId','Directory_','Attributes','KeyPath'))
    $directories=@(Rows Directory @('Directory','Directory_Parent','DefaultDir'))
    if(-not $MinimalFixture) {
        $launcher=@($files|Where-Object{($_.FileName -split '\|')[-1] -eq 'AhaKeyStudio.exe'})
        Require ($launcher.Count -eq 1) 'Launcher file is not unique'
        $component=@($components|Where-Object{$_.Component -eq $launcher[0]['Component_']})
        Require ($component.Count -eq 1 -and $component[0].KeyPath -eq $launcher[0].File -and $component[0]['Directory_'] -eq 'INSTALLDIR') 'Launcher must be the registered component key path at INSTALLDIR'
    }
    Require (@($components|Where-Object{$_['Directory_'] -match 'AppData|UserProfile'}).Count -eq 0) 'User configuration must not be owned by MSI components'
    $recursive=@();if('WixRemoveFolderEx' -in $script:tableNames){$recursive=@(Rows WixRemoveFolderEx @('WixRemoveFolderEx','Component_','Property','InstallMode'))}
    foreach($entry in $recursive) {
        Require ($entry.Property -match '^RM_RF[A-F0-9]+$' -and $entry.InstallMode -eq '2') 'Unexpected recursive cleanup rule'
        Require (@($registry|Where-Object{$_.Name -eq $entry.Property -and $_.Value -eq '[INSTALLDIR]' -and $_.Root -eq '2' -and $_.Key -match '^Software\\AhaKey\\AhaKeyStudio\\'}).Count -eq 1) 'Recursive cleanup must bind only the registered installation directory'
    }
    $summary=$db.SummaryInformation(0)
    try{$platform=$summary.Property(7);$packageCode=$summary.Property(9)}finally{[void][Runtime.InteropServices.Marshal]::ReleaseComObject($summary)}
    Require ($platform -match '^x64;' -and $packageCode -match '^\{[A-Fa-f0-9-]{36}\}$') 'Invalid platform/PackageCode'
    @{scope='actual-msi-structure-not-install-or-rollback';minimalFixture=[bool]$MinimalFixture;properties=$properties;packageCode=$packageCode;upgrade=$upgrade;execute=$execute;ui=$ui;customActions=$ca;customActionSha256=$binaryHash;controlEvents=$events;removeFile=$remove;recursiveRemove=$recursive;registry=$registry;files=$files;components=$components;directories=$directories}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $Output -Encoding UTF8
} finally {[void][Runtime.InteropServices.Marshal]::ReleaseComObject($db);[void][Runtime.InteropServices.Marshal]::ReleaseComObject($engine)}
