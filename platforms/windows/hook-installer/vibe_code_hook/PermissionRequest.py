import sys
import json
import os

def run():

    sys.path.append(os.path.dirname(os.path.abspath(__file__)))
    from UdpLog import UdpLog

    log = UdpLog(tag="permission")

    auto_permit=False
    from ble_command_send import ClaudeState, send_new_state
    try:
        ret = send_new_state(ClaudeState.CL_PermissionRequest)
        if ret is not None:
            if (ret['SwitchState']==0): # auto mode
                auto_permit=True
    except Exception as e:
        log.error(f"error: {e}")


    try:
        # raw = sys.stdin.read()
        raw = '''{
    "session_id": "abc123",
    "transcript_path": "/Users/.../.claude/projects/.../00893aaf-19fa-41d2-8238-13269b9b3ca0.jsonl",
    "cwd": "/Users/...",
    "permission_mode": "default",
    "hook_event_name": "PermissionRequest",
    "tool_name": "Bash",
    "tool_input": {
        "command": "rm -rf node_modules",
        "description": "Remove node_modules directory"
    },
    "permission_suggestions": [
        { "type": "toolAlwaysAllow", "tool": "Bash" }
    ]
    }'''
        data = json.loads(raw)

        tool_name = data.get("tool_name", "Unknown")
        tool_input = data.get("tool_input", {})

        log.info(f"Permission requested for tool: {tool_name}")

        log.info(f"User decision: {auto_permit}")


    except Exception as e:
        log.error(f"PermissionRequest hook error: {e}")

    if True == auto_permit:
        output = {
            "hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": {
                    "behavior": "allow"
                }
            }
        }
    else:
        output = {
            "hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": {
                    "behavior": "ask"
                }
            }
        }
    print(json.dumps(output))
    sys.exit(0)
