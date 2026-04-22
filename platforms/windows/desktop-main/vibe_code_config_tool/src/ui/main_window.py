"""主窗口。"""

import json
import subprocess
import sys
import socket
import tempfile
from pathlib import Path
from typing import Dict, List, Optional
import os
import signal
from PySide6.QtGui import QAction, QDesktopServices
from PySide6.QtCore import QSettings, Qt, QTimer, QUrl
from PySide6.QtWidgets import (
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
from ..core.keymap import KeyboardConfig
from .pages.device_page import DevicePage
from .pages.mode_page import ModePage
from .pages.user_page import UserPage
from .widgets.connection_bar import ConnectionBar
from .widgets.device_info_bar import DeviceInfoBar
from .widgets.mode_selector import ModeSelector
from .widgets.voice_hud import VoiceHud
from .update_check import UpdateCheckSignals, interpret_update_payload, schedule_update_check
# 相对各搜索根目录查找语音工程（优先 PyInstaller 输出 dist\CapsWriter-Offline）
_VOICE_TOOL_REL_DIRS = (
    Path("."),
    Path("CapsWriter") / "dist" / "CapsWriter-Offline",
    Path("Capswriter") / "dist" / "CapsWriter-Offline",
    Path("CapsWriter"),
    Path("Capswriter"),
    Path("CapsWriter-Offline"),
    Path("..") / "CapsWriter",
    Path("本地语音输入") / "CapsWriter-Offline"
)
_WELCOME_GUIDE_VERSION = "{}-guide-8".format(APP_VERSION)
_VOICE_READY_HOST = "127.0.0.1"
_VOICE_READY_PORT = 6016
_AUDIO_CUE_CONFIG_PATH = Path(tempfile.gettempdir()) / "capswriter_config.json"
_BLE_DRIVER_EXE_NAME = "BLE_tcp_driver.exe"


def _ui_settings() -> QSettings:
    return QSettings("VibeKeyboard", "VibeCodeConfigTool")


def _is_capswriter_voice_dir(d: Path) -> bool:
    if not d.is_dir():
        return False
    os.environ["CUDA_VISIBLE_DEVICES"] = ""
    has_linux_bin = (d / "start_client").is_file() and (d / "start_server").is_file()
    has_exe = (d / "start_client.exe").is_file() and (d / "start_server.exe").is_file()
    has_py = (d / "start_client.py").is_file() and (d / "start_server.py").is_file()
    return has_linux_bin or has_exe or has_py


def _welcome_settings() -> QSettings:
    return _ui_settings()


class WelcomeGuideDialog(QDialog):
    """首次使用引导弹窗。"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("欢迎使用 Vibecoding Keyboard")
        self.setModal(True)
        self.setMinimumWidth(620)
        self.setWindowFlag(Qt.WindowContextHelpButtonHint, False)
        self._setup_ui()

    def _setup_ui(self) -> None:
        root = QVBoxLayout(self)
        root.setContentsMargins(20, 20, 20, 16)
        root.setSpacing(14)

        title = QLabel("欢迎使用 Vibecoding Keyboard")
        title.setStyleSheet("font-size: 22px; font-weight: 700;")
        root.addWidget(title)

        subtitle = QLabel("你可以先从下面两个功能开始：")
        subtitle.setWordWrap(True)
        subtitle.setStyleSheet("font-size: 13px; color: #B8C0CC;")
        root.addWidget(subtitle)

        cards_row = QHBoxLayout()
        cards_row.setSpacing(12)
        cards_row.addWidget(
            self._build_feature_card(
                "启动语音",
                "点击顶部“启动语音输入”，可以把说话内容快速转换成文字。\n"
                "当右侧状态变成绿色“语音已就绪”后，就可以按下键盘语音键开始录音。\n"
                "默认情况下，键盘语音键对应键盘模式一的第一个按键，也就是 Key1。",
            )
        )
        cards_row.addWidget(
            self._build_feature_card(
                "连接设备和配置按键",
                "点击顶部“连接”，连接键盘设备后就可以查看设备状态。\n"
                "进入“模式配置”页，可以为每个按键设置功能，并把配置保存到设备。\n"
                "如果需要灯效或动图显示，可以在“动画管理”里添加图片或 GIF。",
            )
        )
        root.addLayout(cards_row)

        tip = QLabel("建议第一次使用时，先体验“启动语音”，再连接设备配置按键。")
        tip.setWordWrap(True)
        tip.setStyleSheet(
            "padding: 10px 12px; border-radius: 10px; background-color: rgba(84, 160, 255, 0.12);"
            " color: #D7E8FF;"
        )
        root.addWidget(tip)

        button_row = QHBoxLayout()
        button_row.addStretch()

        confirm_btn = QPushButton("我知道了")
        confirm_btn.setMinimumWidth(120)
        confirm_btn.setDefault(True)
        confirm_btn.clicked.connect(self.accept)
        button_row.addWidget(confirm_btn)

        root.addLayout(button_row)

    def _build_feature_card(self, title: str, body: str) -> QFrame:
        frame = QFrame()
        frame.setFrameShape(QFrame.NoFrame)
        frame.setStyleSheet(
            "QFrame {"
            " border-radius: 14px;"
            " background-color: rgba(255, 255, 255, 0.05);"
            " border: 1px solid rgba(255, 255, 255, 0.08);"
            "}"
        )

        layout = QVBoxLayout(frame)
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(10)

        title_label = QLabel(title)
        title_label.setStyleSheet("font-size: 16px; font-weight: 700;")
        layout.addWidget(title_label)

        body_label = QLabel(body)
        body_label.setWordWrap(True)
        body_label.setStyleSheet("font-size: 13px; line-height: 1.5; color: #D7DCE2;")
        layout.addWidget(body_label)
        layout.addStretch()
        return frame


class MainWindow(QMainWindow):
    """键盘配置工具主窗口。"""
    _USER_TAB_INDEX = 2

    def __init__(self):
        super().__init__()
        self.setWindowTitle("键盘配置工具")
        self._startup_guidance_scheduled = False

        self._state = DeviceState(self)
        self._config_manager = ConfigManager()
        self._ble_driver_process: Optional[subprocess.Popen] = None
        self._voice_processes: List[subprocess.Popen] = []
        self._voice_process_map: Dict[str, subprocess.Popen] = {}
        self._voice_hud = VoiceHud() if self._voice_hud_enabled() else None
        self._voice_ready_poll_timer = QTimer(self)
        self._voice_ready_poll_timer.setInterval(800)
        self._voice_ready_poll_timer.timeout.connect(self._update_voice_ready_state)
        self._setup_menu()
        self._setup_ui()
        self._connect_signals()
        self.connection_bar.set_typeless_enabled(typeless_store.get_typeless_enabled())
        self._audio_cue_enabled = self._load_audio_cue_enabled()
        self.connection_bar.set_audio_cue_enabled(self._audio_cue_enabled)
        self.connection_bar.set_voice_status("stopped")
        self._write_capswriter_shared_config()
        self._apply_initial_window_size()
        QTimer.singleShot(0, self._ensure_ble_driver_started)

        self._update_signals = UpdateCheckSignals(self)
        self._update_signals.finished.connect(self._on_update_check_finished)
        QTimer.singleShot(900, lambda: schedule_update_check(self._update_signals))

    def _apply_initial_window_size(self):
        hint = self.sizeHint()
        width = max(1100, hint.width())
        height = max(760, hint.height())
        self.resize(width, height)
        self.setMinimumSize(width, height)

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

        help_menu = self.menuBar().addMenu("帮助")

        welcome_guide_action = QAction("查看功能引导", self)
        welcome_guide_action.triggered.connect(self._show_welcome_guide_from_menu)
        help_menu.addAction(welcome_guide_action)

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

        self.tabs = QTabWidget()
        self.tabs.setDocumentMode(True)

        mode_widget = QWidget()
        mode_layout = QVBoxLayout(mode_widget)
        mode_layout.setContentsMargins(0, 0, 0, 0)
        mode_layout.setSpacing(0)

        self.mode_selector = ModeSelector()
        mode_layout.addWidget(self.mode_selector)

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

        dlg.exec()

    def showEvent(self, event) -> None:
        super().showEvent(event)
        if self._startup_guidance_scheduled:
            return
        self._startup_guidance_scheduled = True
        QTimer.singleShot(700, self._run_startup_guidance_flow)

    def _run_startup_guidance_flow(self) -> None:
        self._maybe_show_welcome_guide()
        self._run_post_guide_startup_checks()

    def _maybe_show_welcome_guide(self) -> None:
        settings = _welcome_settings()
        seen = settings.value("ui/welcome_guide_seen", False, bool)
        version = settings.value("ui/welcome_guide_version", "", str)
        if seen and version == _WELCOME_GUIDE_VERSION:
            return
        self._show_welcome_guide(mark_seen=True)

    def _show_welcome_guide(self, mark_seen: bool) -> None:
        dlg = WelcomeGuideDialog(self)
        accepted = dlg.exec() == QDialog.Accepted
        if not (mark_seen and accepted):
            return
        settings = _welcome_settings()
        settings.setValue("ui/welcome_guide_seen", True)
        settings.setValue("ui/welcome_guide_version", _WELCOME_GUIDE_VERSION)

    def _show_welcome_guide_from_menu(self) -> None:
        self._show_welcome_guide(mark_seen=False)

    def _run_post_guide_startup_checks(self) -> None:
        """首启引导后的扩展点。

        macOS 版本会在这里继续进入 Hook 缺失检查；当前 Windows 端先保留为无操作，
        方便后续接入本机对应的启动检查流程。
        """
        return

    @staticmethod
    def _ble_driver_candidates() -> list[Path]:
        candidates: list[Path] = []
        if getattr(sys, "frozen", False):
            candidates.append(Path(sys.executable).resolve().with_name(_BLE_DRIVER_EXE_NAME))
        here = Path(__file__).resolve()
        candidates.extend(
            [
                here.parents[3] / "all_in_one" / _BLE_DRIVER_EXE_NAME,
                here.parents[3] / _BLE_DRIVER_EXE_NAME,
                Path.cwd() / _BLE_DRIVER_EXE_NAME,
            ]
        )
        unique: list[Path] = []
        seen: set[str] = set()
        for path in candidates:
            key = str(path).lower()
            if key in seen:
                continue
            seen.add(key)
            unique.append(path)
        return unique

    @staticmethod
    def _is_ble_driver_running() -> bool:
        if sys.platform != "win32":
            return False
        try:
            result = subprocess.run(
                ["tasklist", "/FI", f"IMAGENAME eq {_BLE_DRIVER_EXE_NAME}"],
                capture_output=True,
                text=True,
                check=False,
            )
        except OSError:
            return False
        output = "{}\n{}".format(result.stdout, result.stderr).lower()
        return _BLE_DRIVER_EXE_NAME.lower() in output

    def _find_ble_driver_exe(self) -> Optional[Path]:
        for path in self._ble_driver_candidates():
            if path.is_file():
                return path
        return None

    def _ensure_ble_driver_started(self) -> None:
        if sys.platform != "win32":
            return
        if self._is_ble_driver_running():
            self.device_page.log("检测到蓝牙桥接驱动已在运行，跳过重复启动", "info")
            return

        exe_path = self._find_ble_driver_exe()
        if exe_path is None:
            self.device_page.log("未找到 BLE_tcp_driver.exe，已跳过自动启动", "error")
            return

        creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
        try:
            self._ble_driver_process = subprocess.Popen(
                [str(exe_path), "--minimized"],
                cwd=str(exe_path.parent),
                creationflags=creationflags,
            )
            self.device_page.log(f"已自动启动蓝牙桥接驱动: {exe_path}", "info")
        except OSError as exc:
            self._ble_driver_process = None
            self.device_page.log(f"自动启动蓝牙桥接驱动失败: {exc}", "error")

    def _stop_ble_driver_if_started(self) -> None:
        if self._ble_driver_process is None:
            return
        try:
            self._terminate_process_tree(self._ble_driver_process)
            self.device_page.log("已停止本次自动启动的蓝牙桥接驱动", "info")
        except Exception as exc:
            self.device_page.log(f"停止蓝牙桥接驱动失败: {exc}", "error")
        finally:
            self._ble_driver_process = None

    def _on_typeless_toggled(self, enabled: bool) -> None:
        enabled = bool(enabled)
        if enabled and not cloud_settings.get_token():
            QMessageBox.warning(self, "请登录", "请先登录后再开启 AhaType。")
            self.tabs.setCurrentIndex(self._USER_TAB_INDEX)
            # 回拨 UI + 本地状态，避免误开启导致后续云端调用失败。
            typeless_store.set_typeless_enabled(False)
            self.connection_bar.set_typeless_enabled(False)
            return
        typeless_store.set_typeless_enabled(enabled)
        if enabled:
            self.device_page.log("AhaType 已启用：启动语音输入后，识别结果将经云端处理；不会弹出独立界面。", "info")
            QMessageBox.information(
                self,
                "AhaType 已启用",
                "AhaType 会在你启动语音输入后处理识别结果，不会弹出独立界面。\n请保持已登录状态。",
            )
        else:
            self.device_page.log("AhaType 已关闭", "info")

    def _load_audio_cue_enabled(self) -> bool:
        return _ui_settings().value("voice/audio_cue_enabled", True, bool)

    def _on_audio_cue_toggled(self, enabled: bool) -> None:
        self._apply_audio_cue_enabled(enabled, persist=True)

    def _apply_audio_cue_enabled(self, enabled: bool, persist: bool = True) -> None:
        self._audio_cue_enabled = bool(enabled)
        self.connection_bar.set_audio_cue_enabled(self._audio_cue_enabled)
        if persist:
            _ui_settings().setValue("voice/audio_cue_enabled", self._audio_cue_enabled)
        self._write_capswriter_shared_config()

    def _write_capswriter_shared_config(self) -> None:
        payload = {"enable_audio_cue": bool(getattr(self, "_audio_cue_enabled", True))}
        try:
            _AUDIO_CUE_CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
            _AUDIO_CUE_CONFIG_PATH.write_text(
                json.dumps(payload, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
        except OSError as exc:
            if hasattr(self, "device_page"):
                self.device_page.log(f"写入语音共享配置失败: {exc}", "error")

    def _voice_tool_search_roots(self) -> List[Path]:
        roots: List[Path] = []
        if getattr(sys, "frozen", False):
            roots.append(Path(sys.executable).resolve().parent)
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

    def _get_voice_tool_dir(self) -> Optional[Path]:
        for root in self._voice_tool_search_roots():
            for rel in _VOICE_TOOL_REL_DIRS:
                candidate = root / rel
                if _is_capswriter_voice_dir(candidate):
                    return candidate
        return None

    @staticmethod
    def _voice_launch_argv(tool_dir: Path, script_base: str) -> Optional[List[str]]:
        exe = tool_dir / f"{script_base}.exe"
        linux_bin = tool_dir / script_base
        py = tool_dir / f"{script_base}.py"
        if sys.platform == "win32":
            # 冻结后的配置工具运行在 KeyboardConfig.exe 内，若此处回退到
            # `sys.executable start_client.py`，会把配置工具自身再次拉起。
            if exe.is_file():
                return [str(exe)]
            if py.is_file():
                return [sys.executable, str(py)]
            return None

        if linux_bin.is_file():
            if not os.access(linux_bin, os.X_OK):
                try:
                    os.chmod(linux_bin, 0o755)
                except Exception:
                    pass
            return [str(linux_bin)]
        if py.is_file():
            return [sys.executable, str(py)]
        return None
        
    def _start_voice_stack(self):
        self._cleanup_voice_processes()
        if self._voice_process_map:
            self.connection_bar.set_voice_running(True)
            self._set_voice_status("ready", "语音已就绪")
            self.device_page.log("语音服务已在运行，跳过重复启动", "info")
            return

        self._set_voice_status("starting", "语音启动中")

        p_server = self._start_voice_tool("start_server", "语音服务器")
        if p_server:
            self._set_voice_status("starting", "模型已加载，正在启动服务")
        p_client = self._start_voice_tool("start_client", "语音客户端")
        if p_server or p_client:
            self.connection_bar.set_voice_running(True)
            self._set_voice_status("starting", "服务已启动，等待客户端连接")
            self._voice_ready_poll_timer.start()
        else:
            self._set_voice_status("error", "语音启动异常")

    def _start_voice_tool(self, script_base: str, display_name: str) -> Optional[subprocess.Popen]:
        old = self._voice_process_map.get(script_base)
        if old is not None and old.poll() is None:
            return old
        self._voice_process_map.pop(script_base, None)

        tool_dir = self._get_voice_tool_dir()
        if tool_dir is None:
            QMessageBox.warning(
                self,
                "启动失败",
                "未找到语音输入工程目录。\n"
                "请在「项目根目录」下放置 CapsWriter，例如：\n"
                "· Capswriter\\dist\\CapsWriter-Offline（打包后的 exe）\n"
                "· 或 Capswriter 源码目录（含 start_client.py / start_server.py）。\n"
                "与 vibe_code_config_tool 平级即可。"
            )
            self._set_voice_status("error", "语音启动异常")
            return None

        argv = self._voice_launch_argv(tool_dir, script_base)
        if not argv:
            QMessageBox.warning(
                self,
                "启动失败",
                f"未找到 {display_name} 启动文件（{script_base}.exe 或 {script_base}.py）：\n{tool_dir}",
            )
            self._set_voice_status("error", "语音启动异常")
            return None

        cmd = list(argv)
        child_env = os.environ.copy()
        api_base = cloud_settings.effective_api_base()
        if api_base:
            child_env["VIBE_TYPELESS_API_BASE"] = api_base
            child_env["VIBE_API_BASE"] = api_base
        child_env["CAPSWRITER_SHARED_CONFIG"] = str(_AUDIO_CUE_CONFIG_PATH)

        creationflags = 0
        startupinfo = None
        if sys.platform == "win32":
            creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= getattr(subprocess, "STARTF_USESHOWWINDOW", 0)
            startupinfo.wShowWindow = getattr(subprocess, "SW_HIDE", 0)

        try:
            p = subprocess.Popen(
                cmd,
                cwd=str(tool_dir),
                env=child_env,
                preexec_fn=os.setpgrp if sys.platform != "win32" else None,
                creationflags=creationflags,
                startupinfo=startupinfo,
            )
            self.device_page.log(
                f"{display_name} 已启动: {subprocess.list2cmdline(cmd)}",
                "info",
            )
            self._voice_processes.append(p)
            self._voice_process_map[script_base] = p
            QTimer.singleShot(2000, lambda p=p, name=display_name, key=script_base: self._verify_voice_process_started(p, name, key))
            return p
        except OSError as exc:
            self._set_voice_status("error", "语音启动异常")
            QMessageBox.warning(self, "启动失败", f"{display_name} 启动失败: {exc}")
            return None

    def _verify_voice_process_started(self, p: subprocess.Popen, display_name: str, script_base: str) -> None:
        current = self._voice_process_map.get(script_base)
        if current is not p:
            return
        code = p.poll()
        if code is None:
            return
        self._voice_process_map.pop(script_base, None)
        self._cleanup_voice_processes()
        if not self._voice_process_map:
            self.connection_bar.set_voice_running(False)
            self._voice_ready_poll_timer.stop()
            self._set_voice_status("error", "语音服务异常")
        msg = f"{display_name} 启动后立即退出，退出码: {code}"
        self.device_page.log(msg, "error")
        QMessageBox.warning(self, "语音启动失败", msg)

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

        if dead_keys and self._voice_running_expected():
            self._set_voice_status("error", "语音服务异常")

    def _stop_voice_stack(self):
        self._cleanup_voice_processes()
        self._voice_ready_poll_timer.stop()
        if self._voice_running_expected():
            self._set_voice_status("stopping", "语音关闭中")
        for p in list(self._voice_processes):
            try:
                self._terminate_process_tree(p)
            except Exception as e:
                self.device_page.log(f"停止进程失败: {e}", "error")

        self._voice_processes.clear()
        self._voice_process_map.clear()
        self.connection_bar.set_voice_running(False)
        self._set_voice_status("stopped", "语音未启动")
        self.device_page.log("语音服务已尝试关闭", "info")

    def _voice_running_expected(self) -> bool:
        return bool(self._voice_processes or self._voice_process_map or self.connection_bar._voice_running)

    def _set_voice_status(self, status: str, text: str = "") -> None:
        self.connection_bar.set_voice_status(status, text)
        self._set_voice_hud(status, text)

    @staticmethod
    def _voice_hud_enabled() -> bool:
        v = os.environ.get("CAPSWRITER_ENABLE_HUD", "").strip().lower()
        if not v:
            return True
        return v not in {"0", "false", "no", "off"}

    def _voice_hud_auto_hide_ms(self, status: str, text: str) -> int:
        content = (text or "").strip()
        if status == "ready":
            return 1400
        if status == "error":
            return 2600
        if content in {"准备粘贴", "复制失败", "粘贴失败"}:
            return 1200
        return 0

    def _voice_hud_text(self, status: str, text: str) -> str:
        if text:
            if text == "服务已启动，等待客户端连接":
                return "等待语音服务"
            return text
        fallback = {
            "starting": "语音启动中",
            "recording": "录音中",
            "processing": "处理中",
            "ready": "语音已就绪",
            "error": "语音异常",
            "stopping": "语音关闭中",
        }
        return fallback.get(status, "语音状态更新")

    def _set_voice_hud(self, status: str, text: str = "") -> None:
        if self._voice_hud is None:
            return
        if status == "stopped":
            self._voice_hud.hide_now()
            return
        hud_text = self._voice_hud_text(status, text)
        auto_hide_ms = self._voice_hud_auto_hide_ms(status, hud_text)
        self._voice_hud.set_status(status, hud_text, auto_hide_ms=auto_hide_ms)

    def _hide_voice_hud(self) -> None:
        if self._voice_hud is not None:
            self._voice_hud.hide_now()

    def _is_voice_service_ready(self) -> bool:
        try:
            with socket.create_connection((_VOICE_READY_HOST, _VOICE_READY_PORT), timeout=0.35):
                return True
        except OSError:
            return False

    def _update_voice_ready_state(self) -> None:
        self._cleanup_voice_processes()
        if not self._voice_process_map:
            self._voice_ready_poll_timer.stop()
            if self.connection_bar._voice_running:
                self.connection_bar.set_voice_running(False)
            if self.connection_bar._voice_status not in {"error", "stopped"}:
                self._set_voice_status("error", "语音服务异常")
            return

        if self._is_voice_service_ready():
            self._set_voice_status("ready", "语音已就绪")
            self.connection_bar.set_voice_running(True)
            self._voice_ready_poll_timer.stop()
        else:
            self._set_voice_status("starting", "服务已启动，等待客户端连接")

    def _ingest_voice_status_hint(self, hint: str) -> None:
        text = (hint or "").strip()
        if not text:
            return
        lowered = text.lower()
        if "录音" in text or "recording" in lowered:
            self._set_voice_status("recording", text)
            return
        if (
            "识别" in text
            or "处理中" in text
            or "准备粘贴" in text
            or "整理中" in text
            or "processing" in lowered
        ):
            self._set_voice_status("processing", text)
            return
        if "就绪" in text or "监听已启动" in text or "ready" in lowered:
            self._set_voice_status("ready", text)
            return
        if "关闭" in text or "stopping" in lowered:
            self._set_voice_status("stopping", text)
            return
        if "异常" in text or "失败" in text or "error" in lowered:
            self._set_voice_status("error", text)
            return
        self._set_voice_status("starting", text)

    def closeEvent(self, event):
        self._hide_voice_hud()
        self._stop_voice_stack()
        self._stop_ble_driver_if_started()
        super().closeEvent(event)
    def _on_connect(self, host: str, port: int):
        self._state.connect_device(host, port)

    def _on_disconnect(self):
        self._state.disconnect_device()

    def _on_connection_changed(self, connected: bool):
        self.connection_bar.set_connected(connected)
        if connected:
            self.device_page.log("设备已连接", "info")
            self._refresh_device_info()
        else:
            self.device_page.log("设备已断开", "error")

    def _refresh_device_info(self):
        self._state.query_status()
        self._state.query_info()

    def _on_ble_status(self, info: dict):
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
