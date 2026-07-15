#!/usr/bin/env python3
"""Собирает AppIcon.appiconset для Xcode из мастер-рендера иконки.

Вход:   design/foundry-app-icon-1024.png — квадрат 1024×1024 без скругления.
Выход:  App/Assets.xcassets/AppIcon.appiconset/ — PNG всех размеров + Contents.json.

Выход — единственный источник правды по иконке; готовых наборов рядом с мастером
не держим, иначе они расходятся (так и случилось однажды). Перегенерация:

    python3 design/make-appiconset.py        # нужен Pillow: pip3 install Pillow

Артворк кладётся по сетке macOS Big Sur: тело занимает не весь канвас, а
центральный квадрат со скруглением, вокруг — прозрачные поля. Без полей иконка
в Dock выглядит крупнее системных.
"""

import json
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("Нужен Pillow:  pip3 install Pillow")

# Сетка macOS Big Sur: на канвасе 1024 тело — 824×824, поля по 100 px.
CANVAS_SIZE = 1024
BODY_SIZE = 824
CORNER_RADIUS = round(BODY_SIZE * 0.2237)  # непрерывный угол Apple ≈ 184
SUPERSAMPLE = 4  # маска строится крупнее и ужимается — гладкая кромка

SIZES = (16, 32, 64, 128, 256, 512, 1024)

# Стандартная macOS-сетка: 16→512, каждый в @1x и @2x.
CONTENTS = {
    "images": [
        {"idiom": "mac", "size": f"{point}x{point}", "scale": f"{scale}x",
         "filename": f"icon_{point * scale}.png"}
        for point in (16, 32, 128, 256, 512)
        for scale in (1, 2)
    ],
    "info": {"version": 1, "author": "xcode"},
}

REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
MASTER_PATH = REPOSITORY_ROOT / "design" / "foundry-app-icon-1024.png"
ICONSET_PATH = REPOSITORY_ROOT / "App" / "Assets.xcassets" / "AppIcon.appiconset"


def build_rounded_mask() -> Image.Image:
    """Маска тела: скруглённый квадрат, сглаженный супер-семплированием."""
    large = Image.new("L", (BODY_SIZE * SUPERSAMPLE, BODY_SIZE * SUPERSAMPLE), 0)
    ImageDraw.Draw(large).rounded_rectangle(
        [0, 0, BODY_SIZE * SUPERSAMPLE - 1, BODY_SIZE * SUPERSAMPLE - 1],
        radius=CORNER_RADIUS * SUPERSAMPLE,
        fill=255,
    )
    return large.resize((BODY_SIZE, BODY_SIZE), Image.LANCZOS)


def build_canvas(master: Image.Image) -> Image.Image:
    """Мастер → тело по сетке, центрированное на прозрачном канвасе."""
    body = master.resize((BODY_SIZE, BODY_SIZE), Image.LANCZOS)
    body.putalpha(build_rounded_mask())

    canvas = Image.new("RGBA", (CANVAS_SIZE, CANVAS_SIZE), (0, 0, 0, 0))
    margin = (CANVAS_SIZE - BODY_SIZE) // 2
    canvas.paste(body, (margin, margin), body)
    return canvas


def main() -> None:
    if not MASTER_PATH.exists():
        sys.exit(f"Мастер не найден: {MASTER_PATH}")

    master = Image.open(MASTER_PATH).convert("RGBA")
    if master.size != (CANVAS_SIZE, CANVAS_SIZE):
        sys.exit(f"Мастер обязан быть {CANVAS_SIZE}×{CANVAS_SIZE}, а он {master.size[0]}×{master.size[1]}")

    canvas = build_canvas(master)
    ICONSET_PATH.mkdir(parents=True, exist_ok=True)

    for size in SIZES:
        canvas.resize((size, size), Image.LANCZOS).save(ICONSET_PATH / f"icon_{size}.png")

    (ICONSET_PATH / "Contents.json").write_text(json.dumps(CONTENTS, indent=2) + "\n")

    print(f"Готово: {len(SIZES)} PNG + Contents.json → {ICONSET_PATH.relative_to(REPOSITORY_ROOT)}")


if __name__ == "__main__":
    main()
