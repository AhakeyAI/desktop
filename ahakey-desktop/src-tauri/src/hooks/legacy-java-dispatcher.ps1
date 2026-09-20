# AhaKey Hook Dispatcher - Auto-generated, do not edit
# Receives hook event name as argument, dispatches to AhaKey Studio via TCP.
# Compatible with Claude Code, Codex, Kimi, and Cursor hooks.
param([Parameter(Position=0)][string]$EventName)
try {
    if ([Console]::IsInputRedirected) { $null = [Console]::In.ReadToEnd() }
} catch { }
try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.Connect('127.0.0.1', 8765)
    $writer = New-Object System.IO.StreamWriter($tcp.GetStream())
    $writer.WriteLine($EventName)
    $writer.Flush()
    $reader = New-Object System.IO.StreamReader($tcp.GetStream())
    $response = $reader.ReadLine()
    $tcp.Close()
} catch {
    $response = $null
}
# Codex lifecycle hooks must output exactly {} (Codex validates JSON schema)
if ($EventName -match '^Codex' -and $EventName -ne 'CodexPermissionRequest') {
    [Console]::WriteLine('{}')
    exit 0
}
# Codex PermissionRequest: output hookSpecificOutput in Codex format
if ($EventName -eq 'CodexPermissionRequest') {
    $isAuto = $response -match '"autoApproved"\s*:\s*true'
    if ($isAuto) {
        [Console]::WriteLine('{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}')
    } else {
        [Console]::WriteLine('{"hookSpecificOutput":{"hookEventName":"PermissionRequest"}}')
    }
    exit 0
}
# Claude PermissionRequest: output hookSpecificOutput in Claude format
if ($EventName -eq 'PermissionRequest') {
    $isAuto = $response -match '"autoApproved"\s*:\s*true'
    if ($isAuto) {
        [Console]::WriteLine('{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}')
    } else {
        [Console]::WriteLine('{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"ask"}}}')
    }
    exit 0
}
# Kimi / Cursor: pass through server response
if ($response) { [Console]::WriteLine($response) } else { [Console]::WriteLine('{"ok":true}') }
exit 0
