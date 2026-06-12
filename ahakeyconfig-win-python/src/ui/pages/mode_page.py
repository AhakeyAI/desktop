"""模式配置页。"""

import os
import tempfile

from PySide6.QtCore import QThread, Qt, Signal
from PySide6.QtWidgets import (
    QAbstractItemView,
    QFileDialog,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QListWidget,
    QListWidgetItem,
    QMessageBox,
    QProgressDialog,
    QPushButton,
    QSizePolicy,
    QSpinBox,
    QVBoxLayout,
    QWidget,
)

from ...comm.protocol import KeySubType
from ...core.image_processor import (
    FRAME_SLOT_SIZE,
    MAX_TOTAL_FRAMES,
    extract_gif_frames,
    load_image,
    process_image,
)
from ...core.keycodes import KeyType
from ...core.keymap import MAX_DESCRIPTION_LEN, MAX_KEY_DATA_LEN, KeyBinding, ModeConfig
from ..widgets.help_button import HelpButton
from ..widgets.image_preview import ImagePreview
from ..widgets.key_editor import KeyEditor
from ..widgets.keyboard_view import KeyboardView


_MODE0_DISPLAY_PRESETS = ("F18", "YES", "NO", "Enter")


class UploadWorker(QThread):
    progress = Signal(int, int)
    finished = Signal(bool, str)

    def __init__(self, service, mode_id, frames_data, start_index, fps):
        super().__init__()
        self._service = service
        self._mode_id = mode_id
        self._frames_data = frames_data
        self._start_index = start_index
        self._fps = fps

    def run(self):
        try:
            total = len(self._frames_data)
            for index, frame_bytes in enumerate(self._frames_data):
                address = (self._start_index + index) * FRAME_SLOT_SIZE
                self._service.write_large_data(address, frame_bytes)
                self.progress.emit(index + 1, total)

            self._service.update_pic(self._mode_id, self._start_index, total, fps=self._fps)
            self.finished.emit(True, "动画上传完成")
        except Exception as exc:
            self.finished.emit(False, str(exc))


