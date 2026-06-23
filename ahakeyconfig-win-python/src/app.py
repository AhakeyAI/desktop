"""
应用程序入口 — QApplication 初始化和主题设置
"""

import sys
from PySide6.QtWidgets import QApplication
from PySide6.QtCore import Qt

from .core import typeless_store
from .ui.main_window import MainWindow


def run():
    app = QApplication(sys.argv)
    typeless_store.ensure_typeless_file()

    # 暗色主题
    try:
        import qdarktheme
        qdarktheme.setup_theme("dark")
    except ImportError:
        pass  # 如果 pyqtdarktheme 未安装则使用默认主题

    window = MainWindow()
    window.show()

    sys.exit(app.exec())
