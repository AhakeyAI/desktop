import sys
import json
import os
def run():

    sys.path.append(os.path.dirname(os.path.abspath(__file__)))
    from UdpLog import UdpLog

    log = UdpLog(tag="task-done")
    from ble_command_send import ClaudeState, send_new_state
    try:
        ret = send_new_state(ClaudeState.CL_TaskCompleted)
        if ret is not None:
            if (ret['SwitchState']==0): # auto mode
                pass
    except Exception as e:
        log.error(f"error: {e}")

    try:
        raw = sys.stdin.read()
        data = json.loads(raw)

        session_id = data.get("session_id", "")
        cwd = data.get("cwd", "")

        log.info("=" * 50)
        log.info("Task Completed")
        log.info(f"  session: {session_id}")
        log.info(f"  cwd: {cwd}")
        log.info("=" * 50)
    except Exception as e:
        log.error(f"TaskCompleted hook error: {e}")

    sys.exit(0)
