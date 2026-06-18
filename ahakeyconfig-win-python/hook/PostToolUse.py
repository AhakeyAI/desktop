import sys
import json
import os

    
def run():
    sys.path.append(os.path.dirname(os.path.abspath(__file__)))
    from UdpLog import UdpLog

    log = UdpLog(tag="post-tool")
    from ble_command_send import ClaudeState, send_new_state
    try:
        ret = send_new_state(ClaudeState.CL_PostToolUse)
        if ret is not None and ret.get("SwitchState") == 0:
            pass
    except Exception as e:
        log.error(f"error: {e}")

    try:
        raw = sys.stdin.read()
        data = json.loads(raw)

        tool_name = data.get("tool_name", "")
        tool_result = data.get("tool_result", "")

        result_str = str(tool_result)
        if len(result_str) > 300:
            result_str = result_str[:300] + "..."

        log.info(f"<<< {tool_name} done")
        log.info(f"  result: {result_str}")
    except Exception as e:
        log.error(f"PostToolUse hook error: {e}")

    sys.exit(0)


