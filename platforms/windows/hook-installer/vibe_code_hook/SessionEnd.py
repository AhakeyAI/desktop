import sys
import json
import os


def run():
    sys.path.append(os.path.dirname(os.path.abspath(__file__)))
    from UdpLog import UdpLog

    log = UdpLog(tag="session end")
    from ble_command_send import ClaudeState, send_new_state
    try:
        ret = send_new_state(ClaudeState.CL_SessionEnd)
        if ret is not None and ret.get("SwitchState") == 0:
            pass
    except Exception as e:
        log.error(f"error: {e}")

    try:
        raw = sys.stdin.read()
        data = json.loads(raw)

        session_id = data.get("session_id", "")
        transcript_path = data.get("transcript_path", "")
        reason = data.get("reason", "")
        cwd = data.get("cwd", "")
        permission_mode = data.get("permission_mode", "")

        log.info("=" * 50)
        log.info(f"Session end ({reason})")
        log.info(f"session: {session_id}")
        log.info(f"transcript_path: {transcript_path}")
        log.info(f"cwd: {cwd}")
        log.info(f"mode: {permission_mode}")
        log.info("=" * 50)
    except Exception as e:
        log.error(f"SessionEnd hook error: {e}")

    sys.exit(0)


