# AhaKey Codex Hook - Auto-generated, do not edit
# ahakey-hook-version: ws3-cp1-v1
param([Parameter(Position=0)][string]$EventName)
. (Join-Path $env:USERPROFILE '.ahakey\hooks\ahakey-core.ps1')
# Codex PreToolUse: 拨杆手动模式 → ask 用户确认
if ($EventName -eq 'CodexPreToolUse') {
    if ($response -match '"autoApproved"\s*:\s*true') {
        [Console]::WriteLine('{"hookSpecificOutput":{"hookEventName":"PreToolUse","decision":{"behavior":"allow"}}}')
    } else {
        [Console]::WriteLine('{"hookSpecificOutput":{"hookEventName":"PreToolUse","decision":{"behavior":"ask"}}}')
    }
    exit 0
}
# Codex PermissionRequest: 拨杆手动模式 → ask 用户确认
if ($EventName -eq 'CodexPermissionRequest') {
    if ($response -match '"autoApproved"\s*:\s*true') {
        [Console]::WriteLine('{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}')
    } else {
        [Console]::WriteLine('{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"ask"}}}')
    }
    exit 0
}
# Codex 其他 lifecycle hooks must output exactly {} (Codex validates JSON schema)
[Console]::WriteLine('{}')
exit 0
