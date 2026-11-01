param([Parameter(Mandatory=$true)][string]$DtfRoot,[Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $OutputDirectory){throw 'Test output must be new'}
New-Item -ItemType Directory -Path $OutputDirectory|Out-Null
$OutputDirectory=(Resolve-Path -LiteralPath $OutputDirectory).Path
$DtfRoot=(Resolve-Path -LiteralPath $DtfRoot).Path
$resolver=Join-Path $PSScriptRoot '../resolve-dtf-toolchain.ps1'
$results=New-Object 'System.Collections.Generic.List[object]'
function Reject([string]$Name,[string]$Pattern,[scriptblock]$Action) {
    $message=$null
    try{& $Action|Out-Null}catch{$message=$_.Exception.Message}
    if(-not $message -or $message -notmatch $Pattern){throw "Unexpected result for $Name : $message"}
    $results.Add(@{name=$Name;result='PASS';rejection=$message})
}
function Copy-Fixture([string]$Name) {
    $path=Join-Path $OutputDirectory $Name
    Copy-Item -LiteralPath $DtfRoot -Destination $path -Recurse
    return $path
}
$valid=& $resolver -DtfRoot $DtfRoot
if($valid.Version -cne '5.0.2'){throw 'Wrong resolved DTF version'}
$results.Add(@{name='valid pinned archives and extracted inputs';result='PASS';provenance=$valid.Provenance})
$missing=Join-Path $OutputDirectory 'empty'
New-Item -ItemType Directory -Path $missing|Out-Null
Reject 'missing package' 'Missing DTF input' {& $resolver -DtfRoot $missing}
$badArchive=Copy-Fixture 'wrong-archive'
[IO.File]::WriteAllText((Join-Path $badArchive 'wixtoolset.dtf.customaction.5.0.2.nupkg'),'not the pinned version')
Reject 'different archive bytes' 'DTF hash mismatch' {& $resolver -DtfRoot $badArchive}
$badRuntime=Copy-Fixture 'changed-runtime'
[IO.File]::WriteAllText((Join-Path $badRuntime 'wixtoolset.dtf.windowsinstaller/lib/net20/WixToolset.Dtf.WindowsInstaller.dll'),'changed')
Reject 'changed runtime' 'DTF hash mismatch' {& $resolver -DtfRoot $badRuntime}
$badConfig=Copy-Fixture 'changed-config'
[IO.File]::WriteAllText((Join-Path $badConfig 'wixtoolset.dtf.customaction/tools/WixToolset.Dtf.MakeSfxCA.exe.config'),'changed')
Reject 'changed packager configuration' 'DTF hash mismatch' {& $resolver -DtfRoot $badConfig}
$extra=Copy-Fixture 'extra-binary'
[IO.File]::WriteAllText((Join-Path $extra 'wixtoolset.dtf.customaction/tools/Unexpected.dll'),'extra')
Reject 'extra adjacent binary' 'Unexpected DTF package contents' {& $resolver -DtfRoot $extra}
$sourceRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$rejectedOutput=Join-Path $OutputDirectory 'must-not-exist'
Reject 'prepare rejects invalid inputs before compilation' 'DTF hash mismatch' {
    & (Join-Path $PSScriptRoot '../prepare-upgrade-resources.ps1') -SourceRoot $sourceRoot -OutputDirectory $rejectedOutput -ProductCode '20a91011-f263-47fa-a2dd-546b61af043c' -BuildId ('a'*64) -DtfRoot $badRuntime
}
if(Test-Path -LiteralPath $rejectedOutput){throw 'Invalid input created compiler output'}
$results|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $OutputDirectory 'RESULT.json') -Encoding UTF8
Write-Output ('PASS '+$results.Count+' DTF input validation cases; no tool or custom action executed')
