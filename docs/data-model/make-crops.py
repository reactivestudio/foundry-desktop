#!/usr/bin/env python3
"""Нарезает вырезки со стрелками для docs/data-model.md.

Исходные скриншоты лежат вне репозитория (они тяжёлые). Путь задаётся
переменной SRC, по умолчанию ~/Desktop/model.

    python3 docs/data-model/make-crops.py

Координаты в crops.json заданы в опорной ширине ref_w каждого исходника,
скрипт сам пересчитывает их в реальные пиксели.
"""

import json
import os
import pathlib
import sys

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent
SRC = pathlib.Path(os.environ.get("SRC", pathlib.Path.home() / "Desktop" / "model"))
OUT = ROOT / "img"

ACCENT = (255, 176, 32)          # янтарь: стрелка и рамка
MAX_W = 900                      # ширина готовой картинки


def draw_arrow(draw, x0, y0, x1, y1, width, head):
    """Стрелка из (x0,y0) в (x1,y1) — по горизонтали или по вертикали."""
    draw.line((x0, y0, x1, y1), fill=ACCENT, width=width)
    if y0 == y1:
        sign = 1 if x1 > x0 else -1
        tail = x1 - sign * head
        pts = [(x1, y1), (tail, y1 - head * 0.55), (tail, y1 + head * 0.55)]
    else:
        sign = 1 if y1 > y0 else -1
        tail = y1 - sign * head
        pts = [(x1, y1), (x1 - head * 0.55, tail), (x1 + head * 0.55, tail)]
    draw.polygon(pts, fill=ACCENT)


def render(spec, sources):
    src = sources[spec["src"]]
    path = SRC / src["file"]
    img = Image.open(path).convert("RGB")
    k = img.width / src["ref_w"]

    cx, cy, cw, ch = (round(v * k) for v in spec["crop"])
    tx, ty, tw, th = (round(v * k) for v in spec["target"])

    cx = max(0, min(cx, img.width - 1))
    cy = max(0, min(cy, img.height - 1))
    cw = min(cw, img.width - cx)
    ch = min(ch, img.height - cy)

    crop = img.crop((cx, cy, cx + cw, cy + ch))
    draw = ImageDraw.Draw(crop)

    # рамка вокруг поля
    rx, ry = tx - cx, ty - cy
    pad = round(6 * k)
    line_w = max(2, round(3 * k))
    draw.rounded_rectangle(
        (rx - pad, ry - pad, rx + tw + pad, ry + th + pad),
        radius=round(8 * k),
        outline=ACCENT,
        width=line_w,
    )

    # стрелка: первая сторона, где хватает места — слева, справа, сверху, снизу
    gap = round(14 * k)
    length = round(80 * k)
    head = max(6, round(11 * k))
    mx, my = rx + tw // 2, ry + th // 2
    left, right = rx - pad - gap, rx + tw + pad + gap
    top, bottom = ry - pad - gap, ry + th + pad + gap
    for fits, args in (
        (left - length > 2, (left - length, my, left, my)),
        (right + length < cw - 2, (right + length, my, right, my)),
        (top - length > 2, (mx, top - length, mx, top)),
        (bottom + length < ch - 2, (mx, bottom + length, mx, bottom)),
    ):
        if fits:
            draw_arrow(draw, *args, line_w, head)
            break

    if crop.width > MAX_W:
        crop = crop.resize(
            (MAX_W, round(crop.height * MAX_W / crop.width)), Image.LANCZOS
        )

    OUT.mkdir(parents=True, exist_ok=True)
    crop.save(OUT / f"{spec['id']}.webp", quality=88, method=6)
    return spec["id"]


def main():
    manifest = json.loads((ROOT / "crops.json").read_text())
    sources = manifest["sources"]
    missing = {
        s["file"] for s in sources.values() if not (SRC / s["file"]).exists()
    }
    if missing:
        print(f"нет исходников в {SRC}:", *sorted(missing), sep="\n  ")
        return 1
    for spec in manifest["crops"]:
        render(spec, sources)
    print(f"готово: {len(manifest['crops'])} вырезок в {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
