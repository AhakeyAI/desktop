"""
HID 键码定义和键码数据库
"""

from enum import IntEnum


class KeyType(IntEnum):
    SHORTCUT = 0  # 快捷键 (HID keycodes列表, 修饰键也是keycode)
    MACRO = 1     # 宏 (action+param序列)


# HID 键码表 — 含修饰键和小键盘
# 格式: (name, hid_code, category)
KEYCODES = [
    # 字母
    ("A", 0x04, "alpha"), ("B", 0x05, "alpha"), ("C", 0x06, "alpha"),
    ("D", 0x07, "alpha"), ("E", 0x08, "alpha"), ("F", 0x09, "alpha"),
    ("G", 0x0A, "alpha"), ("H", 0x0B, "alpha"), ("I", 0x0C, "alpha"),
    ("J", 0x0D, "alpha"), ("K", 0x0E, "alpha"), ("L", 0x0F, "alpha"),
    ("M", 0x10, "alpha"), ("N", 0x11, "alpha"), ("O", 0x12, "alpha"),
    ("P", 0x13, "alpha"), ("Q", 0x14, "alpha"), ("R", 0x15, "alpha"),
    ("S", 0x16, "alpha"), ("T", 0x17, "alpha"), ("U", 0x18, "alpha"),
    ("V", 0x19, "alpha"), ("W", 0x1A, "alpha"), ("X", 0x1B, "alpha"),
    ("Y", 0x1C, "alpha"), ("Z", 0x1D, "alpha"),
    # 数字
    ("1", 0x1E, "number"), ("2", 0x1F, "number"), ("3", 0x20, "number"),
    ("4", 0x21, "number"), ("5", 0x22, "number"), ("6", 0x23, "number"),
    ("7", 0x24, "number"), ("8", 0x25, "number"), ("9", 0x26, "number"),
    ("0", 0x27, "number"),
    # 基础键
    ("Enter", 0x28, "basic"), ("Escape", 0x29, "basic"),
    ("Backspace", 0x2A, "basic"), ("Tab", 0x2B, "basic"),
    ("Space", 0x2C, "basic"), ("Minus", 0x2D, "basic"),
    ("Equal", 0x2E, "basic"), ("Left Bracket", 0x2F, "basic"),
    ("Right Bracket", 0x30, "basic"), ("Backslash", 0x31, "basic"),
    ("Semicolon", 0x33, "basic"), ("Quote", 0x34, "basic"),
    ("Grave", 0x35, "basic"), ("Comma", 0x36, "basic"),
    ("Period", 0x37, "basic"), ("Slash", 0x38, "basic"),
    ("Caps Lock", 0x39, "basic"),
    # F键
    ("F1", 0x3A, "function"), ("F2", 0x3B, "function"),
    ("F3", 0x3C, "function"), ("F4", 0x3D, "function"),
    ("F5", 0x3E, "function"), ("F6", 0x3F, "function"),
    ("F7", 0x40, "function"), ("F8", 0x41, "function"),
    ("F9", 0x42, "function"), ("F10", 0x43, "function"),
    ("F11", 0x44, "function"), ("F12", 0x45, "function"),
    ("F13", 0x68, "function"), ("F14", 0x69, "function"),
    ("F15", 0x6A, "function"), ("F16", 0x6B, "function"),
    ("F17", 0x6C, "function"), ("F18", 0x6D, "function"),
    ("F19", 0x6E, "function"), ("F20", 0x6F, "function"),
    ("F21", 0x70, "function"), ("F22", 0x71, "function"),
    ("F23", 0x72, "function"), ("F24", 0x73, "function"),
    # 控制键
    ("Print Screen", 0x46, "control"), ("Scroll Lock", 0x47, "control"),
    ("Pause", 0x48, "control"), ("Insert", 0x49, "control"),
    ("Home", 0x4A, "control"), ("Page Up", 0x4B, "control"),
    ("Delete", 0x4C, "control"), ("End", 0x4D, "control"),
    ("Page Down", 0x4E, "control"),
    # 方向键
    ("Right", 0x4F, "arrow"), ("Left", 0x50, "arrow"),
    ("Down", 0x51, "arrow"), ("Up", 0x52, "arrow"),
    # 小键盘
    ("Num Lock", 0x53, "numpad"), ("KP /", 0x54, "numpad"),
    ("KP *", 0x55, "numpad"), ("KP -", 0x56, "numpad"),
    ("KP +", 0x57, "numpad"), ("KP Enter", 0x58, "numpad"),
    ("KP 1", 0x59, "numpad"), ("KP 2", 0x5A, "numpad"),
    ("KP 3", 0x5B, "numpad"), ("KP 4", 0x5C, "numpad"),
    ("KP 5", 0x5D, "numpad"), ("KP 6", 0x5E, "numpad"),
    ("KP 7", 0x5F, "numpad"), ("KP 8", 0x60, "numpad"),
    ("KP 9", 0x61, "numpad"), ("KP 0", 0x62, "numpad"),
    ("KP .", 0x63, "numpad"),
    # 修饰键 (作为普通键码，用于快捷键组合)
    ("Left Ctrl", 0xE0, "modifier"), ("Left Shift", 0xE1, "modifier"),
    ("Left Alt", 0xE2, "modifier"), ("Left Win", 0xE3, "modifier"),
    ("Right Ctrl", 0xE4, "modifier"), ("Right Shift", 0xE5, "modifier"),
    ("Right Alt", 0xE6, "modifier"), ("Right Win", 0xE7, "modifier"),
]

# 查找辅助
KEYCODE_BY_HID = {code: name for name, code, _ in KEYCODES}
KEYCODE_BY_NAME = {name: code for name, code, _ in KEYCODES}
KEYCODES_BY_CATEGORY = {}
for name, code, cat in KEYCODES:
    KEYCODES_BY_CATEGORY.setdefault(cat, []).append((name, code))

# 修饰键 HID 码集合 (用于快捷键标签生成)
MODIFIER_HIDS = {0xE0, 0xE1, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7}


def get_keycode_name(hid_code: int) -> str:
    """根据 HID 码获取键名"""
    return KEYCODE_BY_HID.get(hid_code, f"0x{hid_code:02X}")


def format_shortcut_label(keycodes: list[int]) -> str:
    """将快捷键码列表格式化为可读标签, 如 'Left Win + E'"""
    if not keycodes:
        return "None"
    names = [get_keycode_name(k) for k in keycodes]
    return " + ".join(names)
