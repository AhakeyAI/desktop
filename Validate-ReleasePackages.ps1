param([Parameter(Mandatory=$true)][string]$WixBin,[string]$PackageRoot='artifacts/public-installer')
$ErrorActionPreference='Stop'
Push-Location $PSScriptRoot
try {
 [xml]$props=Get-Content Directory.Build.props
 $version=[string]$props.Project.PropertyGroup.Version
 $root=(Resolve-Path -LiteralPath $PackageRoot).Path
 $manifest=@(Get-Content -LiteralPath "$root/runtime-manifest.json" -Raw | ConvertFrom-Json)
 foreach($entry in $manifest){if($entry.Path -match '(?i)(FirmwarePackages|\.hex$|WCH|\.pdb$|\.log$|\.jsonl$|Fixture|Tests|Smoke)'){throw "Forbidden public file: $($entry.Path)"}}
 Add-Type -AssemblyName System.IO.Compression
 $zip=[IO.Compression.ZipFile]::OpenRead("$root/AhaKeyStudio-$version-win-x64.zip")
 try {
  $files=@($zip.Entries | Where-Object Length -GT 0)
  if($files.Count -ne $manifest.Count){throw 'ZIP file count differs from manifest'}
  foreach($entry in $manifest){$item=$zip.GetEntry($entry.Path.Replace('\','/'));if($null -eq $item -or $item.Length -ne $entry.Bytes){throw "ZIP missing/size mismatch: $($entry.Path)"};$stream=$item.Open();try{$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream));if($hash -ne $entry.SHA256){throw "ZIP hash mismatch: $($entry.Path)"}}finally{$stream.Dispose()}}
 } finally {$zip.Dispose()}
 $msi="$root/AhaKeyStudio-$version-win-x64.msi"
 $extract=Join-Path $root ('validation-'+[guid]::NewGuid().ToString('N'))
 New-Item -ItemType Directory -Path $extract | Out-Null
 & "$WixBin/dark.exe" -nologo -x $extract -o "$extract/package.wxs" $msi
 if($LASTEXITCODE -ne 0){throw 'MSI extraction failed'}
 [xml]$package=Get-Content -LiteralPath "$extract/package.wxs"
 $ns=[Xml.XmlNamespaceManager]::new($package.NameTable);$ns.AddNamespace('w','http://schemas.microsoft.com/wix/2006/wi')
 $msiFiles=@($package.SelectNodes('//w:File',$ns))
 if($msiFiles.Count -ne $manifest.Count){throw 'MSI file count differs from manifest'}
 foreach($entry in $manifest){$relative=$entry.Path;$pathHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($relative.ToLowerInvariant())));$id=if($relative -eq 'AhaKey Studio.exe'){'StudioExecutable'}else{'F'+$pathHash.Substring(0,28)};$item=$msiFiles | Where-Object Id -EQ $id;if(@($item).Count -ne 1){throw "MSI file missing: $relative"};$source=$item.Source;if(-not [IO.Path]::IsPathRooted($source)){$source=Join-Path $PSScriptRoot $source};if(-not(Test-Path -LiteralPath $source)){throw "Extracted source missing: $source"};if((Get-Item -LiteralPath $source).Length -ne $entry.Bytes -or (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $entry.SHA256){throw "MSI payload mismatch: $relative"}}
 foreach($line in Get-Content -LiteralPath "$root/SHA256SUMS.txt"){$parts=$line -split '  ',2;if($parts.Count -ne 2 -or (Get-FileHash -LiteralPath (Join-Path $root $parts[1]) -Algorithm SHA256).Hash -ne $parts[0]){throw 'Package checksum mismatch'}}
 $summary=[ordered]@{StudioVersion=$version;Files=$manifest.Count;ZipPayloadHashes='PASS';MsiPayloadHashes='PASS';RestrictedFiles='ABSENT';PackageChecksums='PASS';Signature=(Get-AuthenticodeSignature -LiteralPath $msi).Status.ToString();CheckedAtUtc=[DateTimeOffset]::UtcNow.ToString('o');InstallUpgradeUninstall='NOT_TESTED_BY_THIS_SCRIPT'}
 $summary | ConvertTo-Json | Set-Content -LiteralPath "$root/package-validation.json" -Encoding utf8
 $resolvedExtract=[IO.Path]::GetFullPath($extract)
 if(-not $resolvedExtract.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolvedExtract) -notmatch '^validation-[0-9a-f]{32}$'){throw 'Unsafe validation cleanup path'}
 Remove-Item -LiteralPath $resolvedExtract -Recurse -Force
 $summary
} finally {Pop-Location}
