namespace AhaKey.Integrations;

public static class HookScript
{
    public static bool IsOwned(string script)=>script.StartsWith("# AhaKey Studio 2 owned hook v1\n",StringComparison.Ordinal)||script.StartsWith("# AhaKey Studio 2 owned hook v2\n",StringComparison.Ordinal);
    public static string Create(AssistantId id) => "# AhaKey Studio 2 owned hook v2\n" +
        "param([Parameter(Mandatory=$true)][string]$EventName)\n$Platform = '" + id.ToString().ToLowerInvariant() + "'\n" + """
$ErrorActionPreference = 'Stop'
$response = $null
$tcp = $null
try {
    # Optional native ownership metadata; nothing from stdin is logged or forwarded except opaque IDs.
    # Read at most 64 KiB within 150 ms. A missing/oversized payload remains unidentified.
    $message = @{cmd=$EventName}
    if ([Console]::IsInputRedirected) {
        try {
            $chars = [char[]]::new(65537)
            $used = 0
            $complete = $false
            $timer = [Diagnostics.Stopwatch]::StartNew()
            while ($used -lt $chars.Length -and $timer.ElapsedMilliseconds -lt 150) {
                $read = [Console]::In.ReadAsync($chars,$used,$chars.Length-$used)
                if (-not $read.Wait([Math]::Max(1,150-[int]$timer.ElapsedMilliseconds))) { break }
                if ($read.Result -eq 0) { $complete = $true; break }
                $used += $read.Result
            }
            if ($complete -and $used -gt 0 -and $used -le 65536) {
                $metadata = (-join $chars[0..($used-1)]) | ConvertFrom-Json
                foreach ($field in @('session_id','thread_id','conversation_id','task_id')) {
                    $value = $metadata.$field
                    if ($value -is [string] -and $value.Length -gt 0 -and $value.Length -le 256) { $message.taskId=$value; break }
                }
                if ($metadata.event_id -is [string] -and $metadata.event_id.Length -gt 0 -and $metadata.event_id.Length -le 256) { $message.eventId=$metadata.event_id }
                if ($metadata.outcome -ceq 'error') { $message.outcome='error' }
            }
        } catch { }
        $metadata = $null
        $chars = $null
    }
    $tcp = [System.Net.Sockets.TcpClient]::new()
    $connect = $tcp.ConnectAsync('127.0.0.1',8765)
    if (-not $connect.Wait(1000)) { throw 'connect-timeout' }
    $stream = $tcp.GetStream()
    $stream.ReadTimeout = 17000
    $stream.WriteTimeout = 1000
    $payload = [System.Text.Encoding]::UTF8.GetBytes(($message | ConvertTo-Json -Compress) + "`n")
    $stream.Write($payload,0,$payload.Length)
    $buffer = [byte[]]::new(512)
    $count = 0
    $ended = $false
    while ($count -lt $buffer.Length) {
        $b = $stream.ReadByte()
        if ($b -lt 0) { break }
        if ($b -eq 10) { $ended = $true; break }
        $buffer[$count++] = [byte]$b
    }
    if (-not $ended) { throw 'invalid-response' }
    $text = [System.Text.Encoding]::UTF8.GetString($buffer,0,$count).TrimEnd("`r")
    $r = $text | ConvertFrom-Json
    $names = @($r.PSObject.Properties.Name)
    if ($names.Count -eq 5 -and ($names -join ',') -ceq 'schemaVersion,platform,event,allow,approvalSource' -and
        $r.schemaVersion -eq 1 -and $r.platform -ceq $Platform -and $r.event -ceq $EventName -and $r.allow -is [bool]) {
        $canonical = '{"schemaVersion":1,"platform":"' + $Platform + '","event":"' + $EventName + '","allow":'
        foreach ($source in @('hardware-auto','user-confirmed','fail-closed','codex-fallback')) {
            $allowed = $source -ceq 'hardware-auto' -or $source -ceq 'user-confirmed'
            $boolText = if ($allowed) { 'true' } else { 'false' }
            if ($text -ceq ($canonical + $boolText + ',"approvalSource":"' + $source + '"}')) { $response = $r }
        }
    }
} catch { } finally { if ($null -ne $tcp) { $tcp.Dispose() } }
$approval = ($Platform -ceq 'claude' -and $EventName -ceq 'PermissionRequest') -or
    ($Platform -ceq 'codex' -and @('CodexPreToolUse','CodexPermissionRequest') -ccontains $EventName) -or
    ($Platform -ceq 'cursor' -and $EventName -ceq 'preToolUse')
if (-not $approval) { [Console]::WriteLine('{}'); exit 0 }
if ($Platform -ceq 'cursor') {
    if ($response -and $response.allow) { [Console]::WriteLine('{"permission":"allow"}'); exit 0 }
    [Console]::WriteLine('{"permission":"deny","user_message":"AhaKey did not approve this operation."}'); exit 1
}
if ($Platform -ceq 'codex' -and ($null -eq $response -or $response.approvalSource -ceq 'codex-fallback')) {
    # No allow decision: native Codex approval policy remains authoritative.
    [Console]::WriteLine('{}'); exit 0
}
$event = if ($EventName.StartsWith('Codex')) { $EventName.Substring(5) } else { $EventName }
$behavior = if ($response -and $response.allow) { 'allow' } else { 'ask' }
[Console]::WriteLine((@{hookSpecificOutput=@{hookEventName=$event;decision=@{behavior=$behavior}}} | ConvertTo-Json -Compress -Depth 4))
exit 0
""" + "\n";
}
