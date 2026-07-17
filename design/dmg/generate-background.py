#!/usr/bin/env python3
"""Генерирует фон окна DMG и контрольный макет.

Вход:   App/Assets.xcassets/AppIcon.appiconset/icon_256.png  — иконка приложения
        системная иконка папки Applications (извлекается через sips)
Выход:  design/dmg/background.png     — 704×400 @1x
        design/dmg/background@2x.png  — 1408×800 @2x (appdmg подхватывает пару сам)
        design/dmg/mockup.png         — макет окна целиком, только для глаз

Перегенерация:  python3 design/dmg/generate-background.py
                (нужны numpy и Pillow: pip3 install numpy Pillow)

Устройство фона — утверждённый эскиз (v26, 2026-07-17):
  · база bg.overlay #1B1828 (13-tokens), поверх — .page-градиент: ультрамарин
    у левого верха, пурпур у правого, маджента снизу; спад слоёв smoothstep;
  · «световой пол» — альфа-белый эллипс по центру (канон 06 §5.5): на тёмном
    тень видна только на приподнятом фоне;
  · тени иконок пролиты вниз непрерывным веером из 96 шагов (blur 6→72pt,
    смещение 10→62pt) — дискретные слои дают «луковичные» ступени;
  · стрелка — точки Ø2.1pt по дуге с петлёй 46×52pt и лёгким прогибом,
    наконечник по касательной; под ней тёмное гало;
  · сами иконки НЕ впечатаны: их кладёт Finder по координатам из appdmg
    (центры: приложение 208,176 · Applications 496,176; размер 128).

Против «лесенок» весь композит считается во float32 (гаусс — FFT, PIL не
умеет блюрить float), квантование в 8 бит — одно на картинку, с поканальным
TPDF-дизером. Подробности граблей — memory проекта, dmg-gradient-banding.
"""

import math
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    import numpy as np
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("Нужны numpy и Pillow:  pip3 install numpy Pillow")

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent

W, H, TITLE = 704, 400, 28          # окно DMG в pt; TITLE — только для макета
BASE = (27, 24, 40)                 # 13 · bg.overlay #1B1828
ICON, GAP = 128, 160
MARGIN = (W - (ICON + GAP + ICON)) // 2
APPX, DSTX = MARGIN + ICON // 2, W - MARGIN - ICON // 2      # 208 и 496
ICONY, LABY = 112, 248
SH_TINT = np.float32((3, 2, 8))
ULTRA, PURPLE, MAGENTA = (47, 92, 255), (139, 92, 246), (214, 92, 255)
LIFT = (235, 232, 248)              # альфа-белый «пол» (06 §5.5)


def app_icon_rgba():
    return Image.open(
        ROOT / 'App/Assets.xcassets/AppIcon.appiconset/icon_256.png').convert('RGBA')


def folder_icon_rgba():
    icns = ('/System/Library/CoreServices/CoreTypes.bundle/'
            'Contents/Resources/ApplicationsFolderIcon.icns')
    with tempfile.NamedTemporaryFile(suffix='.png') as tmp:
        subprocess.run(['sips', '-s', 'format', 'png',
                        '--resampleHeightWidth', '256', '256',
                        icns, '--out', tmp.name],
                       check=True, capture_output=True)
        return Image.open(tmp.name).convert('RGBA')


def fft_gauss(field, sigma, pad=None):
    """Гауссиан через FFT целиком во float; нулевые поля глушат заворот."""
    if pad is None:
        pad = int(3 * sigma) + 8
    f = np.pad(field, pad)
    fy = np.fft.fftfreq(f.shape[0])[:, None]
    fx = np.fft.rfftfreq(f.shape[1])[None, :]
    tf = np.exp(-2 * math.pi**2 * sigma**2 * (fx**2 + fy**2))
    out = np.fft.irfft2(np.fft.rfft2(f) * tf, s=f.shape)
    return out[pad:pad + field.shape[0], pad:pad + field.shape[1]].astype(np.float32)


