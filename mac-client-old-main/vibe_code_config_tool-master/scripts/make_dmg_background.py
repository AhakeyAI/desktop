from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


WIDTH = 780
HEIGHT = 500


def load_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        "/System/Library/Fonts/PingFang.ttc",
        "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
        "/System/Library/Fonts/Supplemental/Helvetica.ttc",
    ]
    for candidate in candidates:
        path = Path(candidate)
        if path.is_file():
            try:
                return ImageFont.truetype(str(path), size=size)
            except Exception:
                continue
    return ImageFont.load_default()


def draw_background(draw: ImageDraw.ImageDraw) -> None:
    draw.rounded_rectangle((18, 18, WIDTH - 18, HEIGHT - 18), radius=26, fill=(248, 246, 240))
    draw.rounded_rectangle((36, 86, WIDTH - 36, HEIGHT - 48), radius=24, fill=(255, 255, 255))
    draw.line((84, 260, 690, 260), fill=(223, 213, 192), width=4)
    draw.polygon([(452, 260), (418, 242), (418, 278)], fill=(223, 213, 192))
    draw.polygon([(454, 260), (488, 242), (488, 278)], fill=(223, 213, 192))


def draw_copy(draw: ImageDraw.ImageDraw, app_name: str) -> None:
    title_font = load_font(40)
    subtitle_font = load_font(24)
    note_font = load_font(18)

    title = "Drag to Applications to install"
    subtitle = f"将 {app_name} 拖到右侧 Applications 完成安装"
    note = "首次打开如果被拦截，请到“系统设置 -> 隐私与安全性”里点“仍要打开”"

    draw.text((52, 34), title, fill=(44, 43, 37), font=title_font)
    draw.text((52, 94), subtitle, fill=(90, 86, 78), font=subtitle_font)
    draw.text((52, 442), note, fill=(120, 112, 96), font=note_font)

    left_caption = load_font(28)
    right_caption = load_font(28)
    draw.text((102, 330), "App", fill=(70, 67, 60), font=left_caption)
    draw.text((550, 330), "Applications", fill=(70, 67, 60), font=right_caption)


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: make_dmg_background.py OUTPUT.png [APP_NAME]", file=sys.stderr)
        return 1

    output_path = Path(sys.argv[1]).expanduser().resolve()
    app_name = (sys.argv[2] if len(sys.argv) > 2 else "Vibecoding Keyboard").strip() or "Vibecoding Keyboard"

    image = Image.new("RGB", (WIDTH, HEIGHT), (239, 232, 216))
    draw = ImageDraw.Draw(image)
    draw_background(draw)
    draw_copy(draw, app_name)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    image.save(output_path, format="PNG")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
