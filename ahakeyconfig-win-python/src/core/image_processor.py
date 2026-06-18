"""
图片处理 — 图片加载、缩放、RGB565 编码、GIF 帧提取
使用 Pillow 替代 OpenCV，数学运算一致
"""

from dataclasses import dataclass
from typing import Optional

import numpy as np
from PIL import Image

DISPLAY_WIDTH = 160
DISPLAY_HEIGHT = 80
FRAME_SLOT_SIZE = 4096 * 7  # 28672 bytes per frame slot
MAX_TOTAL_FRAMES = 74       # 设备限制


@dataclass
class ProcessedFrame:
    """处理后的单帧"""
    rgb565_data: bytes          # 25600 bytes of RGB565 big-endian
    preview_image: Image.Image  # 160x80 RGB PIL Image for UI preview


def extract_gif_frames(gif_path: str) -> list[Image.Image]:
    """从 GIF 文件提取所有帧"""
    frames = []
    with Image.open(gif_path) as img:
        for i in range(getattr(img, 'n_frames', 1)):
            img.seek(i)
            frames.append(img.convert("RGB").copy())
    return frames


def load_image(path: str) -> Image.Image:
    """加载单张图片"""
    return Image.open(path).convert("RGB")


def process_image(
    img: Image.Image,
    width: int = DISPLAY_WIDTH,
    height: int = DISPLAY_HEIGHT,
    h_align: int = 0,
    v_align: int = 0,
    bg_color: tuple[int, int, int] = (0, 0, 0),
) -> ProcessedFrame:
    """缩放图片并编码为 RGB565"""
    # 1. 等比缩放
    w_src, h_src = img.size
    scale = min(width / w_src, height / h_src)
    new_w = int(w_src * scale)
    new_h = int(h_src * scale)
    resized = img.resize((new_w, new_h), Image.LANCZOS)

    # 2. 创建背景
    canvas = Image.new("RGB", (width, height), bg_color)

    # 3. 计算对齐偏移
    if h_align < 0:
        x_offset = 0
    elif h_align == 0:
        x_offset = (width - new_w) // 2
    else:
        x_offset = width - new_w

    if v_align < 0:
        y_offset = 0
    elif v_align == 0:
        y_offset = (height - new_h) // 2
    else:
        y_offset = height - new_h

    # 4. 合成
    canvas.paste(resized, (x_offset, y_offset))

    # 5. 编码 RGB565
    rgb565_data = encode_rgb565_be(canvas)

    return ProcessedFrame(rgb565_data=rgb565_data, preview_image=canvas)


def encode_rgb565_be(img: Image.Image) -> bytes:
    """将 PIL RGB Image 编码为 RGB565 大端字节"""
    arr = np.array(img)
    r = arr[:, :, 0].astype(np.uint16)
    g = arr[:, :, 1].astype(np.uint16)
    b = arr[:, :, 2].astype(np.uint16)

    rgb565 = ((r << 8) & 0xF800) | ((g << 3) & 0x07E0) | (b >> 3)

    # Big-endian
    high = (rgb565 >> 8).astype(np.uint8)
    low = (rgb565 & 0xFF).astype(np.uint8)

    return np.stack((high, low), axis=-1).reshape(-1).tobytes()
