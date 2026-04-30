# coding: utf-8
"""
录音提示音模块 — 按下/松开 CapsLock 时播放短促音效

使用 numpy 生成正弦波，sounddevice 非阻塞播放。
不依赖任何外部音频文件。
"""

from __future__ import annotations

import json
import os
import numpy as np
import sounddevice as sd

# ── 音效参数 ──────────────────────────────────────────
_SAMPLE_RATE = 44100
_NOTE_DURATION = 0.09   # 每个音符 90ms
_AMPLITUDE = 0.35       # 音量（0~1）

# 音符频率 (Hz)
_C5 = 523.25
_E5 = 659.25
_D5 = 587.33
_A4 = 440.00

# ── 共享配置文件路径（GUI 和客户端跨进程通信） ────────
CONFIG_PATH = "/tmp/capswriter_config.json"

# ── 全局开关（可被 GUI 切换） ────────────────────────
_enabled = True

# ── 预生成音效数据 ────────────────────────────────────

def _make_tone(freq: float, duration: float = _NOTE_DURATION) -> np.ndarray:
    """生成单个正弦波音符"""
    t = np.linspace(0, duration, int(_SAMPLE_RATE * duration), endpoint=False)
    # 加淡入淡出避免爆音
    envelope = np.ones_like(t)
    fade_len = int(_SAMPLE_RATE * 0.005)  # 5ms fade
    if fade_len > 0 and len(envelope) > 2 * fade_len:
        envelope[:fade_len] = np.linspace(0, 1, fade_len)
        envelope[-fade_len:] = np.linspace(1, 0, fade_len)
    return (_AMPLITUDE * np.sin(2 * np.pi * freq * t) * envelope).astype(np.float32)


def _make_start_cue() -> np.ndarray:
    """开始录音音效：升调 C5 → E5"""
    return np.concatenate([_make_tone(_C5), _make_tone(_E5)])


def _make_stop_cue() -> np.ndarray:
    """停止录音音效：降调 D5 → A4"""
    return np.concatenate([_make_tone(_D5), _make_tone(_A4)])


# 预生成，避免每次播放时计算
_start_cue = _make_start_cue()
_stop_cue = _make_stop_cue()


# ── 公开接口 ──────────────────────────────────────────

def set_enabled(enabled: bool):
    """设置提示音开关"""
    global _enabled
    _enabled = enabled


def is_enabled() -> bool:
    """获取提示音开关状态"""
    return _enabled


def _check_config():
    """从共享配置文件读取开关状态（每次播放前调用）"""
    global _enabled
    try:
        if os.path.exists(CONFIG_PATH):
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                cfg = json.load(f)
            _enabled = cfg.get("enable_audio_cue", True)
    except Exception:
        pass  # 读取失败时保持上次状态


def write_config(enable_audio_cue: bool):
    """写入共享配置文件（GUI 调用）"""
    cfg = {}
    try:
        if os.path.exists(CONFIG_PATH):
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                cfg = json.load(f)
    except Exception:
        pass
    cfg["enable_audio_cue"] = enable_audio_cue
    try:
        with open(CONFIG_PATH, "w", encoding="utf-8") as f:
            json.dump(cfg, f, ensure_ascii=False)
    except Exception:
        pass


def play_start_cue():
    """播放录音开始提示音（非阻塞）"""
    _check_config()
    if not _enabled:
        return
    try:
        sd.play(_start_cue, samplerate=_SAMPLE_RATE, blocking=False)
    except Exception:
        pass  # 静默失败，不影响录音


def play_stop_cue():
    """播放录音停止提示音（非阻塞）"""
    _check_config()
    if not _enabled:
        return
    try:
        sd.play(_stop_cue, samplerate=_SAMPLE_RATE, blocking=False)
    except Exception:
        pass  # 静默失败，不影响录音

