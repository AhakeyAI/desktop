"""主窗口。"""

from datetime import datetime
import json
import shlex
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import Dict, List, Optional
import os
import signal
from PySide6.QtGui import QAction, QDesktopServices
from PySide6.QtCore import QObject, Qt, QTimer, QUrl, Signal, QSettings
from PySide6.QtWidgets import (
    QApplication,
    QDialog,
    QFileDialog,
    QFrame,
    QHBoxLayout,
    QLabel,
    QMainWindow,
    QMessageBox,
    QPlainTextEdit,
    QPushButton,
    QScrollArea,
    QSizePolicy,
    QStackedWidget,
    QTabWidget,
    QVBoxLayout,
    QWidget,
)

from ..core.config_manager import ConfigManager
from ..core import cloud_settings
from ..core import typeless_store
from ..core.app_version import APP_VERSION
from ..core.device_state import DeviceState
from ..core.macos_capslock_cleanup import restore_capslock_mapping_best_effort
from ..core.hook_integration import (
    hook_targets_needing_migration,
    install_missing_hooks,
    launch_hook_manager,
    refresh_legacy_hooks,
    missing_hook_targets,
    supports_automatic_hook_install,
)
from ..core.keymap import KeyboardConfig
from ..core.voice_runtime import (
    build_embedded_voice_command,
    preferred_voice_runtime_homes,
)
from .pages.device_page import DevicePage
from .pages.mode_page import ModePage
from .pages.user_page import UserPage
from .widgets.connection_bar import ConnectionBar
from .widgets.device_info_bar import DeviceInfoBar
from .widgets.help_button import HelpButton
from .widgets.mode_selector import ModeSelector
from .update_check import UpdateCheckSignals, interpret_update_payload, schedule_update_check
# 相对各搜索根目录查找语音工程（优先 PyInstaller 输出 dist\CapsWriter-Offline）
_VOICE_TOOL_REL_DIRS = (
    Path("."),
    Path("capswriter"),
    Path("CapsWriter") / "dist" / "CapsWriter-Offline",
    Path("Capswriter") / "dist" / "CapsWriter-Offline",
    Path("CapsWriter-master") / "dist" / "CapsWriter-Offline",
    Path("Capswriter-master") / "dist" / "CapsWriter-Offline",
    Path("CapsWriter"),
    Path("Capswriter"),
    Path("CapsWriter-master"),
    Path("Capswriter-master"),
    Path("CapsWriter-Offline"),
    Path("..") / "capswriter",
    Path("..") / "CapsWriter",
    Path("..") / "Capswriter",
    Path("..") / "CapsWriter-master",
    Path("..") / "Capswriter-master",
    Path("本地语音输入") / "CapsWriter-Offline"
)

_VOICE_PERMISSION_SPECS = {
    "input_monitoring": {
        "title": "输入监控",
        "pane": "Privacy_ListenEvent",
        "button": "打开输入监控设置",
        "description": "允许应用监听语音触发键按下和松开事件，这样才能开始和结束录音。",
    },
    "accessibility": {
        "title": "辅助功能",
        "pane": "Privacy_Accessibility",
        "button": "打开辅助功能设置",
        "description": "允许应用把识别结果写回当前光标位置，并执行自动粘贴。",
    },
    "microphone": {
        "title": "麦克风",
        "pane": "Privacy_Microphone",
        "button": "打开麦克风设置",
        "description": "允许应用访问麦克风，才能开始录音。",
    },
}

_WELCOME_GUIDE_VERSION = f"{APP_VERSION}-guide-10"
_AUDIO_CUE_CONFIG_PATH = Path("/tmp/capswriter_config.json")

_UI_AVFoundation = None


def _ui_avfoundation():
    global _UI_AVFoundation
    if _UI_AVFoundation is not None:
        return _UI_AVFoundation
    try:
        import AVFoundation as _loaded_avfoundation
    except Exception:
        return None
    _UI_AVFoundation = _loaded_avfoundation
    return _UI_AVFoundation


def _is_capswriter_voice_dir(d: Path) -> bool:
    if not d.is_dir():
        return False
    os.environ["CUDA_VISIBLE_DEVICES"] = ""
    has_linux_bin = (d / "start_client").is_file() and (d / "start_server").is_file()
    has_exe = (d / "start_client.exe").is_file() and (d / "start_server.exe").is_file()
    has_py = (d / "start_client.py").is_file() and (d / "start_server.py").is_file()
    has_mac_py = (d / "core_client_mac.py").is_file() and (d / "core_server.py").is_file()
    return has_linux_bin or has_exe or has_py or has_mac_py


def _looks_like_capswriter_dir_name(name: str) -> bool:
    normalized = name.strip().lower()
    return normalized in {
        "capswriter",
        "capswriter-master",
        "capswriter-offline",
        "capswriteroffline",
        "capswriter_offline",
    }


class _VoiceRuntimeSignals(QObject):
    log_message = Signal(str, str)  # message, level
    process_exited = Signal(str, int)  # display_name, returncode


class _BridgeRuntimeSignals(QObject):
    log_message = Signal(str, str)  # message, level
    process_exited = Signal(int, int)  # pid, returncode


class VoicePermissionGuideDialog(QDialog):
    def __init__(self, parent: "MainWindow", app_path: Path, missing_permissions: List[str]):
        super().__init__(parent)
        self._parent_window = parent
        self._app_path = app_path
        self._missing_permissions = [
            permission for permission in missing_permissions if permission in _VOICE_PERMISSION_SPECS
        ]

        self.setWindowTitle("完成系统授权")
        self.setModal(True)
        self.resize(660, 320)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(20, 18, 20, 18)
        layout.setSpacing(14)

        title = QLabel("语音服务已经启动，但还差下面这些手动权限。")
        title.setWordWrap(True)
        layout.addWidget(title)

        for permission in self._missing_permissions:
            spec = _VOICE_PERMISSION_SPECS[permission]
            row = QHBoxLayout()
            row.setSpacing(12)

            text = QLabel(f"{spec['title']}\n{spec['description']}")
            text.setWordWrap(True)

            button = QPushButton(spec["button"])
            button.clicked.connect(
                lambda _checked=False, pane=spec["pane"]: self._parent_window._open_privacy_settings(pane)
            )

            row.addWidget(text, 1)
            row.addWidget(button, 0, Qt.AlignTop)
            layout.addLayout(row)

        tips = QLabel(
            "如果列表里没有 Vibecoding Keyboard，请在对应权限页点左下角的 +，然后选择下面这个应用："
        )
        tips.setWordWrap(True)
        layout.addWidget(tips)

        path_label = QLabel(str(app_path))
        path_label.setWordWrap(True)
        path_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        path_label.setStyleSheet("padding: 8px; border: 1px solid #cfcfcf; border-radius: 6px;")
        layout.addWidget(path_label)

        footer = QHBoxLayout()
        footer.setSpacing(10)
        footer.addStretch(1)

        next_button = QPushButton("已开启权限，下一步")
        next_button.clicked.connect(self._on_continue)
        footer.addWidget(next_button)

        layout.addLayout(footer)

    def _on_continue(self) -> None:
        self.accept()
        self._parent_window._restart_after_voice_permissions()


class WelcomeGuideDialog(QDialog):
    def __init__(self, parent: "MainWindow"):
        super().__init__(parent)
        self.setWindowTitle("欢迎使用 Vibecoding Keyboard")
        self.setModal(True)
        self.resize(640, 380)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(20, 18, 20, 18)
        layout.setSpacing(14)

        title = QLabel("欢迎使用 Vibecoding Keyboard")
        title.setStyleSheet("font-size: 20px; font-weight: 700;")
        layout.addWidget(title)

        subtitle = QLabel("你可以先从下面两个功能开始：")
        subtitle.setStyleSheet("color: #5f6b7a;")
        layout.addWidget(subtitle)

        layout.addWidget(
            self._build_feature_card(
                "启动语音",
                [
                    "点击顶部“启动语音输入”，可以把说话内容快速转换成文字。",
                    "首次使用时，系统会提示你开启麦克风、输入监控和辅助功能权限。",
                    "当右侧状态变成绿色“语音已就绪”后，长按键盘语音键即可开始录音。",
                ],
            )
        )
        layout.addWidget(
            self._build_feature_card(
                "连接设备和配置按键",
                [
                    "点击顶部“连接”，连接键盘设备后就可以查看设备状态。",
                    "进入“模式配置”页，可以为每个按键设置功能，并把配置保存到设备。",
                    "如果需要灯效或动图显示，可以在“动画管理”里添加图片或 GIF。",
                ],
            )
        )

        hint = QLabel("建议第一次使用时，先体验“启动语音”，再连接设备配置按键。")
        hint.setWordWrap(True)
        hint.setStyleSheet("color: #5f6b7a;")
        layout.addWidget(hint)

        button_row = QHBoxLayout()
        button_row.addStretch(1)
        ok_button = QPushButton("我知道了")
        ok_button.setMinimumWidth(128)
        ok_button.setDefault(True)
        ok_button.clicked.connect(self.accept)
        button_row.addWidget(ok_button)
        layout.addLayout(button_row)

    def _build_feature_card(self, title: str, items: List[str]) -> QFrame:
        card = QFrame(self)
        card.setFrameShape(QFrame.StyledPanel)
        card.setStyleSheet(
            """
            QFrame {
                background: #f7f9fc;
                border: 1px solid #d9e0ea;
                border-radius: 10px;
            }
            """
        )

        layout = QVBoxLayout(card)
        layout.setContentsMargins(14, 12, 14, 12)
        layout.setSpacing(8)

        title_label = QLabel(title)
        title_label.setStyleSheet("font-size: 15px; font-weight: 700; color: #1f2d3d;")
        layout.addWidget(title_label)

        for item in items:
            label = QLabel(f"• {item}")
            label.setWordWrap(True)
            label.setStyleSheet("color: #39495a;")
            layout.addWidget(label)

        return card


