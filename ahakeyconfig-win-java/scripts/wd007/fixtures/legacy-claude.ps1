# AhaKey Claude Hook - Auto-generated, do not edit
param([Parameter(Position=0)][string]$EventName)
. (Join-Path $env:USERPROFILE '.ahakey\hooks\ahakey-core.ps1')
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
# Claude lifecycle events: pass through server response
if ($response) { [Console]::WriteLine($response) } else { [Console]::WriteLine('{"ok":true}') }
exit 0
