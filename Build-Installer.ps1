param([string]$WixBin, [string]$Dotnet='dotnet', [switch]$SkipPublish)
$ErrorActionPreference='Stop'
Push-Location $PSScriptRoot
try {
 if(-not $SkipPublish){& ./Publish-Studio.ps1 -Dotnet $Dotnet}
 if(-not (Test-Path -LiteralPath "$WixBin/candle.exe")){throw 'Supply WiX 3.14 bin directory.'}
 [xml]$props=Get-Content Directory.Build.props
 $version=[string]$props.Project.PropertyGroup.Version
 $fileVersion=[version]([string]$props.Project.PropertyGroup.FileVersion)
 $msiVersion="$($fileVersion.Major).$($fileVersion.Minor).$($fileVersion.Revision)"
 $runtime=(Resolve-Path artifacts/runtime).Path
 $output=Join-Path $PSScriptRoot 'artifacts/installer'
 $build=Join-Path $PSScriptRoot 'artifacts/installer-build'
 New-Item -ItemType Directory -Force -Path $build | Out-Null
 New-Item -ItemType Directory -Force -Path $output | Out-Null
 $forbidden=Get-ChildItem $runtime -File -Recurse | Where-Object { $_.Extension -in '.pdb','.log','.jsonl','.ps1','.py','.java' -or $_.Name -match 'BLE_tcp|Tests|Smoke|Fixture' }
 if($forbidden){throw ('Forbidden runtime files: '+($forbidden.Name -join ', '))}
 foreach($required in 'AhaKey Studio.exe','hostfxr.dll','coreclr.dll','AhaKey Studio.runtimeconfig.json'){if(-not(Test-Path -LiteralPath (Join-Path $runtime $required))){throw "Missing self-contained runtime file: $required"}}
 $builder=[Text.StringBuilder]::new()
 [void]$builder.AppendLine('<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi"><Fragment><DirectoryRef Id="INSTALLFOLDER">')
 $components=[Collections.Generic.List[string]]::new()
 $files=Get-ChildItem -LiteralPath $runtime -File -Recurse | Sort-Object FullName
 foreach($file in $files){
  $relative=[IO.Path]::GetRelativePath($runtime,$file.FullName)
  $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($relative.ToLowerInvariant())))
  $id='C'+$hash.Substring(0,28);$fileId=if($relative -eq 'AhaKey Studio.exe'){'StudioExecutable'}else{'F'+$hash.Substring(0,28)}
  $parts=$relative.Split([IO.Path]::DirectorySeparatorChar)
  $current=''
  for($i=0;$i -lt $parts.Length-1;$i++){
   $current+='/'+$parts[$i];$dirHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($relative+':'+$current)))
   [void]$builder.AppendLine('<Directory Id="D'+$dirHash.Substring(0,28)+'" Name="'+[Security.SecurityElement]::Escape($parts[$i])+'">')
  }
  [void]$builder.AppendLine('<Component Id="'+$id+'" Guid="'+([guid]$hash.Substring(0,32)).ToString()+'" Win64="yes"><File Id="'+$fileId+'" Source="'+[Security.SecurityElement]::Escape($file.FullName)+'" /><RegistryValue Root="HKCU" Key="Software\AhaKey\StudioInstaller\Files" Name="'+$id+'" Type="integer" Value="1" KeyPath="yes"/><RemoveFolder Id="R'+$hash.Substring(0,28)+'" On="uninstall"/></Component>')
  for($i=0;$i -lt $parts.Length-1;$i++){[void]$builder.AppendLine('</Directory>')}
  $components.Add($id)
 }
 [void]$builder.AppendLine('</DirectoryRef></Fragment><Fragment><ComponentGroup Id="RuntimeFiles">')
 foreach($id in $components){[void]$builder.AppendLine('<ComponentRef Id="'+$id+'"/>')}
 [void]$builder.AppendLine('</ComponentGroup></Fragment></Wix>')
 $builder.ToString() | Set-Content -LiteralPath "$build/Runtime.wxs" -Encoding utf8
 & "$WixBin/candle.exe" -nologo -arch x64 "-dMsiVersion=$msiVersion" "-dProductVersion=$version" "-dIconPath=$PSScriptRoot/src/AhaKey.Studio/Assets/AhaKeyStudio.ico" "-dLicensePath=$PSScriptRoot/installer/license.rtf" -out "$build/" installer/Studio.wxs "$build/Runtime.wxs"
 if($LASTEXITCODE -ne 0){throw 'WiX compilation failed'}
 & "$WixBin/light.exe" -nologo -pdbout "$build/installer.wixpdb" -sice:ICE91 -ext WixUIExtension -out "$output/AhaKeyStudio-$version-win-x64.msi" "$build/Studio.wixobj" "$build/Runtime.wixobj"
 if($LASTEXITCODE -ne 0){throw 'WiX linking failed'}
 $files | ForEach-Object {[pscustomobject]@{Path=[IO.Path]::GetRelativePath($runtime,$_.FullName);Bytes=$_.Length;SHA256=(Get-FileHash -LiteralPath $_.FullName).Hash}} | ConvertTo-Json | Set-Content "$output/runtime-manifest.json" -Encoding utf8
 Compress-Archive -Path "$runtime/*" -DestinationPath "$output/AhaKeyStudio-$version-win-x64.zip" -Force
 Get-FileHash "$output/AhaKeyStudio-$version-win-x64.msi","$output/AhaKeyStudio-$version-win-x64.zip"
} finally {Pop-Location}