class ModePage(QWidget):
    """单个模式的配置页。"""

    config_changed = Signal()
    def __init__(self, mode_config: ModeConfig, device_state=None, parent=None):
        super().__init__(parent)
        self._config = mode_config
        self._device_state = device_state
        self._processed_frames = []
        self._upload_worker = None
        self._setup_ui()
        self._refresh_ui()

    @property
    def mode_config(self) -> ModeConfig:
        return self._config

    def set_config(self, config: ModeConfig):
        self._config = config
        self._refresh_ui()

    def _setup_ui(self):
        root_layout = QVBoxLayout(self)
        root_layout.setContentsMargins(0, 0, 0, 0)
        root_layout.setSpacing(0)

        content_layout = QHBoxLayout()
        content_layout.setContentsMargins(0, 0, 0, 0)
        content_layout.setSpacing(12)

        keymap_group = self._build_keymap_group()
        display_group = self._build_display_group()

        for panel in (keymap_group, display_group):
            panel.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Maximum)

        content_layout.addWidget(keymap_group, 1)
        content_layout.addWidget(display_group, 1)
        root_layout.addLayout(content_layout)

    def _build_keymap_group(self) -> QGroupBox:
        group = QGroupBox()
        layout = QVBoxLayout(group)
        layout.setContentsMargins(12, 12, 12, 12)
        layout.setSpacing(12)
        layout.addLayout(
            self._build_group_header(
                "按键映射",
                "按键映射说明",
                "这里可以给当前模式下的每个按键分配功能。\n\n"
                "步骤最先是：点击顶部“连接”，连接成功后才可以更改键盘设置并写入设备。\n\n"
                "Key1 对应的是键盘最左边的语音键。\n\n"
                "适合用来设置常用快捷键、组合键、文本输入，或不同模式下的专用布局。\n\n"
                "快捷键设置\n"
                "示例：把 Key1 设置为 Ctrl+C 复制\n"
                "a. 进入“模式配置”页，选择要配置的模式，例如 Mode1。\n"
                "b. 在左侧 4 键示意图里点击 Key1。\n"
                "c. 在“按键描述”里输入便于识别的名字，例如 CTRL_C_COPY。按键描述会显示在键盘屏幕上，建议使用英文、数字或下划线。\n"
                "d. 在“按键类型”中选择“快捷键”。\n"
                "e. 在键码下拉框中选择 Left Ctrl，点击“添加”。\n"
                "f. 再选择字母 C，点击“添加”。\n"
                "g. 确认列表里已经有 Left Ctrl 和 C，最后点击“应用按键到设备”。\n\n"
                "宏设置示例：如果你想把某个键设为宏复制，可以把“按键类型”改为“宏”，按顺序添加："
                "按下 Left Ctrl -> 按下 C -> 延时 30 -> 释放 C -> 释放 Left Ctrl -> 释放全部按键。",
            )
        )

        self.keyboard_view = KeyboardView()
        self.keyboard_view.key_selected.connect(self._on_key_selected)
        layout.addWidget(self.keyboard_view)

        self.key_editor = KeyEditor()
        self.key_editor.binding_changed.connect(self._on_binding_changed)
        layout.addWidget(self.key_editor, stretch=1)

        apply_layout = QHBoxLayout()
        apply_layout.addStretch(1)
        apply_btn = QPushButton("应用按键到设备")
        apply_btn.setStyleSheet(
            "background-color: #2e7d32; color: white; font-weight: bold; "
            "padding: 8px 24px; min-width: 150px;"
        )
        apply_btn.clicked.connect(self._apply_keys_to_device)
        apply_layout.addWidget(apply_btn)
        apply_layout.addStretch(1)
        layout.addLayout(apply_layout)
        return group

    def _build_display_group(self) -> QGroupBox:
        group = QGroupBox()
        layout = QVBoxLayout(group)
        layout.setContentsMargins(12, 12, 12, 12)
        layout.setSpacing(12)
        layout.addLayout(
            self._build_group_header(
                "动画管理",
                "动画管理说明",
                "这里可以上传图片或 GIF，生成设备显示用的动画帧。\n\n"
                "步骤最先是：点击顶部“连接”，连接成功后才可以修改键盘设置并把动画写入设备。\n\n"
                "适合用来自定义开机动画、模式显示效果，或为不同模式准备不同视觉反馈。\n\n"
                "示例 1：如果你想给当前模式放一张静态图，可以点击“添加图片”，选中 png 或 jpg，"
                "在下方确认预览效果后上传到设备。\n\n"
                "示例 2：如果你想上传一段 GIF 动画，可以点击“添加 GIF”，导入文件后调整 FPS，"
                "先点“播放预览”看动画速度，再点击“上传到设备”。如果帧太多，建议先删掉不需要的帧"
                "或降低动画长度。",
            )
        )

        self.frame_list = QListWidget()
        self.frame_list.setDragDropMode(QAbstractItemView.InternalMove)
        self.frame_list.currentRowChanged.connect(self._on_frame_selected)
        layout.addWidget(self.frame_list, stretch=1)

        add_row = QHBoxLayout()
        add_img_btn = QPushButton("添加图片")
        add_img_btn.clicked.connect(self._add_images)
        add_row.addWidget(add_img_btn)

        add_gif_btn = QPushButton("添加 GIF")
        add_gif_btn.clicked.connect(self._add_gif)
        add_row.addWidget(add_gif_btn)
        layout.addLayout(add_row)

        action_row = QHBoxLayout()
        remove_btn = QPushButton("删除")
        remove_btn.clicked.connect(self._remove_frame)
        action_row.addWidget(remove_btn)

        clear_btn = QPushButton("清空")
        clear_btn.clicked.connect(self._clear_frames)
        action_row.addWidget(clear_btn)
        layout.addLayout(action_row)

        fps_row = QHBoxLayout()
        fps_row.addWidget(QLabel("FPS:"))
        self.fps_spin = QSpinBox()
        self.fps_spin.setRange(1, 30)
        self.fps_spin.setValue(10)
        self.fps_spin.valueChanged.connect(self._on_fps_changed)
        fps_row.addWidget(self.fps_spin)
        fps_row.addStretch()
        self.frame_count_label = QLabel("0 帧")
        fps_row.addWidget(self.frame_count_label)
        layout.addLayout(fps_row)

        self.image_preview = ImagePreview()
        layout.addWidget(self.image_preview, alignment=Qt.AlignHCenter)

        preview_btn_row = QHBoxLayout()
        preview_btn_row.addStretch(1)

        play_btn = QPushButton("播放预览")
        play_btn.clicked.connect(self._play_preview)
        preview_btn_row.addWidget(play_btn)

        upload_btn = QPushButton("上传到设备")
        upload_btn.setStyleSheet(
            "background-color: #1565c0; color: white; font-weight: bold; padding: 6px 16px;"
        )
        upload_btn.clicked.connect(self._upload_to_device)
        preview_btn_row.addWidget(upload_btn)

        preview_btn_row.addStretch(1)
        layout.addLayout(preview_btn_row)
        return group

    def _build_group_header(self, title: str, help_title: str, help_body: str) -> QHBoxLayout:
        layout = QHBoxLayout()
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(6)

        title_label = QLabel(title)
        title_label.setStyleSheet("font-size: 15px; font-weight: 700;")
        layout.addWidget(title_label)

        help_btn = HelpButton(help_title, help_body, self)
        layout.addWidget(help_btn, alignment=Qt.AlignVCenter)
        layout.addStretch(1)
        return layout

    @staticmethod
    def _binding_has_real_value(binding: KeyBinding) -> bool:
        return bool(binding.description or binding.keycodes or binding.macro_data)

    def _effective_key_labels(self) -> list[str]:
        labels: list[str] = []
        is_mode0 = self._config.mode_id == 0
        for index, binding in enumerate(self._config.keys):
            label = binding.label
            if (
                is_mode0
                and index < len(_MODE0_DISPLAY_PRESETS)
                and not self._binding_has_real_value(binding)
            ):
                label = _MODE0_DISPLAY_PRESETS[index]
            labels.append(label)
        return labels

    def _refresh_ui(self):
        labels = self._effective_key_labels()
        self.keyboard_view.update_key_labels(labels)

        key_index = self.keyboard_view.selected_key()
        if 0 <= key_index < len(self._config.keys):
            self.key_editor.set_binding(self._config.keys[key_index])

        self.fps_spin.setValue(self._config.display.fps)
        self._update_frame_list()

    def _on_key_selected(self, key_index: int):
        if 0 <= key_index < len(self._config.keys):
            self.key_editor.set_binding(self._config.keys[key_index])

    def _on_binding_changed(self, binding: KeyBinding):
        key_index = self.keyboard_view.selected_key()
        if 0 <= key_index < len(self._config.keys):
            self._config.keys[key_index] = binding
            self.keyboard_view.update_key_labels(self._effective_key_labels())
            self.config_changed.emit()

    def _on_fps_changed(self, value: int):
        self._config.display.fps = value
        self.config_changed.emit()

    def _update_frame_list(self):
        self.frame_list.clear()
        self._processed_frames.clear()
        for path in self._config.display.frame_paths:
            if os.path.exists(path):
                item = QListWidgetItem(os.path.basename(path))
                item.setData(Qt.UserRole, path)
                self.frame_list.addItem(item)
        self.frame_count_label.setText(f"{self.frame_list.count()} 帧")

    def _add_images(self):
        files, _ = QFileDialog.getOpenFileNames(
            self,
            "选择图片",
            "",
            "Images (*.png *.jpg *.jpeg *.bmp);;All Files (*)",
        )
        if files:
            self._config.display.frame_paths.extend(files)
            self._update_frame_list()
            self.config_changed.emit()

    def _add_gif(self):
        file_path, _ = QFileDialog.getOpenFileName(
            self,
            "选择 GIF",
            "",
            "GIF Files (*.gif);;All Files (*)",
        )
        if not file_path:
            return

        try:
            frames = extract_gif_frames(file_path)
            temp_dir = tempfile.mkdtemp(prefix="kb_frames_")
            for index, frame in enumerate(frames):
                path = os.path.join(temp_dir, f"frame_{index:04d}.png")
                frame.save(path)
                self._config.display.frame_paths.append(path)
            self._update_frame_list()
            self.config_changed.emit()
        except Exception as exc:
            QMessageBox.warning(self, "导入失败", f"GIF 解析失败: {exc}")

    def _remove_frame(self):
        row = self.frame_list.currentRow()
        if row >= 0:
            self._config.display.frame_paths.pop(row)
            self._update_frame_list()
            self.config_changed.emit()

    def _clear_frames(self):
        self._config.display.frame_paths.clear()
        self._update_frame_list()
        self.image_preview.clear()
        self.config_changed.emit()

    def _on_frame_selected(self, row: int):
        if 0 <= row < len(self._config.display.frame_paths):
            path = self._config.display.frame_paths[row]
            if os.path.exists(path):
                try:
                    img = load_image(path)
                    processed = process_image(img)
                    self.image_preview.set_single_image(processed.preview_image)
                except Exception:
                    pass

    def _play_preview(self):
        preview_images = []
        for path in self._config.display.frame_paths:
            if os.path.exists(path):
                try:
                    img = load_image(path)
                    processed = process_image(img)
                    preview_images.append(processed.preview_image)
                except Exception:
                    continue

        if preview_images:
            self.image_preview.set_animation(preview_images, self._config.display.fps)

    def upload_keys_to_device(self, service):
        mode_id = self._config.mode_id
        for key_index, binding in enumerate(self._config.keys):
            if binding.key_type == KeyType.SHORTCUT:
                data = bytes(binding.keycodes[:MAX_KEY_DATA_LEN])
                service.update_custom_key(mode_id, key_index, KeySubType.SHORTCUT, data)
            elif binding.key_type == KeyType.MACRO:
                data = bytes(binding.macro_data[:MAX_KEY_DATA_LEN])
                service.update_custom_key(mode_id, key_index, KeySubType.MACRO, data)

            desc_bytes = binding.description.encode("ascii", errors="ignore")[:MAX_DESCRIPTION_LEN]
            service.update_custom_key(mode_id, key_index, KeySubType.DESCRIPTION, desc_bytes)

    def _apply_keys_to_device(self):
        if not self._device_state or not self._device_state.connected:
            QMessageBox.information(self, "提示", "请先连接设备")
            return

        try:
            self.upload_keys_to_device(self._device_state.service)
            QMessageBox.information(self, "完成", "按键映射已发送到设备")
        except Exception as exc:
            QMessageBox.warning(self, "发送失败", str(exc))

    def upload_to_device(self, service, start_index: int):
        total_frames = len(self._config.display.frame_paths)
        if total_frames == 0:
            QMessageBox.information(self, "提示", "当前没有可上传的动画帧")
            return start_index

        progress = QProgressDialog("正在准备动画数据...", "取消", 0, total_frames, self)
        progress.setWindowModality(Qt.WindowModal)
        progress.setMinimumDuration(0)
        progress.setValue(0)

        frames_data = []
        for path in self._config.display.frame_paths:
            if progress.wasCanceled():
                return start_index
            if os.path.exists(path):
                try:
                    img = load_image(path)
                    processed = process_image(img)
                    frames_data.append(processed.rgb565_data)
                except Exception:
                    continue

        if not frames_data:
            progress.close()
            QMessageBox.information(self, "提示", "没有可用的动画帧数据")
            return start_index

        progress.setLabelText("正在上传动画数据...")
        progress.setMaximum(len(frames_data))
        progress.setValue(0)

        self._upload_worker = UploadWorker(
            service,
            self._config.mode_id,
            frames_data,
            start_index,
            self._config.display.fps,
        )
        self._upload_worker.progress.connect(lambda sent, _total: progress.setValue(sent))
        self._upload_worker.finished.connect(
            lambda ok, msg: self._on_upload_done(ok, msg, progress)
        )
        self._upload_worker.start()

        return start_index + len(frames_data)

    def _upload_to_device(self):
        if not self._device_state or not self._device_state.connected:
            QMessageBox.information(self, "提示", "请先连接设备")
            return

        try:
            all_states = []
            max_capacity = 0
            for mode_id in range(3):
                state = self._device_state.service.read_pic_state(mode_id)
                all_states.append(state)
                max_capacity = state.get("all_mode_max_pic", MAX_TOTAL_FRAMES)

            current_mode = self._config.mode_id
            new_count = len(self._config.display.frame_paths)
            if new_count == 0:
                QMessageBox.information(self, "提示", "当前没有可上传的动画帧")
                return

            occupied_regions = []
            for state in all_states:
                mode_id = state.get("mode", 0)
                if mode_id == current_mode:
                    continue
                start = state.get("start_index", 0)
                length = state.get("pic_length", 0)
                if length > 0:
                    occupied_regions.append((start, start + length, mode_id))

            occupied_regions.sort(key=lambda item: item[0])

            start_index = self._find_free_space(occupied_regions, new_count, max_capacity)
            end_index = start_index + new_count
            overlapped_modes = []
            for region_start, region_end, mode_id in occupied_regions:
                if not (end_index <= region_start or start_index >= region_end):
                    overlapped_modes.append(mode_id)

            if overlapped_modes:
                mode_names = [f"Mode {mode_id}" for mode_id in overlapped_modes]
                reply = QMessageBox.question(
                    self,
                    "动画空间冲突",
                    (
                        f"当前动画需要 {new_count} 帧空间。\n"
                        f"建议起始位置: {start_index}\n"
                        f"会覆盖: {', '.join(mode_names)}\n\n"
                        "继续上传会清空这些模式原有的动画数据，是否继续？"
                    ),
                    QMessageBox.Yes | QMessageBox.No,
                    QMessageBox.No,
                )
                if reply != QMessageBox.Yes:
                    return

                for mode_id in overlapped_modes:
                    self._device_state.service.update_pic(mode_id, 0, 0, fps=10)

            self.upload_to_device(self._device_state.service, start_index)
        except Exception as exc:
            QMessageBox.warning(self, "上传失败", str(exc))

    def _find_free_space(self, occupied_regions, needed_count, max_capacity):
        if not occupied_regions:
            return 0

        first_start = occupied_regions[0][0]
        if first_start >= needed_count:
            return 0

        for index in range(len(occupied_regions) - 1):
            gap_start = occupied_regions[index][1]
            gap_end = occupied_regions[index + 1][0]
            if gap_end - gap_start >= needed_count:
                return gap_start

        last_end = occupied_regions[-1][1]
        if last_end + needed_count <= max_capacity:
            return last_end

        if needed_count <= max_capacity:
            return 0

        return max(0, max_capacity - needed_count)

    def _on_upload_done(self, success: bool, message: str, progress: QProgressDialog):
        progress.close()
        if success:
            QMessageBox.information(self, "完成", message)
        else:
            QMessageBox.warning(self, "上传失败", message)
