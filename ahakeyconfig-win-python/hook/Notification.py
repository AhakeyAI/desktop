import sys
import json
import os

def run():
    sys.path.append(os.path.dirname(os.path.abspath(__file__)))
    from UdpLog import UdpLog

    log = UdpLog(tag="notification")

    from ble_command_send import ClaudeState, send_new_state
    try:
        ret = send_new_state(ClaudeState.CL_Notification)
        if ret is not None:
            if (ret['SwitchState']==0): # auto mode
                pass
    except Exception as e:
        log.error(f"error: {e}")

    try:
        raw = sys.stdin.read()
        data = json.loads(raw)

        notification_type = data.get("type", "")
        message = data.get("message", "")
        session_id = data.get("session_id", "")

        log.info(f"Notification [{notification_type}]")
        if message:
            log.info(f"  message: {message}")
        log.info(f"  session: {session_id}")
    except Exception as e:
        log.error(f"Notification hook error: {e}")

    sys.exit(0)
