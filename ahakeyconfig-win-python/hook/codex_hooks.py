"""
OpenAI Codex CLI hooks 专用入口（由 ~/.codex/hooks.json 或旧版 config.toml 内联块调用）。

与 Claude 的差别：需在 stdout 输出合法 JSON；状态类事件使用 hookSpecificOutput.hookEventName（与文档一致）。
PermissionRequest：自动批准输出 decision.allow；手动档不可使用 Claude 的 ask，仅回 hookEventName。
"""

import json
import os
import sys
import threading

_hook_dir = os.path.dirname(os.path.abspath(__file__))
if _hook_dir not in sys.path:
    sys.path.insert(0, _hook_dir)

from ble_command_send import ClaudeState, send_new_state  # noqa: E402
from hook_diag import diag_line
from UdpLog import UdpLog  # noqa: E402


def drain_stdin_text(timeout_seconds: float) -> str:
    """Read hook stdin with upper bound wait.

    When Codex (or CMD) attaches an interactive console stdin instead of a pipe with
    closed writer, ``sys.stdin.read()`` blocks forever → hook times out and appears as
    exit code 1.
    """

    holder: dict[str, str | None] = {"raw": None}

    def _read() -> None:
        try:
            holder["raw"] = sys.stdin.read()
        except Exception:
            holder["raw"] = ""

    t = threading.Thread(target=_read, daemon=True)
    t.start()
    t.join(timeout_seconds)
    if holder["raw"] is None:
        return ""
    return holder["raw"] or ""


def _run_codex_state(
    tag: str,
    state: ClaudeState,
    codex_event_name: str,
    stdin_timeout_seconds: float,
) -> None:
    diag_line(tag.replace(" ", "_"), f"enter state={state.name}")

    log = UdpLog(tag=tag)
    ret = None
    try:
        ret = send_new_state(state)
        if ret is not None and ret.get("SwitchState") == 0:
            diag_line(tag.replace(" ", "_"), "send_new_state ok auto_switch")
        elif ret is None:
            diag_line(tag.replace(" ", "_"), "send_new_state ret=None (桥未连或非目标设备)")
        else:
            diag_line(
                tag.replace(" ", "_"),
                f"send_new_state ok SwitchState={ret.get('SwitchState')}",
            )
    except Exception as e:
        log.error(f"error: {e}")
        diag_line(tag.replace(" ", "_"), f"send_new_state EXCEPTION {e}")

    diag_line(tag.replace(" ", "_"), "skip stdin drain")

    payload = {}
    diag_line(tag.replace(" ", "_"), f"stdout empty json for {codex_event_name!r}")
    print(json.dumps(payload), flush=True)
    sys.exit(0)


def run_codex_session_start():
    _run_codex_state(
        "codex SessionStart",
        ClaudeState.CL_SessionStart,
        "SessionStart",
        3.0,
    )


def run_codex_post_tool_use():
    _run_codex_state(
        "codex PostToolUse",
        ClaudeState.CL_PostToolUse,
        "PostToolUse",
        8.0,
    )


def run_codex_pre_tool_use():
    _run_codex_state(
        "codex PreToolUse",
        ClaudeState.CL_PreToolUse,
        "PreToolUse",
        18.0,
    )


def run_codex_user_prompt_submit():
    _run_codex_state(
        "codex UserPromptSubmit",
        ClaudeState.CL_UserPromptSubmit,
        "UserPromptSubmit",
        8.0,
    )


def run_codex_stop():
    _run_codex_state(
        "codex Stop",
        ClaudeState.CL_Stop,
        "Stop",
        6.0,
    )


def run_codex_permission_request():
    diag_line("codex_PermissionRequest", "enter")

    log = UdpLog(tag="codex permission")
    diag_line("codex_PermissionRequest", "skip stdin drain")

    is_auto = False
    try:
        ret = send_new_state(ClaudeState.CL_PermissionRequest)
        if ret is not None and ret.get("SwitchState") == 0:
            is_auto = True
            diag_line("codex_PermissionRequest", "allow(auto SwitchState=0)")
        elif ret is None:
            diag_line("codex_PermissionRequest", "ret=None 交回 Codex")
        else:
            diag_line(
                "codex_PermissionRequest",
                f"non-auto SwitchState={ret.get('SwitchState')}",
            )
    except Exception as e:
        log.error(f"error: {e}")
        diag_line("codex_PermissionRequest", f"EXCEPTION {e}")

    hook_out: dict = {"hookEventName": "PermissionRequest"}
    if is_auto:
        hook_out["decision"] = {"behavior": "allow"}

    diag_line("codex_PermissionRequest", f"stdout decision auto={is_auto}")
    print(json.dumps({"hookSpecificOutput": hook_out}), flush=True)
    sys.exit(0)
