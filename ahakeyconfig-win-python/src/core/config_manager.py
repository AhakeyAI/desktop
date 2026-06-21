"""
配置管理 — JSON 导入/导出
"""

import json
from pathlib import Path

from .keymap import KeyboardConfig


class ConfigManager:
    """配置文件的保存和加载"""

    SCHEMA_VERSION = 1

    def save(self, config: KeyboardConfig, path: str):
        """保存配置到 JSON 文件"""
        data = config.to_dict()
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

    def load(self, path: str) -> KeyboardConfig:
        """从 JSON 文件加载配置"""
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)

        version = data.get("version", 1)
        if version > self.SCHEMA_VERSION:
            raise ValueError(f"配置文件版本 {version} 不兼容，当前支持版本 {self.SCHEMA_VERSION}")

        return KeyboardConfig.from_dict(data)