def _exec_and_cleanup_dialog(dialog: QDialog) -> int:
    try:
        return dialog.exec()
    finally:
        try:
            dialog.hide()
        except Exception:
            pass
        try:
            dialog.setParent(None)
        except Exception:
            pass
        try:
            dialog.deleteLater()
        except Exception:
            pass


class MainWindow(QMainWindow):
    """键盘配置工具主窗口。"""
    _USER_TAB_INDEX = 2

    def __init__(self):
        super().__init__()
        self.setWindowTitle("键盘配置工具")

        self._state = DeviceState(self)
        self._config_manager = ConfigManager()
        self._voice_processes: List[subprocess.Popen] = []
        self._voice_process_map: Dict[str, subprocess.Popen] = {}
        self._voice_server_ready = False
        self._voice_client_ready = False
        self._voice_stop_requested = False
        self._voice_status = "stopped"
        self._voice_permission_prompt_shown = False
        self._voice_microphone_prompt_shown = False
        self._voice_permission_blocking_reason: Optional[str] = None
        self._last_ble_connected: Optional[bool] = None
        self._hook_prompt_shown = False
        self._voice_runtime_signals = _VoiceRuntimeSignals(self)
        self._bridge_process: Optional[subprocess.Popen] = None
        self._bridge_log_handle = None
        self._bridge_tailer_started = False
        self._bridge_stop_tailer = False
        self._bridge_stop_requested = False
        self._bridge_runtime_signals = _BridgeRuntimeSignals(self)
        self._pending_bridge_connect: Optional[tuple[str, int]] = None
        self._pending_bridge_connect_deadline = 0.0
        self._startup_guidance_scheduled = False
        self._welcome_guide_dialog: Optional[WelcomeGuideDialog] = None
        self._startup_hook_prompt: Optional[QMessageBox] = None
        self._bridge_ready_timer = QTimer(self)
        self._bridge_ready_timer.setInterval(250)
        self._bridge_ready_timer.timeout.connect(self._poll_pending_bridge_connect)
        self._setup_menu()
        self._setup_ui()
        self._voice_runtime_signals.log_message.connect(self._on_voice_runtime_message)
        self._voice_runtime_signals.process_exited.connect(self._on_voice_process_exited)
        self._bridge_runtime_signals.log_message.connect(self.device_page.log)
        self._bridge_runtime_signals.process_exited.connect(self._on_bridge_process_exited)
        self._connect_signals()
        self.connection_bar.set_typeless_enabled(typeless_store.get_typeless_enabled())
        self._apply_audio_cue_enabled(
            self._ui_settings().value("voice/audio_cue_enabled", True, bool),
            persist=False,
        )
        self.connection_bar.set_voice_status("stopped")
        self._update_bridge_runtime_status("未启动", "等待自动拉起")
        self._apply_initial_window_size()
        QTimer.singleShot(0, lambda: self._stop_stale_voice_bootstrap_processes("应用启动时清理残留语音进程"))

        self._update_signals = UpdateCheckSignals(self)
        self._update_signals.finished.connect(self._on_update_check_finished)
        QTimer.singleShot(900, lambda: schedule_update_check(self._update_signals))
        QTimer.singleShot(300, self._auto_prepare_local_bridge)

    def _apply_initial_window_size(self):
        hint = self.sizeHint()
        width = max(1100, hint.width())
        height = max(760, hint.height())
        self.resize(width, height)
        self.setMinimumSize(width, height)

    @staticmethod
    def _ui_settings() -> QSettings:
        return QSettings("VibeKeyboard", "VibeCodeConfigTool")

    def _run_startup_guidance_flow(self) -> None:
        if self._maybe_show_welcome_guide():
            return
        self._continue_startup_guidance_flow()

    def _continue_startup_guidance_flow(self) -> None:
        self._maybe_migrate_legacy_hooks()
        self._maybe_prompt_hook_installation()

    def _show_welcome_guide_from_menu(self) -> None:
        self._show_welcome_guide(mark_seen=False)

    def _maybe_show_welcome_guide(self) -> bool:
        settings = self._ui_settings()
        seen_version = (settings.value("ui/welcome_guide_version", "", str) or "").strip()
        seen_flag = settings.value("ui/welcome_guide_seen", False, bool)
        if seen_flag and seen_version == _WELCOME_GUIDE_VERSION:
            return False
        self._show_welcome_guide(mark_seen=True)
        return True

    def _show_welcome_guide(self, *, mark_seen: bool) -> None:
        self.raise_()
        self.activateWindow()
        dlg = WelcomeGuideDialog(self)
        dlg.raise_()
        dlg.activateWindow()
        dlg.setModal(False)
        dlg.setAttribute(Qt.WA_DeleteOnClose, True)
        self._welcome_guide_dialog = dlg

        def _finish() -> None:
            if self._welcome_guide_dialog is dlg:
                self._welcome_guide_dialog = None
            if mark_seen:
                settings = self._ui_settings()
                settings.setValue("ui/welcome_guide_seen", True)
                settings.setValue("ui/welcome_guide_version", _WELCOME_GUIDE_VERSION)
                QTimer.singleShot(0, self._continue_startup_guidance_flow)

        dlg.finished.connect(lambda _result: _finish())
        dlg.show()
        dlg.raise_()
        dlg.activateWindow()

    def _maybe_prompt_hook_installation(self) -> None:
        if self._hook_prompt_shown:
            return

        missing = missing_hook_targets()
        if not missing:
            return

        self._hook_prompt_shown = True
        joined = "、".join(missing)
        prompt = QMessageBox(self)
        prompt.setIcon(QMessageBox.Information)
        prompt.setWindowTitle("打开 Hook 管理器")
        prompt.setText(f"检测到 {joined} Hook 尚未安装。")
        if supports_automatic_hook_install():
            prompt.setInformativeText("建议先打开 Hook 管理器查看状态，再一键安装。")
        else:
            prompt.setInformativeText("当前打包版会通过 Hook 管理器完成安装。")
        open_button = prompt.addButton("打开 Hook 管理器", QMessageBox.AcceptRole)
        prompt.addButton("稍后", QMessageBox.RejectRole)
        prompt.setModal(False)
        prompt.setAttribute(Qt.WA_DeleteOnClose, True)
        self._startup_hook_prompt = prompt

        def _finish() -> None:
            if prompt.clickedButton() is open_button:
                self._open_hook_manager()
            if self._startup_hook_prompt is prompt:
                self._startup_hook_prompt = None

        prompt.finished.connect(lambda _result: _finish())
        prompt.show()
        prompt.raise_()
        prompt.activateWindow()

    def _maybe_migrate_legacy_hooks(self) -> None:
        targets = hook_targets_needing_migration()
        if not targets or not supports_automatic_hook_install():
            return

        QApplication.setOverrideCursor(Qt.WaitCursor)
        try:
            ok, message = refresh_legacy_hooks()
        finally:
            QApplication.restoreOverrideCursor()

        if not ok:
            joined = "、".join(targets)
            QMessageBox.warning(
                self,
                "Hook 迁移失败",
                f"检测到 {joined} 仍在使用旧版 Hook 运行时。\n\n"
                f"{message or '请打开 Hook 管理器重新安装。'}",
            )

    def _install_missing_hooks(self) -> None:
        QApplication.setOverrideCursor(Qt.WaitCursor)
        try:
            ok, message = install_missing_hooks()
        finally:
            QApplication.restoreOverrideCursor()

        if ok:
            QMessageBox.information(self, "Hook 已安装", message)
            return

        fallback = QMessageBox(self)
        fallback.setIcon(QMessageBox.Warning)
        fallback.setWindowTitle("Hook 安装失败")
        fallback.setText("自动安装 Hook 失败了。")
        fallback.setInformativeText(message or "请稍后重试，或手动打开 Hook 管理器。")
        open_manager_button = fallback.addButton("打开 Hook 管理器", QMessageBox.ActionRole)
        fallback.addButton("知道了", QMessageBox.AcceptRole)
        _exec_and_cleanup_dialog(fallback)

        if fallback.clickedButton() is open_manager_button:
            self._open_hook_manager()

    def _open_hook_manager(self) -> None:
        if launch_hook_manager():
            return
        QMessageBox.warning(self, "打开失败", "未找到 Hook 管理工具。")

    def showEvent(self, event) -> None:
        super().showEvent(event)
        if self._startup_guidance_scheduled:
            return
        self._startup_guidance_scheduled = True
        QTimer.singleShot(700, self._run_startup_guidance_flow)

    @staticmethod
    def _microphone_authorization_status() -> Optional[int]:
        avfoundation = _ui_avfoundation()
        if avfoundation is None:
            return None
        try:
            media_type = getattr(avfoundation, "AVMediaTypeAudio", "soun")
            return int(avfoundation.AVCaptureDevice.authorizationStatusForMediaType_(media_type))
        except Exception:
            return None

    @classmethod
    def _microphone_authorized(cls) -> bool:
        status = cls._microphone_authorization_status()
        avfoundation = _ui_avfoundation()
        if status is None or avfoundation is None:
            return False
        authorized = int(getattr(avfoundation, "AVAuthorizationStatusAuthorized", 3))
        return status == authorized

    def _ensure_microphone_permission_from_main_app(self) -> bool:
        avfoundation = _ui_avfoundation()
        if sys.platform != "darwin" or avfoundation is None:
            return True

        if self._microphone_authorized():
            return True

        status = self._microphone_authorization_status()
        denied = int(getattr(avfoundation, "AVAuthorizationStatusDenied", 2))
        restricted = int(getattr(avfoundation, "AVAuthorizationStatusRestricted", 1))
        not_determined = int(getattr(avfoundation, "AVAuthorizationStatusNotDetermined", 0))

        if status in (denied, restricted):
            self._voice_permission_blocking_reason = "需要麦克风权限"
            self._set_voice_status("error", "需要麦克风权限")
            self._maybe_show_microphone_permission_help()
            return False

        # 主界面这里不要再同步拉起麦克风授权弹窗。
        # 在部分 macOS 机器上，这个阻塞式等待 completion 的逻辑会把整个 UI
        # 卡在“启动语音输入”这一刻，看起来像软件直接挂住。
        #
        # 语音客户端自己已经有完整的麦克风授权链路，并且那条链路即使等待授权，
        # 也只会影响子进程，不会卡住主窗口。所以这里改成：
        # - 已拒绝/受限：继续阻止启动并提示用户
        # - 未决定/未知状态：允许继续启动，让客户端去请求授权
        if status == not_determined:
            return True

        return self._microphone_authorized()

    def _setup_menu(self):
        file_menu = self.menuBar().addMenu("文件")

        new_action = QAction("新建配置", self)
        new_action.triggered.connect(self._new_config)
        file_menu.addAction(new_action)

        open_action = QAction("打开配置", self)
        open_action.triggered.connect(self._open_config)
        file_menu.addAction(open_action)

        save_action = QAction("保存配置", self)
        save_action.triggered.connect(self._save_config)
        file_menu.addAction(save_action)

        file_menu.addSeparator()

        save_device_action = QAction("保存到设备", self)
        save_device_action.triggered.connect(self._save_to_device)
        file_menu.addAction(save_device_action)

        tools_menu = self.menuBar().addMenu("工具")

        manage_hook_action = QAction("安装 / 管理 Hook", self)
        manage_hook_action.triggered.connect(self._open_hook_manager)
        tools_menu.addAction(manage_hook_action)

        guide_action = QAction("查看功能引导", self)
        guide_action.triggered.connect(self._show_welcome_guide_from_menu)
        tools_menu.addAction(guide_action)

        self.copyright_label = QLabel(
            "Copyright © 2026 南京锦心湾科技有限公司. All Rights Reserved."
        )
        self.menuBar().setCornerWidget(self.copyright_label, Qt.TopRightCorner)

    def _setup_ui(self):
        central = QWidget()
        self.setCentralWidget(central)

        main_layout = QVBoxLayout(central)
        main_layout.setContentsMargins(0, 0, 0, 0)
        main_layout.setSpacing(0)

        self.connection_bar = ConnectionBar()
        main_layout.addWidget(self.connection_bar)

        self.device_info_bar = DeviceInfoBar()
        main_layout.addWidget(self.device_info_bar)

        copyright_row = QHBoxLayout()
        copyright_row.setContentsMargins(12, 6, 12, 2)
        copyright_row.addStretch(1)
        self.window_copyright_label = QLabel(
            "Copyright © 2026 南京锦心湾科技有限公司. All Rights Reserved."
        )
        self.window_copyright_label.setStyleSheet("color: #6d7885; font-size: 12px;")
        self.window_copyright_label.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
        copyright_row.addWidget(self.window_copyright_label, 0, Qt.AlignRight)
        main_layout.addLayout(copyright_row)

        self.tabs = QTabWidget()
        self.tabs.setDocumentMode(True)

        mode_widget = QWidget()
        mode_layout = QVBoxLayout(mode_widget)
        mode_layout.setContentsMargins(0, 0, 0, 0)
        mode_layout.setSpacing(0)

        mode_selector_row = QHBoxLayout()
        mode_selector_row.setContentsMargins(0, 0, 0, 0)
        mode_selector_row.setSpacing(6)

        self.mode_selector = ModeSelector()
        mode_selector_row.addWidget(self.mode_selector, 0, Qt.AlignLeft)
        mode_selector_row.addWidget(
            HelpButton(
                "模式说明",
                "软件里的 Mode 0 / Mode 1 / Mode 2，分别对应键盘上的不同模式灯状态。\n\n"
                "单击电源键切换模式。\n\n"
                "你当前切换到哪个 Mode，修改的就是键盘对应模式下的按键功能和动画配置。\n\n"
                "点击顶部“连接”后，就可以修改当前模式下的按键和动画配置，并写入设备。",
                self,
                tooltip="查看模式切换与 Mode 配置说明",
            ),
            0,
            Qt.AlignVCenter,
        )
        mode_selector_row.addStretch(1)
        mode_layout.addLayout(mode_selector_row)

        self.mode_stack = QStackedWidget()
        self._mode_pages = []
        for index in range(3):
            page = ModePage(self._state.config.modes[index], device_state=self._state)
            page.config_changed.connect(self._on_config_changed)
            self._mode_pages.append(page)
            self.mode_stack.addWidget(page)

        mode_scroll = QScrollArea()
        mode_scroll.setWidgetResizable(True)
        mode_scroll.setFrameShape(QFrame.NoFrame)
        mode_scroll.setWidget(self.mode_stack)
        mode_layout.addWidget(mode_scroll)
        self.tabs.addTab(mode_widget, "模式配置")

        self.device_page = DevicePage(device_state=self._state)
        device_scroll = QScrollArea()
        device_scroll.setWidgetResizable(True)
        device_scroll.setFrameShape(QFrame.NoFrame)
        device_scroll.setWidget(self.device_page)
        self.tabs.addTab(device_scroll, "设备信息")

        self.user_page = UserPage()
        user_scroll = QScrollArea()
        user_scroll.setWidgetResizable(True)
        user_scroll.setFrameShape(QFrame.NoFrame)
        user_scroll.setWidget(self.user_page)
        self.tabs.addTab(user_scroll, "用户信息")

        main_layout.addWidget(self.tabs)

    def _connect_signals(self):
        self.connection_bar.start_voice_stack_requested.connect(self._start_voice_stack)
        self.connection_bar.stop_voice_stack_requested.connect(self._stop_voice_stack)
        self.connection_bar.typeless_toggled.connect(self._on_typeless_toggled)
        self.connection_bar.audio_cue_toggled.connect(self._on_audio_cue_toggled)
        self.connection_bar.connect_requested.connect(self._on_connect)
        self.connection_bar.disconnect_requested.connect(self._on_disconnect)

        self.device_info_bar.refresh_requested.connect(self._refresh_device_info)
        self.mode_selector.mode_changed.connect(self._on_mode_changed)

        self._state.connection_changed.connect(self._on_connection_changed)
        self._state.ble_status_updated.connect(self._on_ble_status)
        self._state.device_info_updated.connect(self._on_device_info)
        self._state.error_occurred.connect(self._on_error)

    def _on_update_check_finished(self, data: object, err_msg: str) -> None:
        if err_msg or data is None:
            return
        if not isinstance(data, dict):
            return
        payload = interpret_update_payload(data)
        if not payload:
            return
        self._show_update_available_dialog(payload)

    def _show_update_available_dialog(self, data: dict) -> None:
        """使用独立对话框展示更新说明，避免 QMessageBox.setDetailedText 引入英文「Show Details」按钮与按钮挤占截断。"""
        latest = (data.get("latest_version") or "").strip()
        notes = (data.get("release_notes") or "").strip()
        url = (data.get("download_url") or "").strip()

        dlg = QDialog(self)
        dlg.setWindowTitle("发现新版本")
        dlg.setModal(True)
        dlg.setMinimumWidth(440)

        root = QVBoxLayout(dlg)
        root.setSpacing(10)

        info = QLabel("当前版本：{}\n最新版本：{}".format(APP_VERSION, latest))
        info.setWordWrap(True)
        root.addWidget(info)

        if url:
            hint = QLabel("点击下方按钮可在浏览器中打开下载地址。")
        else:
            hint = QLabel("服务端未配置下载地址，请联系管理员获取安装包。")
        hint.setWordWrap(True)
        root.addWidget(hint)

        if notes:
            root.addWidget(QLabel("更新说明"))
            te = QPlainTextEdit()
            te.setPlainText(notes)
            te.setReadOnly(True)
            te.setMinimumHeight(140)
            te.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
            root.addWidget(te, 1)

        btn_row = QHBoxLayout()
        btn_row.addStretch()
        if url:
            btn_open = QPushButton("打开下载页面")
            btn_later = QPushButton("稍后")
            for b in (btn_open, btn_later):
                b.setMinimumWidth(168)
            btn_open.setDefault(True)
            btn_open.setAutoDefault(True)

            def _open_download() -> None:
                QDesktopServices.openUrl(QUrl(url))

            btn_open.clicked.connect(_open_download)
            btn_later.clicked.connect(dlg.reject)
            btn_row.addWidget(btn_open)
            btn_row.addWidget(btn_later)
        else:
            btn_ok = QPushButton("确定")
            btn_ok.setMinimumWidth(120)
            btn_ok.setDefault(True)
            btn_ok.clicked.connect(dlg.accept)
            btn_row.addWidget(btn_ok)
        root.addLayout(btn_row)

        _exec_and_cleanup_dialog(dlg)

    def _on_typeless_toggled(self, enabled: bool) -> None:
        enabled = bool(enabled)
        if enabled and not cloud_settings.get_token():
            QMessageBox.warning(self, "请登录", "请先登录后再开启 Typeless。")
            self.tabs.setCurrentIndex(self._USER_TAB_INDEX)
            # 回拨 UI + 本地状态，避免误开启导致后续云端调用失败。
            typeless_store.set_typeless_enabled(False)
            self.connection_bar.set_typeless_enabled(False)
            return
        typeless_store.set_typeless_enabled(enabled)
        if enabled:
            self._ensure_mac_fn_relay_started()

    @staticmethod
    def _ensure_mac_fn_relay_started() -> None:
        try:
            from ..core.fn_relay_mac import start_mac_fn_relay
        except Exception:
            return
        try:
            start_mac_fn_relay()
        except Exception:
            return

    def _on_audio_cue_toggled(self, enabled: bool) -> None:
        self._apply_audio_cue_enabled(enabled, persist=True)

    def _apply_audio_cue_enabled(self, enabled: bool, *, persist: bool) -> None:
        enabled = bool(enabled)
        self.connection_bar.set_audio_cue_enabled(enabled)
        if persist:
            self._ui_settings().setValue("voice/audio_cue_enabled", enabled)
        self._write_capswriter_shared_config({"enable_audio_cue": enabled})

    @staticmethod
    def _write_capswriter_shared_config(patch: dict) -> None:
        payload = {}
        try:
            if _AUDIO_CUE_CONFIG_PATH.is_file():
                payload = json.loads(_AUDIO_CUE_CONFIG_PATH.read_text(encoding="utf-8") or "{}")
                if not isinstance(payload, dict):
                    payload = {}
        except Exception:
            payload = {}
        payload.update(patch or {})
        try:
            _AUDIO_CUE_CONFIG_PATH.write_text(
                json.dumps(payload, ensure_ascii=False),
                encoding="utf-8",
            )
        except Exception:
            pass

    @staticmethod
    def _bridge_log_file_path() -> Path:
        return (
            Path.home()
            / "Library"
            / "Application Support"
            / "VibeKeyboard"
            / "BLETcpBridge"
            / "bridge_console.log"
        )

    @staticmethod
    def _normalize_local_bridge_host(host: str) -> str:
        normalized = host.strip().lower()
        if normalized in {"", "localhost", "0.0.0.0", "::", "::1"}:
            return "127.0.0.1"
        return host.strip()

    @classmethod
    def _uses_local_bridge(cls, host: str) -> bool:
        return cls._normalize_local_bridge_host(host) == "127.0.0.1"

    @staticmethod
    def _can_connect_tcp(host: str, port: int, timeout: float = 0.25) -> bool:
        try:
            with socket.create_connection((host, port), timeout=timeout):
                return True
        except OSError:
            return False

    def _bridge_log(self, message: str, level: str = "info") -> None:
        self._bridge_runtime_signals.log_message.emit(f"[桥接] {message}", level)

    def _update_bridge_runtime_status(
        self,
        status: str,
        mode: str,
        *,
        port: Optional[int] = None,
        log_file: Optional[Path] = None,
    ) -> None:
        try:
            port_text = str(port if port is not None else int(self.connection_bar.port_edit.text().strip()))
        except ValueError:
            port_text = self.connection_bar.port_edit.text().strip() or "9000"

        self.device_page.update_bridge_runtime(
            {
                "status": status,
                "mode": mode,
                "port": port_text,
                "log_file": str(log_file or self._bridge_log_file_path()),
            }
        )

    def _bridge_search_roots(self) -> List[Path]:
        roots: List[Path] = []
        if getattr(sys, "frozen", False):
            exe_path = Path(sys.executable).resolve()
            if sys.platform == "darwin":
                contents_dir = exe_path.parents[1]
                resources_dir = contents_dir / "Resources"
                roots.extend(
                    [
                        exe_path.parents[3],
                        exe_path.parents[2],
                        resources_dir,
                        resources_dir / "bundled_apps",
                    ]
                )
            roots.append(exe_path.parent)

        roots.append(Path.cwd().resolve())
        here = Path(__file__).resolve()
        roots.extend(here.parents)

        out: List[Path] = []
        seen = set()
        for root in roots:
            try:
                root = root.resolve()
            except OSError:
                continue
            if root not in seen:
                seen.add(root)
                out.append(root)
        return out

    def _find_bridge_launch_target(self) -> Optional[dict]:
        if sys.platform != "darwin":
            return None

        bundle_candidates: List[Path] = []
        for root in self._bridge_search_roots():
            bundle_candidates.extend(
                [
                    root / "BLETcpBridge.app",
                    root / "payload" / "BLETcpBridge.app",
                    root / "dist-macos" / "payload" / "BLETcpBridge.app",
                    root / "mac_bridge" / "dist" / "BLETcpBridge.app",
                ]
            )

        seen = set()
        for bundle in bundle_candidates:
            try:
                bundle = bundle.resolve()
            except OSError:
                continue
            if bundle in seen:
                continue
            seen.add(bundle)

            launcher = bundle / "Contents" / "MacOS" / "BLETcpBridge"
            bridge_home = bundle / "Contents" / "Resources" / "bridge"
            binary = bridge_home / "BleTcpBridge"
            helper = bridge_home / "ble_helper"
            if launcher.is_file() and binary.is_file() and helper.exists():
                return {
                    "cmd": [str(launcher)],
                    "cwd": bridge_home,
                    "env": {
                        "BLE_TCP_BRIDGE_HOME": str(bridge_home),
                        "BLE_TCP_BRIDGE_NO_TERMINAL": "1",
                    },
                    "display": str(bundle),
                }

        for root in self._bridge_search_roots():
            publish_root = root / "mac_bridge" / "build"
            if not publish_root.is_dir():
                continue
            for publish_dir in sorted(publish_root.glob("publish-*")):
                binary = publish_dir / "BleTcpBridge"
                helper = publish_dir / "ble_helper"
                if binary.is_file() and helper.exists():
                    return {
                        "cmd": [str(binary)],
                        "cwd": publish_dir,
                        "env": {"BLE_TCP_BRIDGE_HOME": str(publish_dir)},
                        "display": str(binary),
                    }

        return None

    def _ensure_bridge_log_tailer(self, start_offset: int) -> None:
        if self._bridge_tailer_started:
            return
        self._bridge_tailer_started = True
        log_path = self._bridge_log_file_path()

        def _tail() -> None:
            position = max(0, start_offset)
            announced = False

            while not self._bridge_stop_tailer:
                if not log_path.exists():
                    time.sleep(0.2)
                    continue

                try:
                    with log_path.open("r", encoding="utf-8", errors="replace") as f:
                        try:
                            f.seek(position)
                        except OSError:
                            f.seek(0, os.SEEK_END)
                            position = f.tell()

                        if not announced:
                            self._bridge_log(f"正在跟踪日志文件: {log_path}", "debug")
                            announced = True

                        while not self._bridge_stop_tailer:
                            line = f.readline()
                            if line:
                                position = f.tell()
                                line = line.rstrip("\r\n")
                                if line:
                                    self._bridge_runtime_signals.log_message.emit(
                                        f"[桥接] {line}",
                                        "debug",
                                    )
                                continue

                            try:
                                if log_path.stat().st_size < f.tell():
                                    position = 0
                                    break
                            except OSError:
                                break
                            time.sleep(0.2)
                except Exception as exc:
                    self._bridge_log(f"读取日志文件失败: {exc}", "error")
                    time.sleep(0.5)

        threading.Thread(
            target=_tail,
            name="bridge-log-tail",
            daemon=True,
        ).start()

    def _start_bridge_process_watcher(self, process: subprocess.Popen) -> None:
        def _watch() -> None:
            returncode = process.wait()
            self._bridge_runtime_signals.process_exited.emit(process.pid, returncode)

        threading.Thread(
            target=_watch,
            name="bridge-watcher",
            daemon=True,
        ).start()

    def _close_bridge_log_handle(self) -> None:
        if self._bridge_log_handle is None:
            return
        try:
            self._bridge_log_handle.close()
        except Exception:
            pass
        self._bridge_log_handle = None

    def _ensure_local_bridge_started(self, host: str, port: int, *, show_error: bool) -> bool:
        if sys.platform != "darwin":
            return True
        if not self._uses_local_bridge(host):
            self._update_bridge_runtime_status("未启用", "远程桥接", port=port)
            return True

        local_host = self._normalize_local_bridge_host(host)
        log_path = self._bridge_log_file_path()
        log_path.parent.mkdir(parents=True, exist_ok=True)
        start_offset = log_path.stat().st_size if log_path.exists() else 0
        self._ensure_bridge_log_tailer(start_offset)

        if self._bridge_process is not None and self._bridge_process.poll() is None:
            self._update_bridge_runtime_status("运行中", "主界面自动启动", port=port, log_file=log_path)
            return True

        self._close_bridge_log_handle()
        self._bridge_process = None

        if self._can_connect_tcp(local_host, port):
            self._update_bridge_runtime_status("运行中", "检测到已运行的桥接程序", port=port, log_file=log_path)
            return True

        target = self._find_bridge_launch_target()
        if target is None:
            self._update_bridge_runtime_status("未找到", "缺少 BLETcpBridge.app", port=port, log_file=log_path)
            if show_error:
                QMessageBox.warning(
                    self,
                    "启动失败",
                    "未找到 BLETcpBridge 启动文件。\n\n"
                    "请先构建 bridge：\n"
                    "  ./mac_bridge/build_app.sh\n\n"
                    "或确认安装目录中包含 BLETcpBridge.app。",
                )
            return False

        env = os.environ.copy()
        env.update(target["env"])
        env["PYTHONUNBUFFERED"] = "1"
        env.setdefault("PYTHONIOENCODING", "utf-8")

        try:
            self._bridge_log_handle = log_path.open("a", encoding="utf-8")
            self._bridge_stop_requested = False
            process = subprocess.Popen(
                target["cmd"],
                cwd=str(target["cwd"]),
                env=env,
                stdin=subprocess.DEVNULL,
                stdout=self._bridge_log_handle,
                stderr=subprocess.STDOUT,
                text=True,
                preexec_fn=os.setpgrp if sys.platform != "win32" else None,
            )
        except OSError as exc:
            self._close_bridge_log_handle()
            self._update_bridge_runtime_status("启动失败", "桥接程序无法启动", port=port, log_file=log_path)
            if show_error:
                QMessageBox.warning(self, "启动失败", f"BLETcpBridge 启动失败: {exc}")
            return False

        self._bridge_process = process
        self._start_bridge_process_watcher(process)
        self._bridge_log(f"已自动启动桥接程序: {target['display']}", "info")
        self._bridge_log(f"桥接日志文件: {log_path}", "debug")
        self._update_bridge_runtime_status("启动中", "主界面自动启动", port=port, log_file=log_path)
        return True

    def _auto_prepare_local_bridge(self) -> None:
        if sys.platform != "darwin":
            return
        host = self.connection_bar.host_edit.text().strip()
        try:
            port = int(self.connection_bar.port_edit.text().strip())
        except ValueError:
            port = 9000
        self._ensure_local_bridge_started(host, port, show_error=False)

    def _poll_pending_bridge_connect(self) -> None:
        if not self._pending_bridge_connect:
            self._bridge_ready_timer.stop()
            return

        host, port = self._pending_bridge_connect
        local_host = self._normalize_local_bridge_host(host)
        if self._can_connect_tcp(local_host, port):
            self._bridge_ready_timer.stop()
            self._pending_bridge_connect = None
            self._update_bridge_runtime_status("运行中", "主界面自动启动", port=port)
            self._bridge_log("本地桥接程序已就绪，正在连接设备...", "info")
            self._state.connect_device(host, port)
            return

        if time.monotonic() >= self._pending_bridge_connect_deadline:
            self._bridge_ready_timer.stop()
            self._pending_bridge_connect = None
            self._update_bridge_runtime_status("未响应", "桥接端口未就绪", port=port)
            QMessageBox.warning(
                self,
                "连接失败",
                f"BLETcpBridge 已尝试启动，但 {port} 端口在等待时间内未就绪。\n"
                "请查看设备页中的桥接日志。",
            )

    def _on_bridge_process_exited(self, pid: int, returncode: int) -> None:
        stop_requested = self._bridge_stop_requested
        if self._bridge_process is not None and self._bridge_process.pid == pid:
            self._bridge_process = None
            self._close_bridge_log_handle()
        self._bridge_stop_requested = False

        if stop_requested:
            self._bridge_log(f"桥接程序已停止，退出码={returncode}", "info")
            self._update_bridge_runtime_status("未运行", "已停止")
            return

        if returncode == 0:
            level = "info"
            status = "已退出"
        else:
            level = "error"
            status = "异常退出"

        self._bridge_log(f"桥接程序{status}，退出码={returncode}", level)
        self._update_bridge_runtime_status("未运行", status)

    def _voice_tool_search_roots(self) -> List[Path]:
        roots: List[Path] = []
        if getattr(sys, "frozen", False):
            exe_path = Path(sys.executable).resolve()
            roots.append(exe_path.parent)
            if sys.platform == "darwin":
                resources_dir = exe_path.parents[1] / "Resources"
                roots.extend([resources_dir, resources_dir / "capswriter"])
        roots.append(Path.cwd().resolve())
        here = Path(__file__).resolve()
        roots.extend(here.parents)
        out: List[Path] = []
        seen = set()
        for r in roots:
            try:
                r = r.resolve()
            except OSError:
                continue
            if r not in seen:
                seen.add(r)
                out.append(r)
        return out

    def _preferred_voice_tool_dirs(self) -> List[Path]:
        preferred: List[Path] = []
        seen = set()
        for candidate in preferred_voice_runtime_homes():
            if not _is_capswriter_voice_dir(candidate):
                continue
            if candidate in seen:
                continue
            seen.add(candidate)
            preferred.append(candidate)
        return preferred

    def _get_voice_tool_dir(self) -> Optional[Path]:
        preferred = self._preferred_voice_tool_dirs()
        if preferred:
            return preferred[0]

        for root in self._voice_tool_search_roots():
            for rel in _VOICE_TOOL_REL_DIRS:
                candidate = root / rel
                if _is_capswriter_voice_dir(candidate):
                    return candidate
            try:
                children = sorted(root.iterdir(), key=lambda p: p.name.lower())
            except OSError:
                continue
            for child in children:
                if not child.is_dir() or not _looks_like_capswriter_dir_name(child.name):
                    continue
                if _is_capswriter_voice_dir(child):
                    return child
        return None

    @staticmethod
    def _voice_entry_candidates(script_base: str) -> List[str]:
        if script_base == "start_server":
            return ["start_server", "core_server"]
        if script_base == "start_client":
            if sys.platform == "darwin":
                return ["start_client", "core_client_mac", "core_client"]
            return ["start_client", "core_client"]
        return [script_base]

    @classmethod
    def _voice_launch_argv(cls, tool_dir: Path, script_base: str) -> Optional[List[str]]:
        for entry in cls._voice_entry_candidates(script_base):
            exe = tool_dir / f"{entry}.exe"
            linux_bin = tool_dir / entry
            py = tool_dir / f"{entry}.py"
            if sys.platform != "win32":
                if linux_bin.is_file():
                    if not os.access(linux_bin, os.X_OK):
                        try:
                            os.chmod(linux_bin, 0o755)
                        except Exception:
                            pass
                    return [str(linux_bin)]
                # On packaged macOS builds, the direct launcher inside
                # Resources/capswriter is the stable path for server/client.
                # Only fall back to the main frozen executable bootstrap if the
                # launcher is missing.
                if getattr(sys, "frozen", False) and sys.platform == "darwin" and py.is_file():
                    embedded_cmd = build_embedded_voice_command(entry, tool_dir)
                    if embedded_cmd is not None:
                        return embedded_cmd
                if py.is_file():
                    embedded_cmd = build_embedded_voice_command(entry, tool_dir)
                    if embedded_cmd is not None:
                        return embedded_cmd
                    return [sys.executable, "-u", str(py)]
                continue

            if exe.is_file():
                return [str(exe)]
            if py.is_file():
                return [sys.executable, "-u", str(py)]
        return None

    @staticmethod
    def _voice_log_root(tool_dir: Path) -> Path:
        if getattr(sys, "frozen", False) and sys.platform == "darwin":
            return (
                Path.home()
                / "Library"
                / "Application Support"
                / "VibeKeyboard"
                / "capswriter"
                / "logs"
            )
        return tool_dir / "logs"

    @classmethod
    def _voice_log_file_path(cls, tool_dir: Path, script_base: str) -> Path:
        log_name = "server" if script_base == "start_server" else "client"
        date_str = datetime.now().strftime("%Y%m%d")
        return cls._voice_log_root(tool_dir) / f"{log_name}_{date_str}.log"

    def _voice_log(self, message: str, level: str = "info") -> None:
        self._voice_runtime_signals.log_message.emit(f"[语音] {message}", level)

    def _set_voice_status(self, status: str, detail: Optional[str] = None) -> None:
        normalized = (status or "stopped").strip().lower()
        detail = (detail or "").strip()
        if normalized == self._voice_status and not detail:
            return
        self._voice_status = normalized
        self.connection_bar.set_voice_status(normalized, detail or None)

    def _reset_voice_ready_flags(self) -> None:
        self._voice_server_ready = False
        self._voice_client_ready = False

    def _voice_permission_app_path(self) -> Path:
        if getattr(sys, "frozen", False):
            try:
                return Path(sys.executable).resolve().parents[2]
            except OSError:
                pass
        return Path("/Applications") / "Vibecoding Keyboard.app"

    @staticmethod
    def _normalize_voice_permission_keys(missing_permissions: Optional[List[str]]) -> List[str]:
        mapping = {
            "输入监控": "input_monitoring",
            "辅助功能": "accessibility",
            "麦克风": "microphone",
            "input_monitoring": "input_monitoring",
            "accessibility": "accessibility",
            "microphone": "microphone",
        }
        normalized: List[str] = []
        for permission in missing_permissions or []:
            key = mapping.get((permission or "").strip())
            if key and key not in normalized:
                normalized.append(key)
        return normalized

    def _maybe_show_voice_permission_guide(self, missing_permissions: Optional[List[str]] = None) -> None:
        if sys.platform != "darwin" or self._voice_permission_prompt_shown:
            return
        normalized = self._normalize_voice_permission_keys(
            missing_permissions or ["input_monitoring", "accessibility"]
        )
        if not normalized:
            normalized = ["input_monitoring", "accessibility"]
        self._voice_permission_prompt_shown = True
        QTimer.singleShot(0, lambda: self._show_voice_permission_guide(normalized))

    def _show_voice_permission_guide(self, missing_permissions: Optional[List[str]] = None) -> None:
        app_path = self._voice_permission_app_path()
        dialog = VoicePermissionGuideDialog(
            self,
            app_path,
            self._normalize_voice_permission_keys(missing_permissions or ["input_monitoring", "accessibility"]),
        )
        _exec_and_cleanup_dialog(dialog)

    def _maybe_show_microphone_permission_help(self) -> None:
        if sys.platform != "darwin" or self._voice_microphone_prompt_shown:
            return
        self._voice_microphone_prompt_shown = True
        QTimer.singleShot(0, self._show_microphone_permission_help)

    def _show_microphone_permission_help(self) -> None:
        msg = QMessageBox(self)
        msg.setIcon(QMessageBox.Warning)
        msg.setWindowTitle("需要麦克风权限")
        msg.setText("语音输入需要访问麦克风。")
        msg.setInformativeText(
            "系统会先弹出麦克风授权框，请直接点“允许”。\n\n"
            "如果之前点过“不允许”，请到：\n"
            "系统设置 -> 隐私与安全性 -> 麦克风\n"
            "然后打开 Vibecoding Keyboard。"
        )
        open_settings_button = msg.addButton("打开麦克风设置", QMessageBox.ActionRole)
        msg.addButton("知道了", QMessageBox.AcceptRole)
        _exec_and_cleanup_dialog(msg)
        if msg.clickedButton() == open_settings_button:
            self._open_privacy_settings("Privacy_Microphone")

    def _open_privacy_settings(self, pane: Optional[str] = None) -> None:
        commands = [
            *(
                [["open", f"x-apple.systempreferences:com.apple.preference.security?{pane}"]]
                if pane
                else []
            ),
            ["open", "x-apple.systempreferences:com.apple.preference.security"],
            ["open", "-b", "com.apple.systempreferences"],
        ]
        for command in commands:
            try:
                subprocess.Popen(command)
                return
            except OSError:
                continue
        QMessageBox.warning(self, "打开失败", "无法打开系统设置，请手动前往“隐私与安全性”。")

    def _reveal_voice_permission_app(self) -> None:
        app_path = self._voice_permission_app_path()
        if not app_path.exists():
            QMessageBox.warning(self, "定位失败", f"未找到应用文件：\n{app_path}")
            return
        try:
            subprocess.Popen(["open", "-R", str(app_path)])
        except OSError as exc:
            QMessageBox.warning(self, "定位失败", str(exc))

    def _restart_after_voice_permissions(self) -> None:
        app_path = self._voice_permission_app_path()
        if not app_path.exists():
            QMessageBox.warning(self, "重启失败", f"未找到应用文件：\n{app_path}")
            return

        try:
            quoted_path = shlex.quote(str(app_path))
            subprocess.Popen(
                ["/bin/sh", "-c", f"sleep 1.2; open -n {quoted_path}"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except OSError as exc:
            QMessageBox.warning(self, "重启失败", str(exc))
            return

        self.device_page.log("系统权限已更新，正在关闭并重新打开应用", "info")
        self.close()

    def _update_voice_ready_state(self, starting_detail: Optional[str] = None) -> None:
        if self._voice_server_ready and self._voice_client_ready:
            self._set_voice_status("ready", "语音已就绪")
        else:
            self._set_voice_status("starting", starting_detail or "语音启动中")

    def _on_voice_runtime_message(self, message: str, level: str) -> None:
        self.device_page.log(message, level)
        self._ingest_voice_status_hint(message, level)

    def _ingest_voice_status_hint(self, message: str, level: str) -> None:
        if not message.startswith("[语音]"):
            return

        if self._voice_stop_requested:
            if any(token in message for token in ("收到退出请求", "收到退出信号", "正在关闭服务")):
                self._set_voice_status("stopping", "语音关闭中")
            return

        if "模型文件检查通过" in message:
            self._set_voice_status("starting", "模型检查完成")
            return

        if "🔴 录音中" in message:
            self._set_voice_status("recording", "录音中")
            return

        if "录音结束" in message and "识别中" in message:
            self._set_voice_status("processing", "本地识别中")
            return

        if "开始加载语音模型" in message or "语音模型载入中" in message:
            self._set_voice_status("starting", "模型加载中")
            return

        if "语音模型加载完成" in message or "模型加载完成，开始服务" in message:
            self._set_voice_status("starting", "模型已加载，正在启动服务")
            return

        if "WebSocket 服务器正在启动" in message:
            self._voice_server_ready = True
            self._update_voice_ready_state("服务已启动，等待客户端连接")
            return

        if "已连接到 ASR 服务器" in message:
            self._voice_server_ready = True
            self._voice_client_ready = True
            self._voice_permission_blocking_reason = None
            self._update_voice_ready_state()
            return

        if "新客户端连接" in message:
            self._voice_server_ready = True
            self._voice_client_ready = True
            self._voice_permission_blocking_reason = None
            self._update_voice_ready_state()
            return

        if "按键事件监听已启动" in message:
            if self._voice_status != "ready":
                self._set_voice_status("starting", "按键监听已启动")
            return

        if "[识别]" in message:
            if typeless_store.get_typeless_enabled():
                self._set_voice_status("processing", "AhaType 整理中")
            else:
                self._set_voice_status("processing", "准备粘贴")
            return

        if "未识别到有效文本" in message:
            self._set_voice_status("ready", "语音已就绪")
            return

        if "[AhaType] 请求整理" in message:
            self._set_voice_status("processing", "AhaType 整理中")
            return

        if "[AhaType] 响应 HTTP 200" in message or "[AhaType] 整理完成" in message:
            self._set_voice_status("processing", "准备粘贴")
            return

        if ("已粘贴到光标位置" in message) or ("已写入当前焦点" in message):
            self._set_voice_status("ready", "语音已就绪")
            return

        if any(token in message for token in ("[粘贴失败]", "[AX 失败]", "[Quartz 粘贴失败]", "[Quartz Unicode 直输失败]", "[AppleScript 粘贴失败]", "[菜单粘贴失败]")):
            self._set_voice_status("error", "写入失败")
            return

        if "连接被拒绝" in message:
            if self._voice_status != "ready":
                self._set_voice_status("starting", "等待语音服务就绪")
            return

        if "[权限] 麦克风权限未开启" in message:
            self._voice_permission_blocking_reason = "需要麦克风权限"
            self._set_voice_status("error", "需要麦克风权限")
            self._maybe_show_microphone_permission_help()
            return

        if "[权限] 需要手动开启:" in message:
            raw = message.split("[权限] 需要手动开启:", 1)[1].strip()
            missing_permissions = [part.strip() for part in raw.split("、") if part.strip()]
            self._voice_permission_blocking_reason = "请开启系统权限"
            self._set_voice_status("error", "请开启系统权限")
            self._maybe_show_voice_permission_guide(missing_permissions)
            return

        if any(token in message for token in ("需要辅助功能权限", "无法创建 EventTap")):
            self._voice_permission_blocking_reason = "请开启系统权限"
            self._set_voice_status("error", "需要辅助功能权限")
            self._maybe_show_voice_permission_guide()
            return

        if any(token in message for token in ("未能找到模型文件", "ModuleNotFoundError", "Traceback")):
            self._set_voice_status("error", "语音启动异常")
            return

        if level == "error":
            self._set_voice_status("error", "语音服务异常")

    def _start_voice_pipe_reader(
        self,
        stream,
        display_name: str,
        stream_name: str,
    ) -> None:
        if stream is None:
            return

        level = "error" if stream_name == "stderr" else "recv"

        def _reader() -> None:
            try:
                for raw_line in iter(stream.readline, ""):
                    line = raw_line.rstrip("\r\n")
                    if not line:
                        continue
                    self._voice_runtime_signals.log_message.emit(
                        f"[语音][{display_name}/{stream_name}] {line}",
                        level,
                    )
            except Exception as exc:
                self._voice_runtime_signals.log_message.emit(
                    f"[语音][{display_name}/{stream_name}] 读取失败: {exc}",
                    "error",
                )
            finally:
                try:
                    stream.close()
                except Exception:
                    pass

        threading.Thread(
            target=_reader,
            name=f"voice-{display_name}-{stream_name}",
            daemon=True,
        ).start()

    def _start_voice_log_tailer(
        self,
        process: subprocess.Popen,
        display_name: str,
        log_path: Path,
        start_offset: int,
    ) -> None:
        def _tail() -> None:
            deadline = time.monotonic() + 15.0
            while not log_path.exists() and process.poll() is None and time.monotonic() < deadline:
                time.sleep(0.2)

            if not log_path.exists():
                self._voice_runtime_signals.log_message.emit(
                    f"[语音][{display_name}] 当前尚未生成日志文件: {log_path}",
                    "warn",
                )
                return

            self._voice_runtime_signals.log_message.emit(
                f"[语音][{display_name}] 正在跟踪日志文件: {log_path}",
                "debug",
            )

            try:
                with log_path.open("r", encoding="utf-8", errors="replace") as f:
                    try:
                        f.seek(start_offset)
                    except OSError:
                        f.seek(0, os.SEEK_END)

                    while True:
                        line = f.readline()
                        if line:
                            line = line.rstrip("\r\n")
                            if line:
                                self._voice_runtime_signals.log_message.emit(
                                    f"[语音][{display_name}/log] {line}",
                                    "recv",
                                )
                            continue

                        if process.poll() is not None:
                            extra = f.readline()
                            if not extra:
                                break
                            continue

                        time.sleep(0.2)
            except Exception as exc:
                self._voice_runtime_signals.log_message.emit(
                    f"[语音][{display_name}] 读取日志文件失败: {exc}",
                    "error",
                )

        threading.Thread(
            target=_tail,
            name=f"voice-{display_name}-log-tail",
            daemon=True,
        ).start()

    def _start_voice_process_watcher(
        self,
        process: subprocess.Popen,
        display_name: str,
    ) -> None:
        def _watch() -> None:
            returncode = process.wait()
            self._voice_runtime_signals.process_exited.emit(display_name, returncode)

        threading.Thread(
            target=_watch,
            name=f"voice-{display_name}-watcher",
            daemon=True,
        ).start()

    def _on_voice_process_exited(self, display_name: str, returncode: int) -> None:
        if display_name == "语音客户端":
            restore_capslock_mapping_best_effort()

        if (
            display_name == "语音客户端"
            and returncode == -signal.SIGABRT
            and not self._voice_permission_blocking_reason
        ):
            self._voice_permission_blocking_reason = "需要麦克风权限"
            self._maybe_show_microphone_permission_help()

        if returncode in (0, -signal.SIGTERM, -signal.SIGKILL):
            level = "info"
            state = "已停止"
        else:
            level = "error"
            state = "异常退出"

        self.device_page.log(
            f"[语音][{display_name}] {state}，退出码={returncode}",
            level,
        )
        self._cleanup_voice_processes()
        self.connection_bar.set_voice_running(bool(self._voice_process_map))

        if (
            self._voice_permission_blocking_reason
            and display_name == "语音客户端"
            and self._voice_process_map
            and not self._voice_stop_requested
        ):
            QTimer.singleShot(0, self._stop_voice_stack)
            return

        if self._voice_stop_requested:
            if self._voice_process_map:
                self._set_voice_status("stopping", "语音关闭中")
            else:
                self._voice_stop_requested = False
                self._reset_voice_ready_flags()
                self._set_voice_status("stopped", "语音未启动")
            return

        if self._voice_process_map:
            if self._voice_permission_blocking_reason:
                self._set_voice_status("error", self._voice_permission_blocking_reason)
            else:
                self._set_voice_status("error", f"{display_name} 已退出")
        elif returncode in (0, -signal.SIGTERM, -signal.SIGKILL):
            self._reset_voice_ready_flags()
            if self._voice_permission_blocking_reason:
                self._set_voice_status("error", self._voice_permission_blocking_reason)
            else:
                self._set_voice_status("stopped", "语音未启动")
        else:
            self._reset_voice_ready_flags()
            self._set_voice_status("error", "语音服务异常退出")
        
    def _start_voice_stack(self):
        self._cleanup_voice_processes()
        if self._voice_process_map:
            self.connection_bar.set_voice_running(True)
            if self._voice_status == "ready":
                self.connection_bar.set_voice_status("ready", "语音已就绪")
            elif self._voice_status != "error":
                self.connection_bar.set_voice_status("starting", "语音启动中")
            self.device_page.log("语音服务已在运行，跳过重复启动", "info")
            return

        self._voice_stop_requested = False
        self._voice_permission_prompt_shown = False
        self._voice_microphone_prompt_shown = False
        self._voice_permission_blocking_reason = None
        self._reset_voice_ready_flags()
        self._set_voice_status("starting", "语音启动中")

        if not self._ensure_microphone_permission_from_main_app():
            return

        tool_dir = self._get_voice_tool_dir()
        if tool_dir is None:
            self._set_voice_status("error", "未找到语音工程")
            QMessageBox.warning(
                self,
                "启动失败",
                "未找到语音输入工程目录。\n"
                "请在「项目根目录」下放置 CapsWriter，例如：\n"
                "· Capswriter\\dist\\CapsWriter-Offline（打包后的 exe）\n"
                "· 或 Capswriter-master 源码目录（含 start_client.py / start_server.py）\n"
                "· 或内置的 vibe_code_config_tool-master/capswriter（含 core_client_mac.py / core_server.py）。\n"
                "与 vibe_code_config_tool 平级即可。"
            )
            return

        self._voice_log(f"语音工程目录: {tool_dir}", "debug")

        p_server = self._start_voice_tool("start_server", "语音服务器", tool_dir)
        p_client = self._start_voice_tool("start_client", "语音客户端", tool_dir)
        if p_server or p_client:
            self.connection_bar.set_voice_running(True)
            self._set_voice_status("starting", "语音启动中")
        else:
            self._set_voice_status("error", "语音启动失败")

    def _start_voice_tool(
        self,
        script_base: str,
        display_name: str,
        tool_dir: Optional[Path] = None,
    ) -> Optional[subprocess.Popen]:
        old = self._voice_process_map.get(script_base)
        if old is not None and old.poll() is None:
            return old
        self._voice_process_map.pop(script_base, None)

        if tool_dir is None:
            QMessageBox.warning(
                self,
                "启动失败",
                "未找到语音输入工程目录。\n"
                "请在「项目根目录」下放置 CapsWriter，例如：\n"
                "· Capswriter\\dist\\CapsWriter-Offline（打包后的 exe）\n"
                "· 或 Capswriter-master 源码目录（含 start_client.py / start_server.py）\n"
                "· 或内置的 vibe_code_config_tool-master/capswriter（含 core_client_mac.py / core_server.py）。\n"
                "与 vibe_code_config_tool 平级即可。"
            )
            return None

        argv = self._voice_launch_argv(tool_dir, script_base)
        if not argv:
            QMessageBox.warning(
                self,
                "启动失败",
                f"未找到 {display_name} 启动文件：\n{tool_dir}\n\n"
                f"当前平台需要 {script_base}.py / 可执行的 {script_base}，或对应的 core_server.py / core_client_mac.py。",
            )
            return None

        cmd = list(argv)
        env = os.environ.copy()
        env["PYTHONUNBUFFERED"] = "1"
        env.setdefault("PYTHONIOENCODING", "utf-8")
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        env["CAPSWRITER_HOME"] = str(tool_dir)
        if getattr(sys, "frozen", False) and sys.platform == "darwin":
            data_root = (
                Path.home()
                / "Library"
                / "Application Support"
                / "VibeKeyboard"
                / "capswriter"
            )
            env["CAPSWRITER_DATA_DIR"] = str(data_root)
            env["CAPSWRITER_LOG_DIR"] = str(data_root / "logs")
            env["PYTHONPYCACHEPREFIX"] = str(data_root / "pycache")
        if getattr(sys, "frozen", False):
            env["CAPSWRITER_BOOTSTRAP_EXE"] = sys.executable
        log_path = self._voice_log_file_path(tool_dir, script_base)
        log_path.parent.mkdir(parents=True, exist_ok=True)
        start_offset = log_path.stat().st_size if log_path.exists() else 0

        try:
            p = subprocess.Popen(
                cmd,
                cwd=str(tool_dir),
                env=env,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                encoding="utf-8",
                errors="replace",
                bufsize=1,
                preexec_fn=os.setpgrp if sys.platform != "win32" else None,
            )
            self.device_page.log(
                f"{display_name} 已启动: {subprocess.list2cmdline(cmd)}",
                "info",
            )
            self._voice_log(f"{display_name} 工作目录: {tool_dir}", "debug")
            self._voice_log(f"{display_name} PID: {p.pid}", "debug")
            self._voice_log(f"{display_name} 日志文件: {log_path}", "debug")
            self._voice_processes.append(p)
            self._voice_process_map[script_base] = p
            self._start_voice_pipe_reader(p.stdout, display_name, "stdout")
            self._start_voice_pipe_reader(p.stderr, display_name, "stderr")
            self._start_voice_log_tailer(p, display_name, log_path, start_offset)
            self._start_voice_process_watcher(p, display_name)
            return p
        except OSError as exc:
            QMessageBox.warning(self, "启动失败", f"{display_name} 启动失败: {exc}")
            return None

    @staticmethod
    def _terminate_process_tree(p: subprocess.Popen) -> None:
        if p.poll() is not None:
            return
        if sys.platform == "win32":
            subprocess.run(["taskkill", "/F", "/T", "/PID", str(p.pid)],
                    capture_output=True
                    )
            return
        else:
            try:
                os.killpg(os.getpgid(p.pid), signal.SIGTERM)
                p.wait(timeout=2)
            except Exception:
                try:
                    os.killpg(os.getpgid(p.pid), signal.SIGKILL)
                except:
                    pass

    def _cleanup_voice_processes(self):
        alive_list: List[subprocess.Popen] = []
        for p in self._voice_processes:
            if p.poll() is None:
                alive_list.append(p)
        self._voice_processes = alive_list

        dead_keys = [k for k, p in self._voice_process_map.items() if p.poll() is not None]
        for k in dead_keys:
            self._voice_process_map.pop(k, None)

    @staticmethod
    def _pid_exists(pid: int) -> bool:
        try:
            os.kill(pid, 0)
            return True
        except OSError:
            return False

    def _iter_embedded_voice_bootstrap_pids(self) -> List[int]:
        if sys.platform != "darwin" or not getattr(sys, "frozen", False):
            return []

        try:
            current_executable = str(Path(sys.executable).resolve())
        except OSError:
            current_executable = sys.executable

        current_pid = os.getpid()
        pids: List[int] = []
        try:
            result = subprocess.run(
                ["ps", "-axo", "pid=,command="],
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=2,
                check=False,
            )
        except Exception:
            return []

        for raw_line in result.stdout.splitlines():
            line = raw_line.strip()
            if not line:
                continue
            pid_text, _, command = line.partition(" ")
            try:
                pid = int(pid_text)
            except ValueError:
                continue
            if pid == current_pid:
                continue
            if "--capswriter-bootstrap" not in command:
                continue
            if current_executable not in command:
                continue
            pids.append(pid)
        return pids

    def _terminate_pid_group(self, pid: int) -> bool:
        try:
            pgid = os.getpgid(pid)
        except OSError:
            return False

        for sig in (signal.SIGTERM, signal.SIGKILL):
            try:
                os.killpg(pgid, sig)
            except OSError:
                return not self._pid_exists(pid)

            deadline = time.monotonic() + (1.2 if sig == signal.SIGTERM else 0.8)
            while time.monotonic() < deadline:
                if not self._pid_exists(pid):
                    return True
                time.sleep(0.05)

        return not self._pid_exists(pid)

    def _stop_stale_voice_bootstrap_processes(self, reason: str) -> None:
        stale_pids = self._iter_embedded_voice_bootstrap_pids()
        if not stale_pids:
            return

        stopped = 0
        for pid in stale_pids:
            if self._terminate_pid_group(pid):
                stopped += 1

        if stopped:
            self.device_page.log(f"[语音] 已清理 {stopped} 个残留语音进程: {reason}", "info")

    def _stop_voice_stack(self):
        self._cleanup_voice_processes()
        had_processes = bool(self._voice_processes)
        self._voice_stop_requested = True
        if had_processes:
            self._set_voice_status("stopping", "语音关闭中")
        for p in list(self._voice_processes):
            try:
                self._terminate_process_tree(p)
            except Exception as e:
                self.device_page.log(f"停止进程失败: {e}", "error")

        self._voice_processes.clear()
        self._voice_process_map.clear()
        self._stop_stale_voice_bootstrap_processes("主界面停止语音服务")
        restore_capslock_mapping_best_effort()
        self.connection_bar.set_voice_running(False)
        if had_processes:
            self._set_voice_status("stopping", "语音关闭中")
        else:
            self._voice_stop_requested = False
            self._reset_voice_ready_flags()
            self._set_voice_status("stopped", "语音未启动")
        self.device_page.log("语音服务已尝试关闭", "info")

    def _stop_local_bridge(self, *, reason: str, disconnect_device: bool) -> None:
        self._pending_bridge_connect = None
        self._pending_bridge_connect_deadline = 0.0
        self._bridge_ready_timer.stop()

        if disconnect_device and self._state.connected:
            try:
                self._state.disconnect_device()
            except Exception as exc:
                self.device_page.log(f"断开桥接服务失败: {exc}", "error")

        process = self._bridge_process
        if process is None or process.poll() is not None:
            self._bridge_process = None
            self._close_bridge_log_handle()
            self._update_bridge_runtime_status("未运行", reason)
            return

        self._bridge_stop_requested = True
        self._update_bridge_runtime_status("停止中", reason)
        self._bridge_log(f"正在停止桥接程序: {reason}", "info")

        try:
            self._terminate_process_tree(process)
        except Exception as exc:
            self.device_page.log(f"停止桥接程序失败: {exc}", "error")

    def closeEvent(self, event):
        self._bridge_stop_tailer = True
        self._stop_local_bridge(reason="主界面关闭", disconnect_device=True)
        self._stop_voice_stack()
        super().closeEvent(event)
        app = QApplication.instance()
        if event.isAccepted() and app is not None:
            QTimer.singleShot(0, app.quit)

    def _on_connect(self, host: str, port: int):
        if self._uses_local_bridge(host):
            if not self._ensure_local_bridge_started(host, port, show_error=True):
                return

            local_host = self._normalize_local_bridge_host(host)
            if not self._can_connect_tcp(local_host, port):
                self._pending_bridge_connect = (host, port)
                self._pending_bridge_connect_deadline = time.monotonic() + 12.0
                self._bridge_log("正在等待本地桥接程序就绪...", "info")
                if not self._bridge_ready_timer.isActive():
                    self._bridge_ready_timer.start()
                return

            if self._bridge_process is not None and self._bridge_process.poll() is None:
                mode = "主界面自动启动"
            else:
                mode = "检测到已运行的桥接程序"
            self._update_bridge_runtime_status("运行中", mode, port=port)
        self._state.connect_device(host, port)

    def _on_disconnect(self):
        self._state.disconnect_device()
        if self._bridge_process is not None:
            self._stop_local_bridge(reason="已手动断开", disconnect_device=False)
        else:
            self._pending_bridge_connect = None
            self._pending_bridge_connect_deadline = 0.0
            self._bridge_ready_timer.stop()

    def _on_connection_changed(self, connected: bool):
        self.connection_bar.set_connected(connected)
        if connected:
            self.device_page.log("已连接到桥接服务", "info")
            self._refresh_device_info()
        else:
            self.device_page.log("已断开与桥接服务的连接", "error")

    def _refresh_device_info(self):
        self._state.query_status()
        self._state.query_info()

    def _on_ble_status(self, info: dict):
        ble_connected = bool(info.get("connected"))
        if self._last_ble_connected is None or ble_connected != self._last_ble_connected:
            if ble_connected:
                name = info.get("name") or "未知设备"
                self.device_page.log(f"BLE 设备已连接: {name}", "info")
            else:
                self.device_page.log("BLE 设备未连接", "warn")
        self._last_ble_connected = ble_connected
        self.device_info_bar.update_ble_status(info)
        self.device_page.update_ble_status(info)
        self.device_page.log(f"BLE 状态: {info}", "recv")

    def _on_device_info(self, info: dict):
        self.device_info_bar.update_device_info(info)
        self.device_page.update_device_info(info)
        self.device_page.log(f"设备信息: {info}", "recv")

    def _on_error(self, msg: str):
        self.device_page.log(msg, "error")
        QMessageBox.warning(self, "错误", msg)

    def _on_mode_changed(self, mode_id: int):
        self.mode_stack.setCurrentIndex(mode_id)
        self._state.current_mode = mode_id

    def _on_config_changed(self):
        pass

    def _new_config(self):
        self._state.config = KeyboardConfig()
        for index, page in enumerate(self._mode_pages):
            page.set_config(self._state.config.modes[index])

    def _open_config(self):
        path, _ = QFileDialog.getOpenFileName(
            self,
            "打开配置",
            "",
            "配置文件 (*.json);;All Files (*)",
        )
        if not path:
            return

        try:
            config = self._config_manager.load(path)
            self._state.config = config
            for index, page in enumerate(self._mode_pages):
                page.set_config(config.modes[index])
        except Exception as exc:
            QMessageBox.warning(self, "打开失败", str(exc))

    def _save_config(self):
        path, _ = QFileDialog.getSaveFileName(
            self,
            "保存配置",
            "keyboard_config.json",
            "配置文件 (*.json);;All Files (*)",
        )
        if not path:
            return

        try:
            self._config_manager.save(self._state.config, path)
        except Exception as exc:
            QMessageBox.warning(self, "保存失败", str(exc))

    def _save_to_device(self):
        if not self._state.connected:
            QMessageBox.warning(self, "提示", "请先连接设备")
            return

        try:
            state0 = self._state.service.read_pic_state(0)
            max_frames = state0.get("all_mode_max_pic", 74)

            frame_counts = [len(page.mode_config.display.frame_paths) for page in self._mode_pages]
            total_frames = sum(frame_counts)
            if total_frames > max_frames:
                QMessageBox.warning(
                    self,
                    "动画帧数量超限",
                    (
                        f"当前共 {total_frames} 帧，设备最多支持 {max_frames} 帧。\n"
                        f"Mode 0: {frame_counts[0]} 帧\n"
                        f"Mode 1: {frame_counts[1]} 帧\n"
                        f"Mode 2: {frame_counts[2]} 帧\n\n"
                        "请减少 GIF 帧数或删除部分动画后再上传。"
                    ),
                )
                return

            for page in self._mode_pages:
                page.upload_keys_to_device(self._state.service)

            start_index = 0
            for page in self._mode_pages:
                start_index = page.upload_to_device(self._state.service, start_index)

            self._state.service.save_config()
            QMessageBox.information(self, "完成", "配置已保存到设备")
        except Exception as exc:
            QMessageBox.warning(self, "保存失败", str(exc))