def page_field(s):
    layers = [(ULTRA, .16, .12, -.08, .90, .70, .55),
              (PURPLE, .14, .88, .04, .70, .60, .52),
              (MAGENTA, .10, .65, 1.08, .60, .60, .55),
              (LIFT, .14, .50, .44, .62, .55, 1.0)]
    ws, hs = W * s, H * s
    ys, xs = np.mgrid[0:hs, 0:ws].astype(np.float32)
    img = np.empty((hs, ws, 3), np.float32)
    img[:] = BASE
    for c, a0, fx, fy, rx, ry, st in layers:
        t = np.hypot((xs - fx * ws) / (rx * ws), (ys - fy * hs) / (ry * hs))
        u = np.clip(1 - t / st, 0, 1)
        a = (a0 * u * u * (3 - 2 * u))[..., None]   # smoothstep: без излома
        img += (np.float32(c) - img) * a
    return img


def shadow_alpha(s, icons):
    """Непрерывный веер: параметры интерполируются по 96 шагам между пятью
    опорами; обе тени в одном холсте, композит непрозрачностей."""
    anchors = dict(blur=[6, 14, 28, 48, 72], alpha=[.52, .42, .34, .26, .17],
                   dy=[10, 20, 32, 46, 62], grow=[0, 2, 5, 9, 14])
    N = 96
    ks = np.linspace(0, 4, N)
    P = {k: np.interp(ks, range(5), v) for k, v in anchors.items()}
    ws, hs = W * s, H * s
    masks = {}

    def grown(icon, grow):
        key = (id(icon), round(grow, 2))
        if key not in masks:
            size = int(round((ICON + 2 * grow) * s))
            masks[key] = np.asarray(
                icon.resize((size, size), Image.LANCZOS).split()[3],
                np.float32) / 255
        return masks[key]

    total = np.zeros((hs, ws), np.float32)
    for i in range(N):
        canvas = np.zeros((hs, ws), np.float32)
        for cx, icon in icons:
            g = P['grow'][i]
            m = grown(icon, g)
            x0 = int(round((cx - ICON // 2 - g) * s))
            y0 = int(round((ICONY - g + P['dy'][i]) * s))
            h_, w_ = m.shape
            canvas[y0:y0 + h_, x0:x0 + w_] = np.maximum(
                canvas[y0:y0 + h_, x0:x0 + w_], m)
        a = fft_gauss(canvas, P['blur'][i] * s) * (P['alpha'][i] * 5 / N)
        total = total + a - total * a
    return np.clip(total, 0, 1)


def _path(x0, x1, y0, R, drift, n=1400, bow=4.0, u_a=0.27, u_b=0.73):
    """Три фазы: прямая — петля — прямая, с едва заметным прогибом (bow).
    В петле горизонтальный ход почти останавливается (drift мал), поэтому
    след — правильная окружность радиуса R, а не растянутый движением
    завиток; небольшой drift оставляет внизу чистое перекрестие."""
    xA = (x0 + x1) / 2 - drift / 2      # петля по центру пролёта
    pts = []
    for i in range(n + 1):
        u = i / n
        y = y0 - bow * math.sin(math.pi * u)
        if u < u_a:
            x = x0 + (xA - x0) * (u / u_a)
        elif u <= u_b:
            t = (u - u_a) / (u_b - u_a)
            x = xA + drift * t + R * math.sin(2 * math.pi * t)
            y -= R * (1.0 - math.cos(2 * math.pi * t))
        else:
            x = xA + drift + (x1 - xA - drift) * ((u - u_b) / (1 - u_b))
        pts.append((x, y))
    return pts


def arrow_alpha(s, R=26.0, drift=10.0, dot=2.1, spacing=6.5):
    """Бусины и наконечник, 4x суперсэмпл; гало к ним считается отдельно."""
    K = 4
    ws, hs = W * s, H * s
    y0 = ICONY + ICON // 2
    x0, x1 = APPX + ICON // 2 + 16, DSTX - ICON // 2 - 16
    pts = _path(x0, x1, y0, R, drift)
    lay = Image.new('L', (ws * K, hs * K), 0)
    d = ImageDraw.Draw(lay)
    M = s * K
    acc = [0.0]
    for i in range(1, len(pts)):
        acc.append(acc[-1] + math.hypot(pts[i][0] - pts[i-1][0],
                                        pts[i][1] - pts[i-1][1]))
    head, hw = 9.5, 5.0
    stop = acc[-1] - head * 0.92 - dot      # бусины не заезжают под наконечник
    r = dot / 2 * M
    pos, j = 0.0, 1
    while pos <= stop:
        while acc[j] < pos:
            j += 1
        f = (pos - acc[j-1]) / (acc[j] - acc[j-1])
        x = (pts[j-1][0] + (pts[j][0] - pts[j-1][0]) * f) * M
        y = (pts[j-1][1] + (pts[j][1] - pts[j-1][1]) * f) * M
        d.ellipse([x - r, y - r, x + r, y + r], fill=228)
        pos += spacing
    ex, ey = pts[-1]
    px_, py_ = pts[-14]
    ang = math.atan2(ey - py_, ex - px_)
    tx, ty = ex * M, ey * M

    def rot(dx, dy):
        return (tx + (dx * math.cos(ang) - dy * math.sin(ang)) * M,
                ty + (dx * math.sin(ang) + dy * math.cos(ang)) * M)

    d.polygon([(tx, ty), rot(-head, -hw), rot(-head * 0.62, 0), rot(-head, hw)],
              fill=228)
    lay = lay.resize((ws, hs), Image.LANCZOS)
    return np.asarray(lay, np.float32) / 255


def dither8(img_f, amp=1.2, seed=7):
    """Единственное квантование конвейера: TPDF независимо по каналам.
    Finder показывает фон 1:1, поэтому мелкого октава достаточно."""
    rng = np.random.default_rng(seed)
    tpdf = (rng.random(img_f.shape, np.float32) +
            rng.random(img_f.shape, np.float32) - 1) * amp
    return np.clip(np.rint(img_f + tpdf), 0, 255).astype(np.uint8)


def render_background(s, icons):
    """Фон DMG: градиент + тени + стрелка с гало. Иконки кладёт Finder."""
    img = page_field(s)
    a_sh = shadow_alpha(s, icons)[..., None]
    img = img * (1 - a_sh) + SH_TINT * a_sh
    a_arr = arrow_alpha(s)
    halo = fft_gauss(a_arr, 7 * s) * (190 / 255)
    img = img * (1 - halo[..., None]) + SH_TINT * halo[..., None]
    img = img * (1 - a_arr[..., None]) + 255.0 * a_arr[..., None]
    return Image.fromarray(dither8(img), 'RGB')


def render_mockup(bg2x, icons):
    """Контрольный макет: окно Finder с иконками — сверить глазами."""
    s = 2
    win = Image.new('RGBA', (W * s, (H + TITLE) * s), (0, 0, 0, 0))
    win.paste(Image.new('RGB', (W * s, TITLE * s), (246, 246, 246)), (0, 0))
    content = bg2x.convert('RGBA')
    for cx, ic in icons:
        content.alpha_composite(ic.resize((ICON * s, ICON * s), Image.LANCZOS),
                                ((cx - ICON // 2) * s, ICONY * s))
    win.paste(content, (0, TITLE * s))
    d = ImageDraw.Draw(win)
    d.line([(0, TITLE * s), (W * s, TITLE * s)], fill=(214, 214, 214), width=1)
    for i, c in enumerate([(255, 95, 87), (255, 189, 46), (40, 201, 64)]):
        cc = (20 + i * 20) * s
        d.ellipse([cc - 6*s, TITLE*s//2 - 6*s, cc + 6*s, TITLE*s//2 + 6*s], fill=c)
    m = Image.new('L', win.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, win.width-1, win.height-1],
                                        radius=11 * s, fill=255)
    out = Image.new('RGBA', win.size, (0, 0, 0, 0))
    out.paste(win, (0, 0), m)
    return out.convert('RGB')


if __name__ == '__main__':
    icons = [(APPX, app_icon_rgba()), (DSTX, folder_icon_rgba())]
    bg1 = render_background(1, icons)
    bg1.save(OUT / 'background.png', dpi=(72, 72))
    bg2 = render_background(2, icons)
    bg2.save(OUT / 'background@2x.png', dpi=(144, 144))
    render_mockup(bg2, icons).save(OUT / 'mockup.png')
    print(f'→ {OUT}/background.png {bg1.size}, background@2x.png {bg2.size}, mockup.png')
