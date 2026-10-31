param([Parameter(Mandatory=$true)][string]$Request,[ValidateSet('Launch','Prepare')][string]$Mode='Launch')
$ErrorActionPreference='Stop'
$env:PSModulePath = Join-Path $PSHOME 'Modules'
$q=Get-Content -LiteralPath $Request -Raw -Encoding UTF8 | ConvertFrom-Json
$directory=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Request))
function Valid-Request {
    $id=[guid]::Empty
    if(-not [guid]::TryParse([string]$q.operationId,[ref]$id) -or [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() -gt $q.launchDeadline -or (Test-Path -LiteralPath (Join-Path $directory 'cancel.request'))){throw 'Expired or cancelled driver preparation'}
    if([IO.File]::ReadAllText((Join-Path $directory 'operation.id')) -cne $q.operationId){throw 'Operation changed'}
    $parent=Get-Process -Id $q.parentPid -ErrorAction Stop
    if($parent.HasExited -or [Math]::Abs(([DateTimeOffset]$parent.StartTime.ToUniversalTime()).ToUnixTimeMilliseconds()-[long]$q.parentStart) -gt 2){throw 'Original application exited'}
}
function Save-Result($value) {
    $value.operationId=$q.operationId;$file=Join-Path $directory 'result.json'
    if(Test-Path -LiteralPath $file){return}
    [IO.File]::WriteAllText(($file+'.tmp'),($value|ConvertTo-Json),[Text.UTF8Encoding]::new($false));[IO.File]::Move(($file+'.tmp'),$file)
}
if($Mode -eq 'Launch') {
    $supervisor=$null
    try {
        Valid-Request
        $shell=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        if($PSCommandPath.Contains('"') -or $Request.Contains('"')){throw 'Invalid path'}
        $arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Mode Prepare -Request "'+$Request+'"'
        $supervisor=Start-Process -FilePath $shell -Verb RunAs -WindowStyle Hidden -ArgumentList $arguments -PassThru
        if(-not $supervisor.WaitForExit(95000)){[IO.File]::WriteAllText((Join-Path $directory 'cancel.request'),'timeout');[void]$supervisor.WaitForExit(7000)}
    } catch {Save-Result @{ended=($null -eq $supervisor);exitCode=-1;detail=$_.Exception.Message}}
    exit
}
$result=@{ended=$true;exitCode=-1;detail='Driver preparation failed'};$child=$null;$held=[Collections.Generic.List[IO.FileStream]]::new()
try {
    Valid-Request
    $drivers=[IO.Path]::GetFullPath([string]$q.drivers)
    if(-not $drivers.EndsWith('\app\drivers\wch-ch375',[StringComparison]::OrdinalIgnoreCase) -or $drivers.Contains('"')){throw 'Invalid bundled driver directory'}
    $pins=ConvertFrom-Json '{"CH375DLL.dll":"0f019b958d4d3f6b8ec0d282ef848a57f0f92a0596d7405b6c58f5aa383a326c","CH375DLL64.dll":"5ed04e4a8eb9006e92907fdc105c4d8f915408409a02c157ca492a65d9163aa7","CH375M64.sys":"9f40d09251f58be92ee2cb769c86900d52439a5b4f7e2ca2605e26cb464602b4","CH375W64.sys":"5803220ed9da96b310397aa81db6612280f7c1a58948c02a5fe6aedf49065f5a","CH375WDM.CAT":"08a8d8b21f42635243f0a7b4bd73195a4eea22a85508b3c4fce93a181054b4ba","CH375WDM.INF":"76e5f3e96743b097c0d45d019b87c6dbef795934e2826fdade2b5e7b37b47fa4","CH375WDM.sys":"840de6b498b8f3613eeb83ee6987d90229200be125925899df0c1beb2da62d1b"}'
    foreach($entry in $pins.PSObject.Properties){
        $stream=[IO.File]::Open((Join-Path $drivers $entry.Name),'Open','Read','Read');$held.Add($stream)
        $sha=[Security.Cryptography.SHA256]::Create();try{$actual=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
        if($actual -cne $entry.Value){throw 'Bundled driver changed'}
    }
    Valid-Request
    $exe=Join-Path $env:SystemRoot 'System32/pnputil.exe';$inf=Join-Path $drivers 'CH375WDM.INF'
    # Fixed system executable and fixed vendor INF only. Never reboot, remove drivers or alter trust settings.
    $child=Start-Process -FilePath $exe -ArgumentList @('/add-driver',('"'+$inf+'"'),'/install') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $directory 'stdout.txt') -RedirectStandardError (Join-Path $directory 'stderr.txt')
    $result.ended=$false;$result.pid=$child.Id;$result.startTime=$child.StartTime.ToUniversalTime().ToString('o')
    $watch=[Diagnostics.Stopwatch]::StartNew();$failed=$false
    while(-not $child.WaitForExit(100)) {
        $parentAlive=$false;try{$p=Get-Process -Id $q.parentPid -ErrorAction Stop;$parentAlive=(-not $p.HasExited -and [Math]::Abs(([DateTimeOffset]$p.StartTime.ToUniversalTime()).ToUnixTimeMilliseconds()-[long]$q.parentStart) -le 2)}catch{}
        if($watch.ElapsedMilliseconds -ge 90000 -or -not $parentAlive -or (Test-Path -LiteralPath (Join-Path $directory 'cancel.request'))){$failed=$true;$child.Kill();break}
    }
    $result.ended=$child.WaitForExit(5000)
    if($result.ended -and -not $failed){$child.Refresh();$result.exitCode=$child.ExitCode;$result.detail='PnPUtil finished; actual device binding must be checked again'}else{$result.detail='Driver preparation cancelled or timed out'}
} catch {
    $result.detail=$_.Exception.Message
    if($null -ne $child){try{if(-not $child.HasExited){$child.Kill()};$result.ended=$child.WaitForExit(5000)}catch{$result.ended=$false}}
} finally {foreach($stream in $held){$stream.Dispose()}}
Save-Result $result
