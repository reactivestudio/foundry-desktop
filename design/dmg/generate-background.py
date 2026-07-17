#!/usr/bin/env python3
"""Генерирует фон окна DMG и контрольный макет.

Вход:   App/Assets.xcassets/AppIcon.appiconset/icon_256.png  — иконка приложения
        системная иконка папки Applications (извлекается через sips)
Выход:  design/dmg/background.png     — 704×400 @1x
        design/dmg/background@2x.png  — 1408×800 @2x (appdmg подхватывает пару сам)
        design/dmg/mockup.png         — макет окна целиком, только для глаз

Перегенерация:  python3 design/dmg/generate-background.py
                (нужны numpy и Pillow: pip3 install numpy Pillow)

Устройство фона — утверждённый эскиз (v27, 2026-07-17):
  · база bg.overlay #1B1828 (13-tokens), поверх — .page-градиент: ультрамарин
    у левого верха, пурпур у правого, маджента снизу; спад слоёв smoothstep;
  · «световой пол» — альфа-белый эллипс по центру (канон 06 §5.5): на тёмном
    тень видна только на приподнятом фоне;
  · тени иконок пролиты вниз непрерывным веером из 96 шагов (blur 6→72pt,
    смещение 10→62pt) — дискретные слои дают «луковичные» ступени;
  · стрелка — росчерк одним ходом кривизны (см. _gesture): подхват, петля
    овалом с наклоном вперёд (плато нет — оно и есть циркуль), сбег; поверх —
    тремор руки в кривизне (_tremor), потому что стрелка описывает ход мыши,
    а мышью так идеально не водят; точки посажены по закону двух третей
    (_beads), калибр растёт Ø1.5→2.6pt;
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


def _bump(t, m, q):
    """Ход кривизны в петле: всходит к пику в позиции m и сходит, НИГДЕ не
    замирая. Участок постоянной кривизны — это и есть окружность, и рисует её
    только циркуль: раньше петля была кругла ровно на 0.0%, и именно это
    читалось чертёжным. Плато убрано насовсем.

    q — острота пика, единственный рычаг «круг ↔ баллон»: 0.45 → некруглость
    6% (ещё почти циркуль), 0.70 → 9% (рукописная петля), 1.6 → 19% (баллон).
    Ровно постоянной кривизна не бывает ни при каком q.

    m — где пик: >0.5 наклоняет петлю вперёд, как в рукописи; <0.5 заваливает
    назад, и росчерк читается чужой рукой.
    """
    rise = np.sin(np.pi / 2 * np.clip(t / m, 0, 1))
    fall = np.sin(np.pi / 2 * np.clip((1 - t) / (1 - m), 0, 1))
    return np.where(t < m, rise, fall) ** q


def _tremor(u, seed, bands=((0.9, 1.0), (2.1, 0.55), (3.7, 0.30), (6.3, 0.16))):
    """Шум РУКИ, а не контура. Стрелка описывает ход мыши, а мышью человек так
    не водит: он правит кривизну, и правит её с ошибкой. Поэтому шум кладём в
    кривизну — он интегрируется дважды, и путь остаётся гладким сам собой,
    изломов не бывает в принципе, сколько ни добавь. Шум в самом контуре дал бы
    дребезг.

    Полосы — от медленных поправок (0.9 периода на росчерк) к мелкому тремору
    (6.3). Нормируем на единицу: амплитуда задаётся снаружи, в долях 1/Rmin.
    """
    rng = np.random.default_rng(seed)
    w = np.zeros_like(u)
    for f, a in bands:
        w += a * np.sin(2 * math.pi * f * u + rng.uniform(0, 2 * math.pi))
    return w / np.abs(w).max()


def _gesture(Rmin, c, Lpi, Lpo, m, q, phi, amp, seed):
    """Росчерк задан одним непрерывным ходом кривизны по длине дуги:

        −c·(1−u)²   подхват   u = arc/Lpi, круче всего у самого хвоста
        kmax·bump   петля     всход к пику 1/Rmin и сход, без плато
        −c·u²       сбег

    Нулевой кривизны нет нигде, кроме двух точек на стыках, и в этом суть:
    прямая по линейке — первая примета машинного росчерка, рука так не ведёт.
    Скачок кривизны читался бы изломом даже при совпадении касательных, поэтому
    все переходы непрерывны. Обратная кривизна живёт только у концов и к петле
    сходит на нет: если вести её впритык к петле, низ выдувает в каплю.

    Длина петли не задаётся, а следует из поворота: полный поворот берём 2π−2φ,
    поэтому выход идёт на 2φ ниже входа, а горка возникает сама — её не
    подпирают ни прогибом, ни наклоном.

    Поверх всего — тремор руки (_tremor) в долях 1/Rmin. Его среднее вычитается:
    иначе шум сдвинул бы суммарный поворот и выход уехал бы мимо папки.
    """
    kmax = 1 / Rmin
    tt = np.linspace(0, 1, 4000)
    f = _bump(tt, m, q)
    share = np.sum((f[1:] + f[:-1]) / 2 * np.diff(tt))   # поворот на единицу длины
    Lloop = (2 * math.pi - 2 * phi + c * (Lpi + Lpo) / 3) / (kmax * share)
    L = Lpi + Lloop + Lpo
    arc = np.arange(0, L, 0.04)
    a, b = Lpi, Lpi + Lloop
    k = np.where(arc < a, -c * (1 - arc / Lpi) ** 2,
        np.where(arc < b, kmax * _bump((arc - a) / Lloop, m, q),
                 -c * ((arc - b) / Lpo) ** 2))
    u = arc / L
    w = _tremor(u, seed)
    w = w - np.sum((w[1:] + w[:-1]) / 2 * np.diff(u))    # нулевое среднее: поворот цел
    k = k + amp * kmax * w
    tz = lambda f_: np.concatenate(
        [[0], np.cumsum((f_[1:] + f_[:-1]) / 2 * np.diff(arc))])
    th = tz(k)
    return tz(np.cos(th)), tz(-np.sin(th)), k


def _crossings(xs, ys, step=12):
    """Сколько раз путь пересекает сам себя. Тремор может разорвать петлю или,
    наоборот, завязать вторую — а молча доехать до образа такое не должно."""
    X, Y = xs[::step], ys[::step]
    n = 0
    for i in range(len(X) - 1):
        for j in range(i + 3, len(X) - 1):
            px, py = X[i], Y[i]
            rx, ry = X[i+1] - px, Y[i+1] - py
            qx, qy = X[j], Y[j]
            sx, sy = X[j+1] - qx, Y[j+1] - qy
            den = rx * sy - ry * sx
            if abs(den) < 1e-12:
                continue
            t = ((qx - px) * sy - (qy - py) * sx) / den
            u = ((qx - px) * ry - (qy - py) * rx) / den
            if 0 <= t <= 1 and 0 <= u <= 1:
                n += 1
    return n


def _path(x0, x1, y0, Rmin=20.5, c=1 / 120, phi=math.radians(15),
          m=0.55, q=0.70, skew=0.28, amp=0.35, seed=3):
    """Хорда росчерка кладётся ровно в пролёт между иконками. Подгоняется не
    масштабом (он увёл бы размер петли), а длиной подхвата: хорда растёт по ней
    монотонно, поэтому деление пополам. Дальше — поворот хорды в горизонт.

    skew и m — РАЗНЫЕ рычаги, их легко свалить в один и потом гадать, почему
    петля, кренясь, уползает: skew двигает её по пролёту (сбег длиннее подхвата
    — петля левее), m наклоняет.

    amp — тремор в долях 1/Rmin, seed — конкретный росчерк. Зерно здесь не
    «любое», а ВЫБРАННОЕ: при 0.35 форма цела на всех зёрнах, но рисунок петли и
    просадка на подходе у каждого свои, и зерно 3 отобрано глазами из шести.
    Выше ~0.5 амплитуда начинает рвать петлю (зерно 19 разгибало её вовсе) —
    поднимая amp, пересматривать зёрна заново, на проверку ниже не полагаться.
    """
    lo, hi = 1.0, 400.0
    for _ in range(50):
        mid = (lo + hi) / 2
        gx, gy, _ = _gesture(Rmin, c, mid * (1 - skew), mid * (1 + skew),
                             m, q, phi, amp, seed)
        if math.hypot(gx[-1] - gx[0], gy[-1] - gy[0]) < x1 - x0:
            lo = mid
        else:
            hi = mid
    mid = (lo + hi) / 2
    gx, gy, k = _gesture(Rmin, c, mid * (1 - skew), mid * (1 + skew),
                         m, q, phi, amp, seed)
    ang = -math.atan2(gy[-1] - gy[0], gx[-1] - gx[0])
    ca, sa = math.cos(ang), math.sin(ang)
    xs, ys = x0 + gx * ca - gy * sa, y0 + gx * sa + gy * ca
    n = _crossings(xs, ys)
    if n != 1:
        raise ValueError(f'тремор испортил петлю: перекрестий {n}, а не одно')
    if ys.min() < ICONY - 16:
        raise ValueError(f'петля лезет вверх на иконки: верх y={ys.min():.0f}')
    return xs, ys, k


def _beads(xs, ys, k, spacing, ease):
    """Бусины ставятся не через равные расстояния, а через равные промежутки
    ВРЕМЕНИ, и скорость руки идёт по закону двух третей (Вивиани): в повороте
    рука тормозит, v ~ κ^(−1/3). Отсюда v = (|κ| + ease)^(−1/3) — в петле бусины
    сходятся, на подходе расходятся. Метрономный шаг — вторая примета машины
    после линейки. ease держит скорость конечной там, где кривизна почти нулевая,
    и заодно задаёт глубину эффекта; средний шаг остаётся spacing.
    """
    seg = np.hypot(np.diff(xs), np.diff(ys))
    acc = np.concatenate([[0], np.cumsum(seg)])
    v = (np.abs(k) + ease) ** (-1 / 3)
    t = np.concatenate([[0], np.cumsum(seg / ((v[1:] + v[:-1]) / 2))])
    n = max(2, int(round(acc[-1] / spacing)))
    return np.interp(np.arange(n) * t[-1] / n, t, acc), acc


def _uncollide(dx, dy, dot, dmin):
    """На перекрестии бусина садится вплотную к чужой ветви и срастается с ней
    в пилюлю — росчерк выдаёт себя кляксой. Такую не ставим: пропуск на
    перекрестии рука делает сама. Соседей по ходу (i−j < 3) не проверяем — у них
    свой шаг, заведомо больше dmin."""
    keep = []
    for i in range(len(dx)):
        if any(i - j >= 3 and math.hypot(dx[i] - dx[j], dy[i] - dy[j]) < dmin
               for j in keep):
            continue
        keep.append(i)
    return dx[keep], dy[keep], dot[keep]


def arrow_alpha(s, dot0=1.5, dot1=2.6, spacing=6.5, ease=0.03):
    """Бусины и наконечник, 4x суперсэмпл; гало к ним считается отдельно.

    Калибр бусины растёт по ходу dot0 → dot1: росчерк начинается касанием и
    набирает вес к наконечнику. Одинаковые бусины — третья примета печати после
    линейки и метронома. dot0 не опускать ниже ~1.4pt: тоньше — и в DMG, где
    Finder показывает фон 1:1, хвост вырождается в крупинки и читается грязью,
    а не изяществом (проверено на 1.1pt).
    """
    K = 4
    ws, hs = W * s, H * s
    y0 = ICONY + ICON // 2
    x0, x1 = APPX + ICON // 2 + 16, DSTX - ICON // 2 - 16
    xs, ys, k = _path(x0, x1, y0)
    head, hw, notch = 11.0, 3.4, 0.45   # тонкое перо, не дротик: рядом с бусинами
    at, acc = _beads(xs, ys, k, spacing, ease)
    at = at[at <= acc[-1] - head * 0.92 - dot1]  # бусины не заезжают под наконечник
    dot = dot0 + (dot1 - dot0) * at / acc[-1]
    dx, dy, dot = _uncollide(np.interp(at, acc, xs), np.interp(at, acc, ys), dot, 4.3)
    lay = Image.new('L', (ws * K, hs * K), 0)
    d = ImageDraw.Draw(lay)
    M = s * K
    for x, y, dia in zip(dx * M, dy * M, dot / 2 * M):
        d.ellipse([x - dia, y - dia, x + dia, y + dia], fill=228)
    back = int(np.searchsorted(acc, acc[-1] - 6))
    ang = math.atan2(ys[-1] - ys[back],    # касательная по хорде в 6pt: шаг точек
                     xs[-1] - xs[back])    # пути неравномерен, индексом её не мерить
    tx, ty = xs[-1] * M, ys[-1] * M

    def rot(dx, dy):
        return (tx + (dx * math.cos(ang) - dy * math.sin(ang)) * M,
                ty + (dx * math.sin(ang) + dy * math.cos(ang)) * M)

    d.polygon([(tx, ty), rot(-head, -hw), rot(-head * notch, 0), rot(-head, hw)],
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
