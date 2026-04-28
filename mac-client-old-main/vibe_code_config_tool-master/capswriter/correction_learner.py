# coding: utf-8
"""
纠错自动学习模块 — 检测用户对粘贴文本的手动修正，自动添加到 hot.txt

原理：
  1. 粘贴识别结果后，记录原始文本
  2. 延迟数秒后，通过 macOS Accessibility API 读取当前输入框的文本
  3. 用 LCS（最长公共子序列）对比原始文本和编辑后文本
  4. 提取用户的替换修正（如 "课大讯飞" → "科大讯飞"）
  5. 将修正词自动追加到 hot.txt

通过 /tmp/capswriter_config.json 读取配置：
  enable_correction_learner: bool — 总开关
  correction_delay: int — 粘贴后等待秒数（默认 8）
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import threading
import time

# ── 共享配置路径 ──
CONFIG_PATH = "/tmp/capswriter_config.json"


def _read_config() -> dict:
    """读取共享配置文件"""
    try:
        if os.path.exists(CONFIG_PATH):
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                return json.load(f)
    except Exception:
        pass
    return {}


def _get_hot_txt_path() -> str:
    """获取 hot.txt 的路径（与本文件同目录）"""
    env_home = (os.environ.get("CAPSWRITER_HOME") or "").strip()
    if env_home:
        candidate = os.path.join(os.path.abspath(os.path.expanduser(env_home)), "hot.txt")
        if os.path.isfile(candidate):
            return candidate
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "hot.txt")


def read_focused_text() -> str:
    """
    通过 macOS Accessibility API 读取当前聚焦输入框的文本内容。
    需要辅助功能权限。
    """
    if sys.platform == "darwin":
        # 这里原先走 System Events，会触发“允许控制 System Events”的自动化弹窗，
        # 对正常语音输入不是必需能力，先关闭这条学习读取链，避免干扰主流程。
        return ""

    script = '''
tell application "System Events"
    tell (first application process whose frontmost is true)
        try
            set focusedElem to value of attribute "AXFocusedUIElement"
            return value of focusedElem
        on error
            return ""
        end try
    end tell
end tell
'''
    try:
        result = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True, text=True, timeout=5,
        )
        return result.stdout.strip()
    except Exception:
        return ""


def _tokenize_chinese(text: str) -> list:
    """
    中文按字符分词，英文按空格分词。
    返回 token 列表。
    """
    tokens = []
    buf = []
    for ch in text:
        if re.match(r'[\u4e00-\u9fff\u3000-\u303f\uff00-\uffef]', ch):
            # CJK 字符：先清空英文缓冲，再加单字
            if buf:
                tokens.append("".join(buf))
                buf.clear()
            tokens.append(ch)
        elif ch.isspace():
            if buf:
                tokens.append("".join(buf))
                buf.clear()
        else:
            buf.append(ch)
    if buf:
        tokens.append("".join(buf))
    return tokens


def _lcs_alignment(orig_tokens: list, edited_tokens: list) -> list:
    """
    LCS 对齐，返回 [(orig_token_or_None, edited_token_or_None), ...] 对齐序列。
    """
    m, n = len(orig_tokens), len(edited_tokens)
    dp = [[0] * (n + 1) for _ in range(m + 1)]

    for i in range(1, m + 1):
        for j in range(1, n + 1):
            if orig_tokens[i - 1] == edited_tokens[j - 1]:
                dp[i][j] = dp[i - 1][j - 1] + 1
            else:
                dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])

    # 回溯
    aligned = []
    i, j = m, n
    while i > 0 or j > 0:
        if i > 0 and j > 0 and orig_tokens[i - 1] == edited_tokens[j - 1]:
            aligned.append((orig_tokens[i - 1], edited_tokens[j - 1]))
            i -= 1
            j -= 1
        elif j > 0 and (i == 0 or dp[i][j - 1] >= dp[i - 1][j]):
            aligned.append((None, edited_tokens[j - 1]))
            j -= 1
        else:
            aligned.append((orig_tokens[i - 1], None))
            i -= 1
    aligned.reverse()

    return aligned, dp[m][n]


def _extract_substitutions(aligned: list) -> list:
    """
    从对齐结果中提取连续的替换对 [(原始片段, 修正片段), ...]。
    只提取 delete+insert 块（即用户把一段文字改成了另一段）。
    如果替换块过大，递归用字符级 LCS 提取最小差异。
    """
    subs = []
    k = 0
    while k < len(aligned):
        orig_w, edit_w = aligned[k]
        if orig_w is not None and edit_w is None:
            # 开始收集连续删除
            deleted = [orig_w]
            j = k + 1
            while j < len(aligned):
                nw_o, nw_e = aligned[j]
                if nw_o is not None and nw_e is None:
                    deleted.append(nw_o)
                    j += 1
                else:
                    break
            # 收集紧跟的连续插入
            inserted = []
            while j < len(aligned):
                nw_o, nw_e = aligned[j]
                if nw_o is None and nw_e is not None:
                    inserted.append(nw_e)
                    j += 1
                else:
                    break
            if deleted and inserted:
                orig_str = "".join(deleted)
                edit_str = "".join(inserted)
                # 如果替换块太大（>6字符），尝试缩小范围
                if len(orig_str) > 6 or len(edit_str) > 6:
                    # 去掉两端相同的部分，找到真正不同的核心
                    trimmed = _trim_common_affixes(orig_str, edit_str)
                    if trimmed:
                        subs.append(trimmed)
                else:
                    subs.append((orig_str, edit_str))
            k = j
        else:
            k += 1
    return subs


def _trim_common_affixes(orig: str, edit: str) -> tuple:
    """
    去掉两个字符串首尾相同的部分，只保留中间真正不同的核心。
    例如: "今天去见了张心洋开会" vs "今天去见了张新阳开会"
         → ("心洋", "新阳")
    """
    # 去掉共同前缀
    prefix_len = 0
    min_len = min(len(orig), len(edit))
    while prefix_len < min_len and orig[prefix_len] == edit[prefix_len]:
        prefix_len += 1

    # 去掉共同后缀
    suffix_len = 0
    while (suffix_len < min_len - prefix_len
           and orig[len(orig) - 1 - suffix_len] == edit[len(edit) - 1 - suffix_len]):
        suffix_len += 1

    core_orig = orig[prefix_len:len(orig) - suffix_len if suffix_len else len(orig)]
    core_edit = edit[prefix_len:len(edit) - suffix_len if suffix_len else len(edit)]

    if not core_orig and not core_edit:
        return None  # 完全相同
    if not core_edit:
        return None  # 只有删除，没有替换

    return (core_orig, core_edit)


def extract_corrections(original_text: str, edited_text: str,
                        existing_hotwords: set = None) -> list:
    """
    对比原始文本和编辑后文本，提取用户的修正词。

    返回: [(原始词, 修正词), ...] — 可以添加到 hot.txt 的修正对
    """
    if not original_text or not edited_text:
        return []
    if original_text.strip() == edited_text.strip():
        return []

    orig_tokens = _tokenize_chinese(original_text.strip())
    edited_tokens = _tokenize_chinese(edited_text.strip())

    if not orig_tokens or not edited_tokens:
        return []

    # 如果变化太大，认为是重写而非修正
    aligned, lcs_len = _lcs_alignment(orig_tokens, edited_tokens)
    max_len = max(len(orig_tokens), len(edited_tokens))
    unchanged_ratio = lcs_len / max_len if max_len > 0 else 0

    # 短文本（<10字符）放宽阈值：改2个字就有60%变化率，这很正常
    min_ratio = 0.15 if max_len <= 10 else 0.4
    print(f"[学习-DEBUG] LCS: lcs_len={lcs_len}, max_len={max_len}, ratio={unchanged_ratio:.2f}, threshold={min_ratio}", flush=True)
    if unchanged_ratio < min_ratio:
        # 太多变化，可能是整段重写
        print(f"[学习-DEBUG] 变化率过高，跳过", flush=True)
        return []

    subs = _extract_substitutions(aligned)
    print(f"[学习-DEBUG] 替换对: {subs}", flush=True)
    if not subs:
        return []

    existing = existing_hotwords or set()
    results = []

    for orig_word, corrected_word in subs:
        # 过滤：修正词不能太长（热词一般 2~6 个字）
        if len(corrected_word) > 8 or len(corrected_word) < 1:
            print(f"[学习-DEBUG] 跳过(长度): '{corrected_word}' len={len(corrected_word)}", flush=True)
            continue
        # 过滤：原始词和修正词完全相同（大小写除外）
        if orig_word.lower() == corrected_word.lower():
            continue
        # 过滤：已存在于热词表
        if corrected_word in existing or corrected_word.lower() in existing:
            print(f"[学习-DEBUG] 跳过(已存在): '{corrected_word}'", flush=True)
            continue
        # 过滤：纯标点或空白
        if not re.search(r'[\u4e00-\u9fffA-Za-z0-9]', corrected_word):
            continue
        results.append((orig_word, corrected_word))

    return results


def _load_existing_hotwords() -> set:
    """读取 hot.txt 中已有的热词集合"""
    path = _get_hot_txt_path()
    words = set()
    try:
        if os.path.exists(path):
            with open(path, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith("#"):
                        words.add(line)
                        words.add(line.lower())
    except Exception:
        pass
    return words


def append_to_hot_txt(corrections: list) -> int:
    """
    将修正词追加到 hot.txt 末尾。

    参数: corrections — [(原始词, 修正词), ...]
    返回: 实际追加的条数
    """
    if not corrections:
        return 0

    path = _get_hot_txt_path()
    existing = _load_existing_hotwords()
    to_add = []

    for orig, corrected in corrections:
        if corrected not in existing and corrected.lower() not in existing:
            to_add.append(corrected)
            existing.add(corrected)

    if not to_add:
        return 0

    try:
        with open(path, "a", encoding="utf-8") as f:
            f.write("\n# ==================== 自动学习 ====================\n")
            for word in to_add:
                f.write(f"{word}\n")
        print(f"[学习] 已添加 {len(to_add)} 个热词到 hot.txt: {to_add}", flush=True)
        return len(to_add)
    except Exception as e:
        print(f"[学习] 写入 hot.txt 失败: {e}", flush=True)
        return 0


# ── 全局状态：记录最近一次粘贴 ──
_last_paste = {
    "text": "",
    "time": 0.0,
}
_timer = None  # type: threading.Timer


def _char_overlap_score(text_a: str, text_b: str) -> float:
    """计算两段文本的字符重叠率 (0~1)"""
    if not text_a or not text_b:
        return 0.0
    chars_a = {}
    for ch in text_a:
        chars_a[ch] = chars_a.get(ch, 0) + 1
    chars_b = {}
    for ch in text_b:
        chars_b[ch] = chars_b.get(ch, 0) + 1
    overlap = sum(min(chars_a.get(ch, 0), cnt) for ch, cnt in chars_b.items())
    return overlap / max(len(text_a), len(text_b))


def _extract_relevant_region(original: str, full_text: str) -> str:
    """
    从输入框的完整文本中，截取与原始粘贴文本最相关的区域。

    策略：
    1. 按换行拆分成行
    2. 找出与 original 最匹配的单行或连续多行
    3. 如果行级匹配不够好，回退到滑动窗口
    """
    orig_len = len(original)
    full_len = len(full_text)

    if full_len <= orig_len * 3:
        return full_text

    # ── 策略1：按行匹配 ──
    lines = full_text.split("\n")
    if len(lines) > 1:
        best_line_score = 0.0
        best_line_text = ""

        for i, line in enumerate(lines):
            if not line.strip():
                continue
            # 单行匹配
            score = _char_overlap_score(original, line)
            if score > best_line_score:
                best_line_score = score
                best_line_text = line

            # 连续 2~3 行合并匹配（原文可能跨行）
            for span in [2, 3]:
                if i + span <= len(lines):
                    combined = "\n".join(lines[i:i + span])
                    score = _char_overlap_score(original, combined)
                    if score > best_line_score:
                        best_line_score = score
                        best_line_text = combined

        # 如果行级匹配足够好（>60% 重叠），直接用
        if best_line_score > 0.6 and best_line_text:
            return best_line_text

    # ── 策略2：回退到滑动窗口 ──
    window = int(orig_len * 1.8)
    if window > full_len:
        return full_text

    best_score = -1
    best_start = max(0, full_len - window)

    orig_chars = {}
    for ch in original:
        orig_chars[ch] = orig_chars.get(ch, 0) + 1

    for start in range(0, full_len - window + 1):
        segment = full_text[start:start + window]
        seg_chars = {}
        for ch in segment:
            seg_chars[ch] = seg_chars.get(ch, 0) + 1
        score = sum(min(orig_chars.get(ch, 0), cnt) for ch, cnt in seg_chars.items())
        if score > best_score:
            best_score = score
            best_start = start

    return full_text[best_start:best_start + window]


def _do_learn():
    """延迟后执行：读取当前输入框文本，与粘贴文本对比，提取修正"""
    original = _last_paste["text"]
    if not original:
        return

    edited = read_focused_text()
    if not edited:
        print("[学习] 无法读取当前输入框文本（可能不是文本输入区域）", flush=True)
        return

    print(f"[学习-DEBUG] 原始粘贴: '{original}' ({len(original)}字符)", flush=True)
    print(f"[学习-DEBUG] 输入框读回: '{edited[:100]}' ({len(edited)}字符)", flush=True)

    # 从输入框文本中截取与粘贴内容最相关的区域
    edited = _extract_relevant_region(original, edited)
    print(f"[学习-DEBUG] 区域截取后: '{edited[:100]}' ({len(edited)}字符)", flush=True)

    existing = _load_existing_hotwords()
    corrections = extract_corrections(original, edited, existing)

    if corrections:
        count = append_to_hot_txt(corrections)
        if count > 0:
            for orig, corrected in corrections:
                print(f"[学习] 纠正: {orig} → {corrected}", flush=True)
    else:
        elapsed = time.time() - _last_paste["time"]
        print(f"[学习] 检查完成 ({elapsed:.1f}s后)，未检测到修正", flush=True)


def schedule_learning(original_text: str):
    """
    粘贴文本后调用此函数，延迟后自动检测用户修正。

    参数: original_text — 刚粘贴到输入框的文本
    """
    global _timer

    cfg = _read_config()
    if not cfg.get("enable_correction_learner", False):
        return

    # 取消之前的定时器
    if _timer is not None:
        _timer.cancel()

    delay = cfg.get("correction_delay", 8)
    _last_paste["text"] = original_text
    _last_paste["time"] = time.time()

    print(f"[学习] 将在 {delay}s 后检查用户修正...", flush=True)
    _timer = threading.Timer(delay, _do_learn)
    _timer.daemon = True
    _timer.start()
