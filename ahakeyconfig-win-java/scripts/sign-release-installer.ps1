param([switch]$Initialize, [string]$Executable, [string]$Output, [string]$IdentityJson)
$ErrorActionPreference = 'Stop'
$env:PSModulePath = Join-Path $PSHOME 'Modules'
$sourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$signingRoot = Join-Path $env:LOCALAPPDATA 'AhaKeyStudio/release-signing/production-rsa3072-v1'
$privatePath = Join-Path $signingRoot 'private-key.xml'
$publicPath = Join-Path $sourceRoot 'src/main/resources/update/release-public-key.json'
$workerPath = Join-Path $sourceRoot 'src/main/resources/update/windows-update-worker.ps1'
$rsa = [Security.Cryptography.RSACryptoServiceProvider]::new(3072)
$rsa.PersistKeyInCsp = $false
try {
    if ($Initialize) {
        if (-not (Test-Path -LiteralPath $signingRoot)) { New-Item -ItemType Directory -Path $signingRoot | Out-Null }
        $acl = [Security.AccessControl.DirectorySecurity]::new()
        $acl.SetAccessRuleProtection($true,$false)
        $userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
        foreach ($sid in @($userSid,[Security.Principal.SecurityIdentifier]::new('S-1-5-18'))) {
            $rule = [Security.AccessControl.FileSystemAccessRule]::new($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
            $acl.AddAccessRule($rule)
        }
        Set-Acl -LiteralPath $signingRoot -AclObject $acl
        if (Test-Path -LiteralPath $privatePath) { $rsa.FromXmlString([IO.File]::ReadAllText($privatePath)) }
        else {
            if (Test-Path -LiteralPath $publicPath) { throw 'Public key exists but private key is absent; restore the original private key, never rotate silently.' }
            [IO.File]::WriteAllText($privatePath,$rsa.ToXmlString($true),[Text.UTF8Encoding]::new($false))
        }
        if ($rsa.KeySize -ne 3072) { throw 'Unexpected private key size' }
        $public = $rsa.ExportParameters($false)
        $modulus = [Convert]::ToBase64String($public.Modulus)
        $exponent = [Convert]::ToBase64String($public.Exponent)
        if ($exponent -cne 'AQAB') { throw 'Unexpected exponent' }
        if (Test-Path -LiteralPath $publicPath) {
            $existing = Get-Content -LiteralPath $publicPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($existing.modulus -cne $modulus -or $existing.exponent -cne $exponent) { throw 'Public key mismatch; refusing replacement' }
        } else {
            [IO.File]::WriteAllText($publicPath,(@{schema=1;keyId='production-rsa3072-v1';modulus=$modulus;exponent=$exponent}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
        }
        $worker = [IO.File]::ReadAllText($workerPath)
        if ($worker.Contains('__RELEASE_MODULUS__')) { [IO.File]::WriteAllText($workerPath,$worker.Replace('__RELEASE_MODULUS__',$modulus),[Text.UTF8Encoding]::new($false)) }
        elseif (-not $worker.Contains($modulus)) { throw 'Worker fixed key mismatch' }
        Write-Output "Production public key bound. Private key retained only at $signingRoot"
        return
    }
    if (-not (Test-Path -LiteralPath $privatePath)) { throw 'Initialize the authorized signing key first.' }
    $rsa.FromXmlString([IO.File]::ReadAllText($privatePath))
    $public = Get-Content -LiteralPath $publicPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($rsa.KeySize -ne 3072 -or [Convert]::ToBase64String($rsa.ExportParameters($false).Modulus) -cne $public.modulus) { throw 'Signing key does not match installed public key' }
    $identity = Get-Content -LiteralPath $IdentityJson -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($identity.version -notmatch '^(0|[1-9][0-9]{0,4})\.(0|[1-9][0-9]{0,4})\.(0|[1-9][0-9]{0,4})$' -or $identity.variant -cnotin @('lite','local-model') -or $identity.arch -cne 'x64' -or $identity.productName -cne 'AhaKeyStudio' -or $identity.upgradeCode -ine '{03E5A934-FFCA-3815-B455-7D49BF1CA1DC}' -or $identity.productCode -notmatch '^\{[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}\}$') { throw 'Actual MSI identity invalid' }
    $inputFile = [IO.File]::Open($Executable,'Open','Read','Read')
    try {
        if ($inputFile.Length -lt 2 -or $inputFile.Length -gt 2147480000 -or $inputFile.ReadByte() -ne 77 -or $inputFile.ReadByte() -ne 90) { throw 'Invalid EXE prefix' }
        if ($inputFile.Length -ge 16) { $inputFile.Position=$inputFile.Length-16; $marker=[byte[]]::new(8); [void]$inputFile.Read($marker,0,8); if([Text.Encoding]::ASCII.GetString($marker) -ceq 'AHAKEND1'){throw 'Already signed'} }
        $inputFile.Position=0; $sha=[Security.Cryptography.SHA256]::Create()
        try { $digest=$sha.ComputeHash($inputFile) } finally { $sha.Dispose() }
        $payloadStream=[IO.MemoryStream]::new(); $writer=[IO.BinaryWriter]::new($payloadStream)
        try {
            $writer.Write([Text.Encoding]::ASCII.GetBytes('AHAKSIG1'));$writer.Write([uint64]$inputFile.Length);$writer.Write($digest)
            foreach($value in @($identity.version,$identity.variant,$identity.arch,$identity.productName,$identity.upgradeCode,$identity.productCode)){
                $bytes=[Text.UTF8Encoding]::new($false,$true).GetBytes($value)
                if($bytes.Length -lt 1 -or $bytes.Length -gt 128 -or $value -match '[\x00-\x1f\x7f]'){throw 'Invalid signature field'}
                $writer.Write([uint16]$bytes.Length);$writer.Write($bytes)
            }
            $payload=$payloadStream.ToArray()
        } finally {$writer.Dispose();$payloadStream.Dispose()}
        $signature=$rsa.SignData($payload,[Security.Cryptography.CryptoConfig]::MapNameToOID('SHA256'))
        $destination=[IO.File]::Open($Output,'CreateNew','Write','None')
        try {
            $inputFile.Position=0;$inputFile.CopyTo($destination)
            $destination.Write($payload,0,$payload.Length);$destination.Write($signature,0,$signature.Length)
            $tail=[IO.BinaryWriter]::new($destination);$tail.Write([Text.Encoding]::ASCII.GetBytes('AHAKEND1'));$tail.Write([uint32]$payload.Length);$tail.Write([uint32]1);$tail.Flush()
            $destination.Flush($true)
        } finally {$destination.Dispose()}
    } finally {$inputFile.Dispose()}
    Write-Output 'Signed final EXE; do not change its bytes after this step.'
} finally { $rsa.Dispose() }
