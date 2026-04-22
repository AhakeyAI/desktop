"""
按键映射与模式配置数据模型

协议格式 (UPDATE_CUSTOME_KEY):
  快捷键 (0x73): [modifier_keycodes..., key_keycodes...] — HID码列表, max 98 bytes
  宏 (0x74): [action, param, action, param, ...] — 动作对列表, max 98 bytes
  描述 (0x75): ASCII 字符串, max 20 bytes
"""

from dataclasses import dataclass, field

from .keycodes import KeyType, get_keycode_name, format_shortcut_label


NUM_KEYS = 4
NUM_MODES = 3
MAX_DESCRIPTION_LEN = 20
MAX_KEY_DATA_LEN = 98


@dataclass
class KeyBinding:
    """单个按键的绑定配置"""
    key_type: int = KeyType.SHORTCUT
    keycodes: list[int] = field(default_factory=list)     # 快捷键: HID 键码列表
    macro_data: list[int] = field(default_factory=list)    # 宏: [action, param, ...] 扁平列表
    description: str = ""                                  # 按键描述, max 20 ASCII chars

    @property
    def label(self) -> str:
        """生成人类可读的标签"""
        if self.description:
            return self.description
        if self.key_type == KeyType.SHORTCUT:
            return format_shortcut_label(self.keycodes)
        elif self.key_type == KeyType.MACRO:
            if self.macro_data:
                return f"Macro ({len(self.macro_data) // 2} steps)"
            return "Macro (empty)"
        return "None"

    def to_dict(self) -> dict:
        return {
            "key_type": int(self.key_type),
            "keycodes": list(self.keycodes),
            "macro_data": list(self.macro_data),
            "description": self.description,
        }

    @classmethod
    def from_dict(cls, d: dict) -> "KeyBinding":
        return cls(
            key_type=d.get("key_type", 0),
            keycodes=d.get("keycodes", []),
            macro_data=d.get("macro_data", []),
            description=d.get("description", ""),
        )


@dataclass
class DisplayMode:
    """单个模式的显示/动画配置"""
    fps: int = 10
    frame_paths: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "fps": self.fps,
            "frame_paths": list(self.frame_paths),
        }

    @classmethod
    def from_dict(cls, d: dict) -> "DisplayMode":
        return cls(
            fps=d.get("fps", 10),
            frame_paths=d.get("frame_paths", []),
        )


@dataclass
class ModeConfig:
    """单个模式的完整配置（按键 + 动画）"""
    mode_id: int = 0
    keys: list[KeyBinding] = field(default_factory=lambda: [KeyBinding() for _ in range(NUM_KEYS)])
    display: DisplayMode = field(default_factory=DisplayMode)

    def to_dict(self) -> dict:
        return {
            "mode_id": self.mode_id,
            "keys": [k.to_dict() for k in self.keys],
            "display": self.display.to_dict(),
        }

    @classmethod
    def from_dict(cls, d: dict) -> "ModeConfig":
        return cls(
            mode_id=d.get("mode_id", 0),
            keys=[KeyBinding.from_dict(k) for k in d.get("keys", [])],
            display=DisplayMode.from_dict(d.get("display", {})),
        )


@dataclass
class KeyboardConfig:
    """键盘完整配置（3模式）"""
    name: str = "Default"
    modes: list[ModeConfig] = field(
        default_factory=lambda: [ModeConfig(mode_id=i) for i in range(NUM_MODES)]
    )

    def to_dict(self) -> dict:
        return {
            "version": 2,
            "name": self.name,
            "modes": [m.to_dict() for m in self.modes],
        }

    @classmethod
    def from_dict(cls, d: dict) -> "KeyboardConfig":
        return cls(
            name=d.get("name", "Default"),
            modes=[ModeConfig.from_dict(m) for m in d.get("modes", [])],
        )
