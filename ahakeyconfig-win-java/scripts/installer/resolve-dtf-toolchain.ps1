<# Offline validation only. Never downloads, installs, or executes DTF inputs. #>
param([Parameter(Mandatory=$true)][string]$DtfRoot)
$ErrorActionPreference='Stop'
$DtfRoot=(Resolve-Path -LiteralPath $DtfRoot).Path
$lockPath=Join-Path $PSScriptRoot 'dtf-toolchain.json'
$lock=Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8|ConvertFrom-Json
if($lock.schemaVersion -ne 1 -or $lock.version -cne '5.0.2' -or @($lock.packages).Count -ne 2){throw 'Unsupported DTF lock'}
function Input-Path([string]$Relative) {
    if([IO.Path]::IsPathRooted($Relative) -or $Relative -match '(^|[/\\])\.\.([/\\]|$)' -or $Relative.Contains(':')){throw 'Unsafe DTF input path'}
    $path=[IO.Path]::GetFullPath((Join-Path $DtfRoot $Relative))
    if(-not $path.StartsWith($DtfRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'DTF input escapes root'}
    return $path
}
function Assert-Input([string]$Path,[string]$Hash) {
    if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){throw "Missing DTF input: $Path"}
    if($Hash -cnotmatch '^[a-f0-9]{64}$' -or (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $Hash){throw "DTF hash mismatch: $Path"}
}
$inputs=New-Object 'System.Collections.Generic.List[object]'
foreach($package in $lock.packages) {
    $archive=Input-Path $package.archive
    Assert-Input $archive $package.sha256
    $sha512=[Security.Cryptography.SHA512]::Create()
    try {$actual512=[Convert]::ToBase64String($sha512.ComputeHash([IO.File]::ReadAllBytes($archive)))} finally {$sha512.Dispose()}
    if($actual512 -cne $package.sha512){throw "DTF SHA512 mismatch: $archive"}
    $inputs.Add(@{path=$archive;sha256=$package.sha256})
    $directory=Input-Path $package.directory
    # Reject extra adjacent binaries/configuration that could affect assembly loading.
    $actualFiles=@(Get-ChildItem -LiteralPath $directory -File -Recurse -Force)
    if($actualFiles.Count -ne @($package.files).Count){throw "Unexpected DTF package contents: $directory"}
    foreach($file in $package.files) {
        $path=Input-Path ($package.directory+'/'+$file.path)
        Assert-Input $path $file.sha256
        $inputs.Add(@{path=$path;sha256=$file.sha256})
    }
}
foreach($relative in @($lock.runtime,$lock.packager,$lock.stub)) {
    $path=Input-Path $relative
    if(@($inputs|Where-Object {$_.path -ieq $path}).Count -ne 1){throw 'DTF tool is not a locked input'}
}
[pscustomobject]@{
    Root=$DtfRoot;Version=$lock.version;Runtime=(Input-Path $lock.runtime)
    Packager=(Input-Path $lock.packager);Stub=(Input-Path $lock.stub)
    Provenance=@{version=$lock.version;repository=$lock.repository;commit=$lock.commit;license=$lock.license;licenseUrl=$lock.licenseUrl
        lockPath=$lockPath;lockSha256=(Get-FileHash -LiteralPath $lockPath -Algorithm SHA256).Hash.ToLowerInvariant()
        resolverPath=$PSCommandPath;resolverSha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
        packages=@($lock.packages|Select-Object id,version,url,sha256,sha512);inputs=$inputs.ToArray()}
}
