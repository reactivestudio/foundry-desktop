#!/usr/bin/env python3
"""Собирает AppIcon.appiconset для Xcode из мастер-рендера иконки.

Вход:   design/foundry-app-icon-1024.png — квадрат 1024×1024 без скругления.
Выход:  App/Assets.xcassets/AppIcon.appiconset/ — PNG всех размеров + Contents.json.

Выход — единственный источник правды по иконке; готовых наборов рядом с мастером
не держим, иначе они расходятся (так и случилось однажды). Перегенерация:

    python3 design/make-appiconset.py        # нужен Pillow: pip3 install Pillow

Две вещи задаются порознь и не путаются: РАЗМЕР плитки — по сетке macOS, чтобы в
Dock иконка стояла вровень с системными; ФОРМА угла — с референса incident.io.
"""

import json
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit("Нужен Pillow:  pip3 install Pillow")

CANVAS_SIZE = 1024  # мастер-рендер; сам набор нарезается по таблице ниже

# Поля вокруг тела — снято с 95 системных иконок (icns → iconutil -c iconset,
# симметричные squircle-плитки, взято согласие большинства по каждому канвасу):
#
#     канвас   поле   тело   доля    согласны
#         16      1     14   0.8750   62 из 74
#         32      2     28   0.8750   67 из 87
#         64      6     52   0.8125    8 из 15
#        128     12    104   0.8125   62 из 74
#        256     25    206   0.8047   72 из 82
#        512     50    412   0.8047   19 из 27
#       1024    100    824   0.8047    9 из 13
#
# Доля тела НЕ постоянна: на 16 и 32 Apple намеренно оставляет меньше полей
# (0.875 против 0.8047) — на мелких размерах поля съедали бы то, чем иконка
# читается. Поэтому здесь таблица, а не одна константа с делением: заодно поля
# выходят целыми и симметричными на каждом размере, а не «как ляжет округление».
#
# Поля обязаны быть: у macOS они входят в саму картинку, а не добавляются
# системой. Плитка в край — это иконка, торчащая в Dock крупнее соседей.
MARGINS = {16: 1, 32: 2, 64: 6, 128: 12, 256: 25, 512: 50, 1024: 100}

# Углы — squircle. Важен не радиус, а ход кривизны вдоль дуги: скругление
# начинается далеко от угла почти прямым (радиус огромный), к диагонали ужимается
# и симметрично раскрывается обратно. Дуга окружности так не умеет вовсе — радиус
# постоянный, кривизна включается изломом в точке касания.
#
# Форма снята с угла референса incident.io: контур вытащен субпиксельно с
# оригинального скриншота (плитка 204 px, фон ровный, тени нет) и подогнан тремя
# моделями. Максимальное отклонение силуэта:
#
#     дуга окружности           4.97 px
#     кривая Apple .continuous  2.34 px
#     суперэллипс x⁴+y⁴         0.49 px   <- это она, на уровне шума замера
#
# То есть у референса НЕ системная кривая macOS, а канонический сквиркл Ламе
# |x/L|ⁿ + |y/L|ⁿ = 1 при n = 4 (свободная подгонка даёт 4.025 — четвёрка ровно).
# Он загибается заметно раньше кривой Apple (0.404 тела против 0.346) и сильнее
# ужимается на диагонали (R = 164 против 205 при теле 824).
#
# Заход угла кажется меньше, чем есть: у суперэллипса кромка подходит к стороне
# асимптотически, и последние ~2% тела отстоят от неё меньше чем на 0.05 px.
# Мерить заход порогом «отклонилось от прямой» бесполезно — только подгонкой
# всей кривой. Доля от ТЕЛА, не от канваса: форма едет за размером плитки сама.
CORNER_EXTENT = 0.4042  # доля тела, на которой угол сходит на прямую сторону
CORNER_POWER = 4.0      # показатель суперэллипса

SIZES = tuple(sorted(MARGINS))

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


