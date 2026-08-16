from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps, ImageSequence


WIDTH = 160
HEIGHT = 80
MODES = ("Claude", "Cursor", "Codex", "Mode4")
ASSETS = (
    ("default", "DEFAULT", 8, (45, 112, 255)),
    ("running", "RUNNING", 12, (0, 190, 120)),
    ("waiting-error", "WAIT/ERROR", 12, (235, 145, 20)),
    ("completed", "COMPLETED", 12, (40, 180, 80)),
)
RESOURCE_MODES = ("claude", "cursor", "codex", "mode4")


def frame(mode: str, state: str, index: int, count: int, color: tuple[int, int, int]) -> Image.Image:
    image = Image.new("RGB", (WIDTH, HEIGHT), (5, 9, 18))
    draw = ImageDraw.Draw(image)
    font = ImageFont.load_default()
    draw.rounded_rectangle((4, 4, WIDTH - 5, HEIGHT - 5), radius=10, outline=color, width=2)
    draw.text((12, 13), mode, fill=(240, 245, 255), font=font)
    draw.text((12, 32), state, fill=color, font=font)
    draw.text((12, 51), f"FRAME {index + 1:02d}/{count:02d}", fill=(210, 220, 235), font=font)
    progress = int((WIDTH - 16) * (index + 1) / count)
    draw.rectangle((8, HEIGHT - 8, 8 + progress, HEIGHT - 5), fill=color)
    return image


def normalize_default_gif(source: Path, frame_count: int = 8) -> None:
    with Image.open(source) as image:
        source_frames = [
            ImageOps.fit(frame.convert("RGB"), (WIDTH, HEIGHT), method=Image.Resampling.LANCZOS)
            for frame in ImageSequence.Iterator(image)
        ]
        duration = image.info.get("duration", 100)
    selected = []
    for index in range(frame_count):
        source_index = min(len(source_frames) - 1, index * len(source_frames) // frame_count)
        current = source_frames[source_index].copy()
        # Preserve the requested frame count even when the source is a static image.
        ImageDraw.Draw(current).rectangle(
            (WIDTH - 3, HEIGHT - 3, WIDTH - 1, HEIGHT - 1),
            fill=(32 + index * 24, 0, 0),
        )
        selected.append(current)
    selected[0].save(
        source,
        save_all=True,
        append_images=selected[1:],
        duration=duration,
        loop=0,
        optimize=False,
        disposal=2,
    )


def main() -> None:
    project = Path(__file__).resolve().parents[1]
    bundled = project / "src" / "main" / "resources" / "default-gifs"
    for mode in RESOURCE_MODES:
        normalize_default_gif(bundled / mode / "default.gif")
    output = project / "artifacts" / "gif-layout-8-12-12-12"
    output.mkdir(parents=True, exist_ok=True)
    for mode in MODES:
        mode_dir = output / mode.lower()
        mode_dir.mkdir(parents=True, exist_ok=True)
        for slug, label, count, color in ASSETS:
            frames = [frame(mode, label, index, count, color) for index in range(count)]
            target = mode_dir / f"{mode.lower()}-{slug}-{count}f.gif"
            frames[0].save(
                target,
                save_all=True,
                append_images=frames[1:],
                duration=100,
                loop=0,
                optimize=False,
                disposal=2,
            )
    print(output)


if __name__ == "__main__":
    main()
