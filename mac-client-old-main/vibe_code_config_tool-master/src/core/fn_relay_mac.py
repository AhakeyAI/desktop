"""macOS F19 -> Fn/Globe relay."""

from __future__ import annotations

import sys
import threading
import time

_SUPPORTED = sys.platform == "darwin"
_QUARTZ_LOADED = False

F19_KEYCODE = 80
FN_KEYCODE = 63
_EMOJI_SHADOW_KEYCODE = 179
_SHADOW_SUPPRESS_SECONDS = 0.06

_tap_port = None
_run_loop_source = None
_shadow_suppress_until = 0.0
_started = False
_lock = threading.Lock()


def _load_quartz() -> bool:
    global _QUARTZ_LOADED
    global CFMachPortCreateRunLoopSource
    global CFRunLoopAddSource
    global CFRunLoopGetCurrent
    global CFRunLoopRun
    global CGEventCreateKeyboardEvent
    global CGEventGetIntegerValueField
    global CGEventPost
    global CGEventSetFlags
    global CGEventTapCreate
    global CGEventTapEnable
    global kCFRunLoopCommonModes
    global kCGEventFlagMaskSecondaryFn
    global kCGEventKeyDown
    global kCGEventKeyUp
    global kCGHeadInsertEventTap
    global kCGHIDEventTap
    global kCGKeyboardEventKeycode
    global kCGSessionEventTap

    if _QUARTZ_LOADED:
        return True
    if not _SUPPORTED:
        return False

    try:
        from Quartz import (
            CFMachPortCreateRunLoopSource as _CFMachPortCreateRunLoopSource,
            CFRunLoopAddSource as _CFRunLoopAddSource,
            CFRunLoopGetCurrent as _CFRunLoopGetCurrent,
            CFRunLoopRun as _CFRunLoopRun,
            CGEventCreateKeyboardEvent as _CGEventCreateKeyboardEvent,
            CGEventGetIntegerValueField as _CGEventGetIntegerValueField,
            CGEventPost as _CGEventPost,
            CGEventSetFlags as _CGEventSetFlags,
            CGEventTapCreate as _CGEventTapCreate,
            CGEventTapEnable as _CGEventTapEnable,
            kCFRunLoopCommonModes as _kCFRunLoopCommonModes,
            kCGEventFlagMaskSecondaryFn as _kCGEventFlagMaskSecondaryFn,
            kCGEventKeyDown as _kCGEventKeyDown,
            kCGEventKeyUp as _kCGEventKeyUp,
            kCGHeadInsertEventTap as _kCGHeadInsertEventTap,
            kCGHIDEventTap as _kCGHIDEventTap,
            kCGKeyboardEventKeycode as _kCGKeyboardEventKeycode,
            kCGSessionEventTap as _kCGSessionEventTap,
        )
    except Exception:
        return False

    CFMachPortCreateRunLoopSource = _CFMachPortCreateRunLoopSource
    CFRunLoopAddSource = _CFRunLoopAddSource
    CFRunLoopGetCurrent = _CFRunLoopGetCurrent
    CFRunLoopRun = _CFRunLoopRun
    CGEventCreateKeyboardEvent = _CGEventCreateKeyboardEvent
    CGEventGetIntegerValueField = _CGEventGetIntegerValueField
    CGEventPost = _CGEventPost
    CGEventSetFlags = _CGEventSetFlags
    CGEventTapCreate = _CGEventTapCreate
    CGEventTapEnable = _CGEventTapEnable
    kCFRunLoopCommonModes = _kCFRunLoopCommonModes
    kCGEventFlagMaskSecondaryFn = _kCGEventFlagMaskSecondaryFn
    kCGEventKeyDown = _kCGEventKeyDown
    kCGEventKeyUp = _kCGEventKeyUp
    kCGHeadInsertEventTap = _kCGHeadInsertEventTap
    kCGHIDEventTap = _kCGHIDEventTap
    kCGKeyboardEventKeycode = _kCGKeyboardEventKeycode
    kCGSessionEventTap = _kCGSessionEventTap
    _QUARTZ_LOADED = True
    return True


def _post_fn_event(is_key_down: bool) -> None:
    event = CGEventCreateKeyboardEvent(None, FN_KEYCODE, is_key_down)
    if event is None:
        return
    if is_key_down:
        CGEventSetFlags(event, kCGEventFlagMaskSecondaryFn)
    CGEventPost(kCGHIDEventTap, event)


def _event_callback(_proxy, event_type, event, _refcon):
    global _shadow_suppress_until

    keycode = int(CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode))
    now = time.monotonic()

    if keycode == _EMOJI_SHADOW_KEYCODE and now <= _shadow_suppress_until:
        return None

    if keycode != F19_KEYCODE:
        return event

    if event_type == kCGEventKeyDown:
        _post_fn_event(True)
    elif event_type == kCGEventKeyUp:
        _post_fn_event(False)
        _shadow_suppress_until = now + _SHADOW_SUPPRESS_SECONDS

    return None


def _run_event_tap() -> None:
    global _tap_port, _run_loop_source

    if not _load_quartz():
        print(
            "[Fn映射] 无法加载 Quartz 事件接口，已跳过 Mac Fn Relay。",
            flush=True,
        )
        return

    mask = (1 << kCGEventKeyDown) | (1 << kCGEventKeyUp)
    _tap_port = CGEventTapCreate(
        kCGSessionEventTap,
        kCGHeadInsertEventTap,
        0,
        mask,
        _event_callback,
        None,
    )

    if _tap_port is None:
        print(
            "[Fn映射] 无法创建事件监听。请到 系统设置 -> 隐私与安全性 -> 输入监控/辅助功能 中为 Vibecoding Keyboard 开启权限。",
            flush=True,
        )
        return

    _run_loop_source = CFMachPortCreateRunLoopSource(None, _tap_port, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), _run_loop_source, kCFRunLoopCommonModes)
    CGEventTapEnable(_tap_port, True)
    print("[Fn映射] 已启动：Mac Fn Relay (F19) -> Fn/Globe", flush=True)
    CFRunLoopRun()


def start_mac_fn_relay() -> bool:
    """Start the macOS-only F19 -> Fn relay once."""
    global _started

    if not _SUPPORTED:
        return False

    with _lock:
        if _started:
            return True
        _started = True

    thread = threading.Thread(target=_run_event_tap, name="MacFnRelay", daemon=True)
    thread.start()
    return True
