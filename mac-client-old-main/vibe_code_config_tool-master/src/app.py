"""
应用程序入口 — QApplication 初始化和主题设置
"""

import sys
import threading
from PySide6.QtCore import QTimer
from PySide6.QtWidgets import QApplication

from .core.macos_capslock_cleanup import restore_capslock_mapping_best_effort
from .core import typeless_store
from .core.install_cleanup import ensure_uninstall_watcher, maybe_eject_installer_volume
from .ui.main_window import MainWindow


def _apply_dark_theme(app: QApplication) -> None:
    try:
        import qdarktheme
    except ImportError:
        return

    setup_theme = getattr(qdarktheme, "setup_theme", None)
    if callable(setup_theme):
        setup_theme("dark")
        return

    load_stylesheet = getattr(qdarktheme, "load_stylesheet", None)
    if callable(load_stylesheet):
        app.setStyleSheet(load_stylesheet("dark"))


def run():
    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(True)
    app.lastWindowClosed.connect(app.quit)
    app.aboutToQuit.connect(restore_capslock_mapping_best_effort)
    typeless_store.ensure_typeless_file()
    restore_capslock_mapping_best_effort()

    _apply_dark_theme(app)

    window = MainWindow()
    window.show()
    if typeless_store.get_typeless_enabled():
        QTimer.singleShot(1200, _start_mac_fn_relay_safely)
    threading.Thread(target=ensure_uninstall_watcher, daemon=True).start()
    QTimer.singleShot(1600, maybe_eject_installer_volume)

    return app.exec()


def _start_mac_fn_relay_safely() -> None:
    try:
        from .core.fn_relay_mac import start_mac_fn_relay
    except Exception:
        return
    try:
        start_mac_fn_relay()
    except Exception:
        return
