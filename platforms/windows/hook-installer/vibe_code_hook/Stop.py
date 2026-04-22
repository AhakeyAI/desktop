import sys
import json
import os


def run():
    sys.path.append(os.path.dirname(os.path.abspath(__file__)))
    from UdpLog import UdpLog

    log = UdpLog(tag="stop")
    from ble_command_send import ClaudeState, send_new_state
    try:
        ret = send_new_state(ClaudeState.CL_Stop)
        if ret is not None and ret.get("SwitchState") == 0:
            pass
    except Exception as e:
        log.error(f"error: {e}")

    try:
        raw = sys.stdin.read()
        data = json.loads(raw)

        session_id = data.get("session_id", "")
        stop_reason = data.get("stop_reason", "")

        log.info("=" * 50)
        log.info("Claude Code Stopped")
        log.info(f"session: {session_id}")
        log.info(f"reason: {stop_reason}")
        log.info("=" * 50)
    except Exception as e:
        log.error(f"Stop hook error: {e}")

    sys.exit(0)


