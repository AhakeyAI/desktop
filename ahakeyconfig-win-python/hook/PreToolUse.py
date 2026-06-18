import sys
import json
import os


def run():
    sys.path.append(os.path.dirname(os.path.abspath(__file__)))
    from UdpLog import UdpLog

    log = UdpLog(tag="pre-tool")
    from ble_command_send import ClaudeState, send_new_state
    try:
        ret = send_new_state(ClaudeState.CL_PreToolUse)
        if ret is not None and ret.get("SwitchState") == 0:
            pass
    except Exception as e:
        log.error(f"error: {e}")

    try:
        raw = sys.stdin.read()
        data = json.loads(raw)

        tool_name = data.get("tool_name", "")
        tool_input = data.get("tool_input", {})

        log.info(f">>> {tool_name}")
        if isinstance(tool_input, dict):
            for key, value in tool_input.items():
                val_str = str(value)
                if len(val_str) > 200:
                    val_str = val_str[:200] + "..."
                log.info(f"  {key}: {val_str}")
    except Exception as e:
        log.error(f"PreToolUse hook error: {e}")

    sys.exit(0)


