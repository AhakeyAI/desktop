param(
    [ValidateSet('Inspect','VerifyRelease','Resolve','Install')][string]$Mode,
    [string]$Executable, [string]$Result, [string]$Request, [string]$RequestHash
)
$ErrorActionPreference = 'Stop'
$env:PSModulePath = Join-Path $PSHOME 'Modules'
function Write-AtomicJson($Path, $Value) {
    $temp = $Path + '.tmp'
    [IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
    [IO.File]::Move($temp, $Path)
}
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class UpdateResource {
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr LoadLibraryEx(string p, IntPtr h, uint f);
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr FindResource(IntPtr h, string n, IntPtr t);
 [DllImport("kernel32.dll")] static extern uint SizeofResource(IntPtr h, IntPtr r);
 [DllImport("kernel32.dll")] static extern IntPtr LoadResource(IntPtr h, IntPtr r);
 [DllImport("kernel32.dll")] static extern IntPtr LockResource(IntPtr r);
 [DllImport("kernel32.dll")] static extern bool FreeLibrary(IntPtr h);
 public static byte[] Msi(string path) {
   IntPtr h=LoadLibraryEx(path,IntPtr.Zero,0x22);
   if(h==IntPtr.Zero) throw new Exception("Cannot map installer as data");
   try { IntPtr r=FindResource(h,"MSI",new IntPtr(10)); uint n=SizeofResource(h,r);
     if(r==IntPtr.Zero || n==0 || n>Int32.MaxValue) throw new Exception("Embedded MSI missing");
     byte[] b=new byte[n]; Marshal.Copy(LockResource(LoadResource(h,r)),b,0,(int)n); return b;
   } finally { FreeLibrary(h); }
 }
}
public static class AhaReleaseSignature {
 const string Modulus = "n6UVnDHfmQW1QjHA+dhGqDNQGSIerenhPMf5VZ4Lyk9N2F5Pd3/0ZV6J2bIdZE65Y41ig3ZRIX58jqhufJ36mTJ/GUA+s2FN1fshclH1yjtGK14fWaDjPqnIA0nU4++HR2o9X7CTTIzFJMijHhkeQgPcSsve077jcRv4YaHeNQ0+vOWJRO6Yk/1dW2n6Eqf0CUaBjUeYGRfjusgH8h9l01dt5wfk0c7pKnoNJO0XzCBdQwvjPBJuW+c0hAaErBficK8uwkCeK17EnE8YTbmlDb8OyUPtr/oTV45iazBQmiXk0B77+Hfjw+hGgj8/+70hWc/zHKCBYNRYy7+hXB5Umlz/QZQQf765fAg6/XQ73f0AVrx+RIPE6ndVFgfVAguxzHQtkmr/SF8LsLoUpp/RLBy+yIpZKnn9rHbAl8K3Np2Eq1ZDwDNmY9wVOhrDUi+FgaD1XJ0i9aQJ4cEl2rU1SYRanYVG/WybL3OhNcbE4QpcW+LOTvSazIW8pPu/8Na5";
 public static System.Collections.Generic.Dictionary<string,object> Verify(string path) {
  return VerifyWithKey(path, Modulus, "AQAB");
 }
 // Public for isolated interoperability tests; production entry always calls Verify with the compiled key.
 public static System.Collections.Generic.Dictionary<string,object> VerifyWithKey(string path,string modulus,string exponent) {
  using(var stream=new System.IO.FileStream(path,System.IO.FileMode.Open,System.IO.FileAccess.Read,System.IO.FileShare.Read))
  using(var reader=new System.IO.BinaryReader(stream,new System.Text.UTF8Encoding(false,true))) {
   long total=stream.Length;if(total<464 || total>2147483648L)throw new Exception("Invalid release size");
   stream.Position=total-16;
   if(System.Text.Encoding.ASCII.GetString(reader.ReadBytes(8))!="AHAKEND1")throw new Exception("Invalid release footer");
   uint length=reader.ReadUInt32();uint version=reader.ReadUInt32();
   if(version!=1 || length<64 || length>2048 || length>total-400)throw new Exception("Invalid release envelope length");
   long prefix=total-400-length;stream.Position=prefix;
   byte[] payload=reader.ReadBytes((int)length),signature=reader.ReadBytes(384);
   using(var rsa=new System.Security.Cryptography.RSACryptoServiceProvider()) {
    rsa.PersistKeyInCsp=false;
    byte[] m=Convert.FromBase64String(modulus),e=Convert.FromBase64String(exponent);
    if(m.Length!=384 || m[0]<128 || exponent!="AQAB")throw new Exception("Invalid fixed release key");
    rsa.ImportParameters(new System.Security.Cryptography.RSAParameters {Modulus=m,Exponent=e});
    if(!rsa.VerifyData(payload,System.Security.Cryptography.CryptoConfig.MapNameToOID("SHA256"),signature))throw new Exception("Untrusted release signature");
   }
   var fields=new System.Collections.Generic.Dictionary<string,object>();byte[] expectedHash;
   using(var bytes=new System.IO.MemoryStream(payload))using(var p=new System.IO.BinaryReader(bytes,new System.Text.UTF8Encoding(false,true))) {
    if(System.Text.Encoding.ASCII.GetString(p.ReadBytes(8))!="AHAKSIG1" || p.ReadUInt64()!=(ulong)prefix || prefix<2)throw new Exception("Invalid release prefix length");
    expectedHash=p.ReadBytes(32);
    foreach(string name in new[]{"version","variant","arch","productId","upgradeCode","productCode"}) {
     int size=p.ReadUInt16();if(size<1 || size>128 || size>bytes.Length-bytes.Position)throw new Exception("Invalid release field size");
     string value=new System.Text.UTF8Encoding(false,true).GetString(p.ReadBytes(size));
     foreach(char c in value)if(Char.IsControl(c))throw new Exception("Invalid release text");fields.Add(name,value);
    }
    if(bytes.Position!=bytes.Length)throw new Exception("Trailing release fields");
   }
   if(!System.Text.RegularExpressions.Regex.IsMatch((string)fields["version"],@"^(0|[1-9][0-9]{0,4})\.(0|[1-9][0-9]{0,4})\.(0|[1-9][0-9]{0,4})$") ||
      ((string)fields["variant"]!="lite" && (string)fields["variant"]!="local-model") || (string)fields["arch"]!="x64" || (string)fields["productId"]!="AhaKeyStudio" ||
      !String.Equals((string)fields["upgradeCode"],"{03E5A934-FFCA-3815-B455-7D49BF1CA1DC}",StringComparison.OrdinalIgnoreCase) ||
      !System.Text.RegularExpressions.Regex.IsMatch((string)fields["productCode"],@"^\{[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}\}$"))throw new Exception("Invalid release identity");
   if(prefix>=16){stream.Position=prefix-16;if(System.Text.Encoding.ASCII.GetString(reader.ReadBytes(8))=="AHAKEND1")throw new Exception("Duplicate release envelope");}
   stream.Position=0;if(reader.ReadByte()!=77 || reader.ReadByte()!=90)throw new Exception("Not an executable");stream.Position=0;
   using(var sha=System.Security.Cryptography.SHA256.Create()) {
    byte[] buffer=new byte[65536];long remaining=prefix;
    while(remaining>0){int count=stream.Read(buffer,0,(int)Math.Min(buffer.Length,remaining));if(count==0)throw new System.IO.EndOfStreamException();sha.TransformBlock(buffer,0,count,null,0);remaining-=count;}
    sha.TransformFinalBlock(new byte[0],0,0);
    if(!System.Collections.StructuralComparisons.StructuralEqualityComparer.Equals(expectedHash,sha.Hash))throw new Exception("Release content changed");
   }
   fields.Add("prefixLength",prefix);return fields;
  }
 }
}
'@
function Inspect-Package([string]$Path) {
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    $certHash = ''
    if ($signature.SignerCertificate) {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $certHash = ([BitConverter]::ToString($sha.ComputeHash($signature.SignerCertificate.RawData))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
    }
    $scratch = if($Mode -eq 'Inspect'){[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Result))}else{[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Request))}
    $msi = Join-Path $scratch ('inspection-' + [Guid]::NewGuid().ToString() + '.msi')
    $temporaryMsi = $true
    if ([IO.Path]::GetExtension($Path) -ieq '.msi') { $msi = $Path; $temporaryMsi = $false }
    else { [IO.File]::WriteAllBytes($msi, [UpdateResource]::Msi($Path)) }
    $database = $null; $installer = $null
    try {
        $installer = New-Object -ComObject WindowsInstaller.Installer
        $database = $installer.OpenDatabase($msi, 0)
        $properties = @{}
        foreach ($name in @('ProductName','ProductVersion','UpgradeCode','ProductCode','AHAKEY_VARIANT','AHAKEY_ARCH','AHAKEY_BUILD_ID')) {
            $view = $database.OpenView("SELECT ``Value`` FROM ``Property`` WHERE ``Property``='$name'")
            try { $view.Execute(); $row = $view.Fetch(); if ($row) { $properties[$name] = $row.StringData(1); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($row) } }
            finally { $view.Close(); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($view) }
        }
        return @{ status=$signature.Status.ToString(); certificateSha256=$certHash; productName=$properties.ProductName;
            version=$properties.ProductVersion; upgradeCode=$properties.UpgradeCode; productCode=$properties.ProductCode;
            variant=$properties.AHAKEY_VARIANT; arch=$properties.AHAKEY_ARCH; buildId=$properties.AHAKEY_BUILD_ID; msiSha256=(Get-FileHash -LiteralPath $msi -Algorithm SHA256).Hash.ToLowerInvariant() }
    } finally {
        if ($database) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($database) }
        if ($installer) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($installer) }
        if ($temporaryMsi) { Remove-Item -LiteralPath $msi -Force }
    }
}
if ($Mode -eq 'Inspect') { Write-AtomicJson $Result (Inspect-Package $Executable); exit 0 }
if ($Mode -eq 'VerifyRelease') { Write-AtomicJson $Result ([AhaReleaseSignature]::Verify($Executable)); exit 0 }
Add-Type -Path (Join-Path $PSScriptRoot 'InstalledApplication.cs')
function Read-Installed([string]$Launcher) {
    $i=[AhaKey.Installation.InstalledApplication]::Resolve($Launcher,$true)
    return @{productCode=$i.ProductCode;upgradeCode=$i.UpgradeCode;version=$i.Version;variant=$i.Variant;arch=$i.Arch;directory=$i.Directory;launcher=$i.Launcher;buildId=$i.BuildId;msiSha256=$i.MsiSha256;context=$i.Context}
}
if ($Mode -eq 'Resolve') { Write-AtomicJson $Result (Read-Installed $Executable); exit 0 }
function Assert-Source($Expected) {
    $actual=[AhaKey.Installation.InstalledApplication]::Resolve($q.launcher,$true)
    [AhaKey.Installation.InstalledApplication]::AssertSource($actual,$Expected.productCode,$Expected.directory,$Expected.version,$Expected.msiSha256)
    if($actual.Context -ne $Expected.context -or $actual.Variant -cne $Expected.variant -or $actual.Arch -cne $Expected.arch -or $actual.BuildId -cne $Expected.buildId){throw 'Source installation identity changed'}
    if([AhaKey.Installation.InstalledApplication]::RollbackDisabled()){throw 'Windows Installer rollback is disabled'}
}
if ($Mode -ne 'Install' -or $RequestHash -notmatch '^[a-f0-9]{64}$') { throw 'Invalid worker mode/request' }
if ((Get-FileHash -LiteralPath $Request -Algorithm SHA256).Hash.ToLowerInvariant() -ne $RequestHash) { throw 'Request changed' }
$q = Get-Content -LiteralPath $Request -Raw -Encoding UTF8 | ConvertFrom-Json
$directory = [IO.Path]::GetDirectoryName($Request)
$receipt = @{operationId=$q.operationId; requestHash=$RequestHash; state='worker-failed'; exitCode=$null}
$lock = $null
$parentExited = $false
try {
    if ([IO.Path]::GetFullPath($q.installer) -ne (Join-Path $directory 'installer.exe')) { throw 'Invalid frozen installer path' }
    $lock = [IO.File]::Open($q.installer, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    if ($lock.Length -ne $q.size -or (Get-FileHash -LiteralPath $q.installer).Hash.ToLowerInvariant() -ne $q.sha256) { throw 'Installer changed' }
    $identity = Inspect-Package $q.installer
    $signed = [AhaReleaseSignature]::Verify($q.installer)
    if ($signed.version -cne $identity.version -or $signed.variant -cne $identity.variant -or $signed.arch -cne $identity.arch -or $signed.productId -cne $identity.productName -or $signed.upgradeCode -ine $identity.upgradeCode -or $signed.productCode -ine $identity.productCode) { throw 'Release signature and actual MSI identity mismatch' }
    if ($identity.productName -cne $q.productId -or $identity.version -cne $q.version -or $identity.variant -cne $q.variant -or $identity.arch -cne $q.arch -or $identity.upgradeCode -ine $q.upgradeCode) { throw 'MSI identity mismatch' }
    if($identity.productCode -ine $q.targetProductCode -or $identity.msiSha256 -cne $q.targetMsiSha256 -or $identity.buildId -cne $q.targetBuildId -or $q.targetBuildId -notmatch '^[a-f0-9]{64}$'){throw 'Target build identity mismatch'}
    Assert-Source $q.source
    $parent = Get-Process -Id $q.parentPid -ErrorAction Stop
    $parentStart = ([DateTimeOffset]$parent.StartTime.ToUniversalTime()).ToUnixTimeMilliseconds()
    if ([Math]::Abs($parentStart - $q.parentStart) -gt 1000) { throw 'Parent identity changed' }
    if(-not [AhaKey.Installation.InstalledApplication]::Same([IO.Path]::GetFullPath($parent.Path),[IO.Path]::GetFullPath($q.launcher))){throw 'Parent executable differs from registered launcher'}
    Write-AtomicJson (Join-Path $directory 'ready.json') @{operationId=$q.operationId; requestHash=$RequestHash}
    $deadline = [DateTime]::UtcNow.AddMinutes(2)
    $permitFile = Join-Path $directory 'exit-permit.json'
    while (-not (Test-Path -LiteralPath $permitFile)) {
        if ([DateTime]::UtcNow -gt $deadline) { throw 'No explicit exit permit' }
        Start-Sleep -Milliseconds 100
    }
    $permit = Get-Content -LiteralPath $permitFile -Raw | ConvertFrom-Json
    if ($permit.operationId -ne $q.operationId -or $permit.requestHash -ne $RequestHash) { throw 'Invalid exit permit' }
    Assert-Source $q.source
    if (-not $parent.WaitForExit(120000)) { throw 'Parent did not exit; installation not started' }
    $parentExited = $true
    Assert-Source $q.source
    # Record actual OS boot identity before running the installer. Missing evidence never proves a reboot.
    try { $receipt.bootIdBefore = (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime.ToUniversalTime().Ticks.ToString() }
    catch { $receipt.bootIdBefore = '' }
    # JDK17 jpackage MsiWrapper passes through msiexec exit codes; no arbitrary EXE support.
    $arguments=@('/passive','/norestart','/L*v',(Join-Path $directory 'msi.log'),'AHAKEY_OTA=1',
        ('AHAKEY_SOURCE_PRODUCT='+$q.source.productCode),('AHAKEY_SOURCE_DIR='+$q.source.directory),
        ('AHAKEY_SOURCE_VERSION='+$q.source.version),('AHAKEY_SOURCE_MSI='+$q.source.msiSha256))
    $commandLine=($arguments | ForEach-Object {[AhaKey.Installation.InstalledApplication]::Quote($_)}) -join ' '
    # Normal is intentional: the passive progress window must remain visible. Only this child elevates.
    $process = Start-Process -FilePath $q.installer -Verb RunAs -WindowStyle Normal -PassThru -ArgumentList $commandLine
    if(-not $process.WaitForExit(1800000)) {
        Write-AtomicJson (Join-Path $directory 'pending.json') @{operationId=$q.operationId;requestHash=$RequestHash;state='installer-pending';detail='安装仍在进行，尚无最终结果；不会终止安装或提前重开应用。'}
        $process.WaitForExit()
    }
    $receipt.exitCode = $process.ExitCode
    $receipt.state = switch ($process.ExitCode) {
        0 { 'installed-unconfirmed' }
        3010 { 'reboot-required' }
        1641 { 'reboot-initiated' }
        1602 { 'cancelled' }
        1618 { 'installer-busy' }
        default { 'installer-failed' }
    }
} catch {
    $receipt.detail = $_.Exception.Message
    $failure=$_.Exception
    while($failure) {
        if ($failure -is [ComponentModel.Win32Exception] -and $failure.NativeErrorCode -eq 1223) { $receipt.state = 'cancelled'; $receipt.exitCode=1223; break }
        $failure=$failure.InnerException
    }
} finally {
    if ($lock) { $lock.Dispose() }
    Write-AtomicJson (Join-Path $directory 'receipt.json') $receipt
}
# This worker remains in the original user's token; the RunAs child has already exited.
# Resolve again before reopening. A failed installation is not proof of rollback.
if ($parentExited) {
    try {
        $actual=Read-Installed $q.launcher
        if($actual.directory -ine $q.source.directory){throw 'Installed directory changed'}
        $old=($actual.productCode -ieq $q.source.productCode -and $actual.version -ceq $q.source.version -and $actual.buildId -ceq $q.source.buildId)
        $new=($actual.productCode -ieq $q.targetProductCode -and $actual.version -ceq $q.version -and $actual.buildId -ceq $q.targetBuildId)
        if(($old -or $new) -and $actual.variant -ceq $q.variant -and $actual.arch -ceq $q.arch){Start-Process -FilePath $actual.launcher -WindowStyle Normal}
        else {throw 'Neither old nor target installation is verified'}
    } catch { Write-AtomicJson (Join-Path $directory 'reopen-failed.json') @{operationId=$q.operationId;detail=$_.Exception.Message} }
}
