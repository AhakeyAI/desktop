<# Offline build of the approved, read-only bridge inputs into a NEW isolated directory. #>
param(
    [Parameter(Mandatory=$true)][string]$BridgeRoot,
    [Parameter(Mandatory=$true)][string]$OutputRoot,
    [Parameter(Mandatory=$true)][string]$InputManifest,
    [string]$Patch = (Join-Path $PSScriptRoot 'ble-driver-fixes.patch'),
    [string]$ContractsRoot = "$env:USERPROFILE\.nuget\packages\microsoft.windows.sdk.contracts\10.0.26100.7705",
    [string]$MSBuild = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe'
)
$ErrorActionPreference = 'Stop'
$BridgeRoot = (Resolve-Path -LiteralPath $BridgeRoot).Path
$InputManifest = (Resolve-Path -LiteralPath $InputManifest).Path
$ContractsRoot = (Resolve-Path -LiteralPath $ContractsRoot).Path
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
if (Test-Path -LiteralPath $OutputRoot) { throw 'OutputRoot must be a new isolated directory.' }
if ($OutputRoot.StartsWith($BridgeRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Outputs must be outside the read-only bridge tree.'
}
function File-Identity([string]$Path) {
    $item = Get-Item -LiteralPath $Path
    @{ path=$item.FullName; bytes=$item.Length; sha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
}
$Patch = (Resolve-Path -LiteralPath $Patch).Path
$patchIdentity = File-Identity $Patch
$regressionScript = Join-Path $PSScriptRoot 'test-ble-driver.ps1'
# Strict unified-diff application: exact source lines/positions only, no fuzz, no Git/index writes.
function Apply-BridgePatch([string]$Root, [string]$PatchPath) {
    $lines = [IO.File]::ReadAllLines($PatchPath)
    $index = 0
    $changed = @()
    while ($index -lt $lines.Length) {
        if ($lines[$index] -notmatch '^--- a/(Program\.cs|TcpServer\.cs|Form1\.cs)$') { throw 'Unexpected patch source header.' }
        $name = $Matches[1]; $index++
        if ($changed -contains $name -or $lines[$index] -ne "+++ b/$name") { throw 'Unexpected patch target header.' }
        $index++; $changed += $name
        $path = Join-Path $Root $name
        $raw = [IO.File]::ReadAllText($path)
        $original = $raw.Replace("`r`n", "`n").TrimEnd("`n").Split("`n")
        $result = [Collections.Generic.List[string]]::new(); $cursor = 0
        while ($index -lt $lines.Length -and -not $lines[$index].StartsWith('--- ')) {
            if ($lines[$index] -notmatch '^@@ -(\d+),(\d+) \+(\d+),(\d+) @@$') { throw 'Unexpected patch hunk.' }
            $start = [int]$Matches[1]-1; $oldCount = [int]$Matches[2]; $newStart = [int]$Matches[3]-1; $newCount = [int]$Matches[4]
            if ($start -lt $cursor) { throw 'Overlapping patch hunk.' }
            while ($cursor -lt $start) { $result.Add($original[$cursor]); $cursor++ }
            if ($result.Count -ne $newStart) { throw 'Patch output position mismatch.' }
            $index++; $oldSeen = 0; $newSeen = 0
            while ($index -lt $lines.Length -and -not $lines[$index].StartsWith('@@ ') -and -not $lines[$index].StartsWith('--- ')) {
                $line = $lines[$index]; $index++
                if ($line.Length -eq 0) { throw 'Malformed patch line.' }
                $kind = $line.Substring(0,1); $value = $line.Substring(1)
                if ($kind -eq ' ' -or $kind -eq '-') {
                    if ($cursor -ge $original.Length -or $original[$cursor] -cne $value) { throw "Patch context mismatch: $name line $($cursor+1)" }
                    $cursor++; $oldSeen++
                }
                if ($kind -eq ' ' -or $kind -eq '+') { $result.Add($value); $newSeen++ }
                if ($kind -notin @(' ','+','-')) { throw 'Unsupported patch operation.' }
            }
            if ($oldSeen -ne $oldCount -or $newSeen -ne $newCount) { throw 'Patch hunk count mismatch.' }
        }
        while ($cursor -lt $original.Length) { $result.Add($original[$cursor]); $cursor++ }
        $newline = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }
        [IO.File]::WriteAllText($path, (($result -join $newline) + $newline), [Text.UTF8Encoding]::new($false))
    }
    if ($changed.Count -ne 3) { throw 'Expected exactly the three reviewed bridge files.' }
}
$approved = Get-Content -LiteralPath $InputManifest -Raw | ConvertFrom-Json
foreach ($file in $approved.files) {
    $path = Join-Path $BridgeRoot ([IO.Path]::GetFileName($file.path))
    if ((Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -ne $file.sha256) { throw "Pinned bridge input changed: $path" }
}
$project = Join-Path $BridgeRoot 'BLE_tcp_driver.csproj'
[xml]$xml = Get-Content -LiteralPath $project -Raw
$names = @('BLE_tcp_driver.csproj','BRIDGE-01_OFFLINE_TIMING_TESTS.ps1') + @($xml.Project.ItemGroup.ChildNodes |
    Where-Object { $_.LocalName -in @('Compile','EmbeddedResource','None') } | ForEach-Object { $_.Include })
$names = @($names | Sort-Object -Unique)
$sourceInputs = @($names | ForEach-Object { File-Identity (Join-Path $BridgeRoot $_) })
$contracts = @(Get-ChildItem -LiteralPath (Join-Path $ContractsRoot 'ref/netstandard2.0') -Filter '*.winmd' -File)
if ($contracts.Count -eq 0) { throw 'Previously restored SDK Contracts are required; no restore/download is performed.' }
$packageRoot = Split-Path -Parent (Split-Path -Parent $ContractsRoot)
# These are the existing Contracts 10.0.26100.7705 transitive imports, not new dependencies.
$packageImports = @(
    (Join-Path $ContractsRoot 'build/Microsoft.Windows.SDK.Contracts.props'),
    (Join-Path $packageRoot 'system.runtime.windowsruntime/4.6.0/buildTransitive/net461/System.Runtime.WindowsRuntime.targets'),
    (Join-Path $packageRoot 'system.runtime.windowsruntime.ui.xaml/4.6.0/build/net461/System.Runtime.WindowsRuntime.UI.Xaml.targets'),
    (Join-Path $ContractsRoot 'build/Microsoft.Windows.SDK.Contracts.targets')
)
$importInputs = @($packageImports | ForEach-Object { File-Identity $_ })
New-Item -ItemType Directory -Path $OutputRoot | Out-Null
$snapshot = Join-Path $OutputRoot 'source'
New-Item -ItemType Directory -Path $snapshot | Out-Null
foreach ($name in $names) {
    $destination = Join-Path $snapshot $name
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath (Join-Path $BridgeRoot $name) -Destination $destination
    $expected = ($sourceInputs | Where-Object { $_.path -eq (Join-Path $BridgeRoot $name) }).sha256
    if ((Get-FileHash -LiteralPath $destination).Hash.ToLowerInvariant() -ne $expected) { throw "Snapshot mismatch: $name" }
}
Apply-BridgePatch $snapshot $Patch
$patchedInputs = @($names | ForEach-Object { File-Identity (Join-Path $snapshot $_) })
# Classic csproj requires explicit references to the already restored SDK. No csproj/framework changes.
$targets = Join-Path $OutputRoot 'OfflineContracts.targets'
$refs = ($contracts | ForEach-Object { '<Reference Include="' + [Security.SecurityElement]::Escape($_.FullName) + '" />' }) -join "`n"
$resolvedReferences = Join-Path $OutputRoot 'resolved-references.txt'
$captureReferences = '<Target Name="CaptureBridgeReferences" AfterTargets="ResolveReferences"><WriteLinesToFile File="' + [Security.SecurityElement]::Escape($resolvedReferences) + '" Lines="@(ReferencePath)" Overwrite="true" /></Target>'
$imports = ($packageImports | ForEach-Object { '<Import Project="' + [Security.SecurityElement]::Escape($_) + '" />' }) -join "`n"
('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + $imports + '<ItemGroup>' + $refs + '</ItemGroup>' + $captureReferences + '</Project>') |
    Set-Content -LiteralPath $targets -Encoding UTF8
$bin = Join-Path $OutputRoot 'bin'
$obj = Join-Path $OutputRoot 'obj'
$arguments = @((Join-Path $snapshot 'BLE_tcp_driver.csproj'), '/t:Build', '/p:Configuration=Release',
    "/p:OutputPath=$bin\", "/p:IntermediateOutputPath=$obj\", '/p:BuildProjectReferences=false',
    "/p:CustomAfterMicrosoftCommonTargets=$targets", '/p:GenerateResourceMSBuildArchitecture=CurrentArchitecture', '/v:normal')
@{ schema_version=1; source_root=$BridgeRoot; approved_manifest=(File-Identity $InputManifest); sources=$sourceInputs;
    build_script=(File-Identity $MyInvocation.MyCommand.Path);
    patch=$patchIdentity; patched_sources=$patchedInputs; regression_script=(File-Identity $regressionScript);
    package_imports=$importInputs;
    contracts=@($contracts | ForEach-Object { File-Identity $_.FullName }); msbuild=(File-Identity $MSBuild);
    targets=(File-Identity $targets); arguments=$arguments } | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath (Join-Path $OutputRoot 'BUILD_INPUTS.json') -Encoding UTF8
& $MSBuild @arguments *> (Join-Path $OutputRoot 'build.log')
$buildExit = $LASTEXITCODE
if ($buildExit -ne 0) { throw "Bridge build failed ($buildExit); see $OutputRoot/build.log" }
$resolved = @(Get-Content -LiteralPath $resolvedReferences | Where-Object { $_ } | Sort-Object -Unique | ForEach-Object { File-Identity $_ })
if ($resolved.Count -eq 0) { throw 'MSBuild did not report resolved compilation references.' }
@{ references=$resolved } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputRoot 'RESOLVED_REFERENCES.json') -Encoding UTF8
& pwsh -NoProfile -File (Join-Path $snapshot 'BRIDGE-01_OFFLINE_TIMING_TESTS.ps1') *> (Join-Path $OutputRoot 'tests.log')
$testExit = $LASTEXITCODE
if ($testExit -ne 0) { throw "Bridge offline tests failed ($testExit); see $OutputRoot/tests.log" }
& pwsh -NoProfile -File $regressionScript -SourceRoot $snapshot *> (Join-Path $OutputRoot 'regression.log')
$regressionExit = $LASTEXITCODE
if ($regressionExit -ne 0) { throw "Bridge regression failed ($regressionExit); see $OutputRoot/regression.log" }
foreach ($file in @($patchedInputs) + @($patchIdentity)) {
    if ((Get-FileHash -LiteralPath $file.path).Hash.ToLowerInvariant() -ne $file.sha256) { throw 'Build input changed during compilation/tests.' }
}
foreach ($file in $sourceInputs) {
    if ((Get-FileHash -LiteralPath $file.path).Hash.ToLowerInvariant() -ne $file.sha256) { throw "Bridge source changed during build: $($file.path)" }
}
$files = @(Get-ChildItem -LiteralPath $bin -Recurse -File | ForEach-Object {
    @{path=$_.FullName.Substring($bin.Length+1); bytes=$_.Length; sha256=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant(); runtime=($_.Extension -ne '.pdb')}
})
if (-not ($files | Where-Object { $_.path -eq 'BLE_tcp_driver.exe' })) { throw 'Missing driver executable.' }
@{ schema_version=1; status='OFFLINE_BUILD_ONLY_NOT_ADMITTED'; output_root=$bin; build_exit=$buildExit; test_exit=$testExit;
    resolved_references=(File-Identity (Join-Path $OutputRoot 'RESOLVED_REFERENCES.json'));
    regression_exit=$regressionExit; regression_log=(File-Identity (Join-Path $OutputRoot 'regression.log'));
    inputs=(File-Identity (Join-Path $OutputRoot 'BUILD_INPUTS.json')); build_log=(File-Identity (Join-Path $OutputRoot 'build.log'));
    tests_log=(File-Identity (Join-Path $OutputRoot 'tests.log')); files=$files;
    prerequisite='.NET Framework 4.7.2 and supported Windows BLE stack; not installed by this script' } | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath (Join-Path $OutputRoot 'BRIDGE_BUILD_MANIFEST.json') -Encoding UTF8
Write-Output "PASS offline bridge build/tests: $OutputRoot/BRIDGE_BUILD_MANIFEST.json (not hardware/admission PASS)"