def _edge_x(y: float, extent: float) -> float:
    """X кромки суперэллипса на высоте y; отсчёт от угла плитки, 0 — уже сторона."""
    if y >= extent:
        return 0.0
    return extent * (1.0 - (1.0 - (1.0 - y / extent) ** CORNER_POWER) ** (1.0 / CORNER_POWER))


def _corner_coverage(extent: float, quadrature: int = 64) -> list:
    """Углова́я таблица [строка][столбец] → доля площади пикселя под телом.

    Считается формулой, а не растеризацией: тело на высоте y лежит правее кромки,
    значит покрытие пикселя — это средняя по высоте строки длина пересечения
    отрезка [X, X+1] с лучом [edge_x(y), +∞). Ни полигона, ни супер-семпла, ни
    ресайза: кромку негде «съесть» фильтром и негде сдвинуть на полпикселя.
    Прежняя сборка (полигон на 8×, LANCZOS вниз) промахивалась по альфе до 47 из
    255 и систематически недобирала материал на кромке; здесь — 0.01 в среднем.
    """
    rows = int(extent) + 1
    grid = []
    for row in range(rows):
        cut = [0.0] * rows       # пиксель, который кромка режет: доля справа от неё
        solid = [0] * (rows + 1)  # правее реза тело идёт целиком — отметка начала
        for i in range(quadrature):
            edge = _edge_x(row + (i + 0.5) / quadrature, extent)
            column = int(edge)
            cut[column] += column + 1 - edge
            solid[column + 1] += 1
        run = 0
        line = []
        for column in range(rows):
            run += solid[column]
            line.append((cut[column] + run) / quadrature)
        grid.append(line)
    return grid


def build_rounded_mask(side: int) -> Image.Image:
    """Маска тела нужного размера: середина сплошная, все четыре угла — из таблицы."""
    grid = _corner_coverage(CORNER_EXTENT * side)
    mask = Image.new("L", (side, side), 255)
    pixels = mask.load()
    for row, line in enumerate(grid):
        for column, value in enumerate(line):
            shade = round(value * 255)
            for x, y in ((column, row), (side - 1 - column, row),
                         (column, side - 1 - row), (side - 1 - column, side - 1 - row)):
                pixels[x, y] = shade
    return mask


def build_canvas(master: Image.Image, size: int) -> Image.Image:
    """Мастер → готовая иконка размера size: тело по сетке macOS на прозрачных полях.

    Маска считается заново под каждый размер, а не ужимается с 1024: пересемпл
    альфы фильтром — это ровно та потеря кромки, ради ухода от которой её и
    считают формулой. Маска кладётся на НЕПРОЗРАЧНОЕ тело и только потом тело
    садится на прозрачный канвас: ресайзить RGBA с прозрачным фоном нельзя —
    LANCZOS ресемплит RGB отдельно от альфы и затянет фон в кромку.
    """
    margin = MARGINS[size]
    body_size = size - 2 * margin

    body = master.resize((body_size, body_size), Image.LANCZOS)
    body.putalpha(build_rounded_mask(body_size))

    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(body, (margin, margin))
    return canvas


def main() -> None:
    if not MASTER_PATH.exists():
        sys.exit(f"Мастер не найден: {MASTER_PATH}")

    master = Image.open(MASTER_PATH).convert("RGBA")
    if master.size != (CANVAS_SIZE, CANVAS_SIZE):
        sys.exit(f"Мастер обязан быть {CANVAS_SIZE}×{CANVAS_SIZE}, а он {master.size[0]}×{master.size[1]}")

    ICONSET_PATH.mkdir(parents=True, exist_ok=True)

    for size in SIZES:
        build_canvas(master, size).save(ICONSET_PATH / f"icon_{size}.png")

    (ICONSET_PATH / "Contents.json").write_text(json.dumps(CONTENTS, indent=2) + "\n")

    print(f"Готово: {len(SIZES)} PNG + Contents.json → {ICONSET_PATH.relative_to(REPOSITORY_ROOT)}")


if __name__ == "__main__":
    main()
