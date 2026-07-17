#!/usr/bin/env python3
"""Генерирует фон окна DMG и контрольный макет.

Вход:   App/Assets.xcassets/AppIcon.appiconset/icon_256.png  — иконка приложения
        системная иконка папки Applications (извлекается через sips)
Выход:  design/dmg/background.png     — 704×400 @1x
        design/dmg/background@2x.png  — 1408×800 @2x (appdmg подхватывает пару сам)
        design/dmg/mockup.png         — макет окна целиком, только для глаз

Перегенерация:  python3 design/dmg/generate-background.py
                (нужны numpy и Pillow: pip3 install numpy Pillow)

ПОЧЕМУ ФОН СВЕТЛЫЙ, хотя вся система тёмная. Подписи под иконками красит Finder,
и правило у него закрытое: оно НЕ монотонно по яркости фона (0.011 → чёрный,
0.057 → белый, 0.078 → снова чёрный), а запасной вариант — чёрный текст. На
тёмном фоне мы попадали именно в него, и «Foundry» читалось чёрным по чёрному.
Перекрасить подписи нечем: ни ключа в appdmg, ни атрибута у файла — только сам
фон. На светлом обе ветки правила дают одно и то же, поэтому светлый работает
всегда. Плюс так делает индустрия: Claude 0.860, ChatGPT 0.873, Obsidian 0.887,
Docker 0.950. Подложку под текст рисовать нельзя — отвергнуто.

Устройство фона — утверждённый эскиз «Заря» (v42, 2026-07-18):
  · бумага: перламутр по краям, середина выжжена добела, чтобы иконки стояли в
    световом пятне. Краски — брендовые (13-tokens): ультрамарин у левого верха,
    пурпур справа, маджента снизу, бирюза внизу слева — она замыкает ось и роднит
    бумагу с орбом. Спад слоёв smoothstep;
  · тени — пять РАЗНЕСЁННЫХ слоёв (STACK), у каждого своя сигма, свой снос и своя
    краска. Слоистость и «нет колец» уживаются только так: прежний веер из 96
    шагов приближал интегралом НЕПРЕРЫВНУЮ тень и по построению читался одним
    пятном, а кольца давал ровно своей дискретностью (сдвинутые копии маски).
    Сумма же пяти гауссиан гладкая всюду — кольцам взяться неоткуда;
  · стрелка — росчерк одним ходом кривизны (см. _gesture): подхват, петля, сбег.
    Петля симметрична и стоит по центру пролёта: пик кривизны по центру (m=0.5),
    вершина над основанием. Дрожь руки (_tremor) в дефолте ВЫКЛЮЧЕНА (amp=0) —
    она делала линию кривой; механизм оставлен на будущее, но стрелка ровная.
    Бусины одного калибра и через ровный шаг, подобранный так, чтобы сесть ровно
    в перекрестие (см. _beads);
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
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("Нужны numpy и Pillow:  pip3 install numpy Pillow")

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent

W, H, TITLE = 704, 400, 28          # окно DMG в pt; TITLE — только для макета
PAPER = (238, 235, 248)             # бумага «Зари»: перламутр, не белила
ICON, GAP = 128, 160
MARGIN = (W - (ICON + GAP + ICON)) // 2
APPX, DSTX = MARGIN + ICON // 2, W - MARGIN - ICON // 2      # 208 и 496
ICONY, LABY = 112, 248
ULTRA, PURPLE, MAGENTA = (47, 92, 255), (139, 92, 246), (214, 92, 255)
CYAN, WHITE = (88, 199, 255), (255, 255, 255)
LEAD = (84, 79, 112)                # грифель росчерка: не чёрный, иначе кричит

# Бумага: (краска, альфа, фокус x, фокус y, радиус x, радиус y, спад).
PAGE = [(ULTRA,   .32, .06, -.12, .85, .68, .58),
        (PURPLE,  .26, .97, .04, .68, .58, .56),
        (MAGENTA, .24, .70, 1.12, .62, .62, .58),
        (CYAN,    .16, .02, 1.04, .52, .52, .55),
        (WHITE,   .74, .50, .42, .58, .52, 1.0)]

# Тень: (имя, сигма, вниз, вправо, разрастание, альфа, краска).
# Краска светлеет и холодает от контакта к амбиенту — это не стилизация, а то,
# как ведёт себя отражённый свет: в плотное ядро у кромки он не доходит, а
# дальняя полутень набирает свет со всей комнаты. Снос вправо растёт (1→7):
# свет падает сверху-слева, как и на всей странице.
# Амбиент слаб НАМЕРЕННО (.10): fft_gauss берёт СИГМУ, и σ=68 при высоте окна
# 400 растекается на ±204pt. Дай ему вес — ляжет копотью на весь кадр.
STACK = [('контакт',  3.0,  3, 1, -2, .42, (30, 24, 58)),
         ('ближняя',  8.0,  8, 2,  0, .36, (44, 37, 82)),
         ('средняя', 18.0, 18, 3,  3, .32, (62, 55, 110)),
         ('дальняя', 38.0, 36, 5,  7, .24, (86, 80, 140)),
         ('амбиент', 68.0, 58, 7, 12, .10, (120, 114, 172))]

HEAD = dict(Lh=9.8, Wd=4.1, notch=0.83)   # notch — ГДЕ вырез по оси, а не глубина:
DOT, SPACING = 3.0, 7.5                   # 0.45 срезало бы спину на 55% в шеврон


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
    """Гауссиан через FFT целиком во float; нулевые поля глушат заворот.

    Берёт СИГМУ, не радиус. Об это уже спотыкались: опоры тёмного веера нельзя
    перенести множителем — то, что на почти чёрном читалось амбиентом, на светлом
    ложится копотью.
    """
    if pad is None:
        pad = int(3 * sigma) + 8
    f = np.pad(field, pad)
    fy = np.fft.fftfreq(f.shape[0])[:, None]
    fx = np.fft.rfftfreq(f.shape[1])[None, :]
    tf = np.exp(-2 * math.pi**2 * sigma**2 * (fx**2 + fy**2))
    out = np.fft.irfft2(np.fft.rfft2(f) * tf, s=f.shape)
    return out[pad:pad + field.shape[0], pad:pad + field.shape[1]].astype(np.float32)


def page_field(s):
    ws, hs = W * s, H * s
    ys, xs = np.mgrid[0:hs, 0:ws].astype(np.float32)
    img = np.empty((hs, ws, 3), np.float32)
    img[:] = PAPER
    for c, a0, fx, fy, rx, ry, st in PAGE:
        t = np.hypot((xs - fx * ws) / (rx * ws), (ys - fy * hs) / (ry * hs))
        u = np.clip(1 - t / st, 0, 1)
        a = (a0 * u * u * (3 - 2 * u))[..., None]   # smoothstep: без излома
        img += (np.float32(c) - img) * a
    return img


def _layer_alpha(s, icons, sigma, dy, dx, grow):
    ws, hs = W * s, H * s
    canvas = np.zeros((hs, ws), np.float32)
    for cx, icon in icons:
        size = int(round((ICON + 2 * grow) * s))
        m = np.asarray(icon.resize((size, size), Image.LANCZOS).split()[3],
                       np.float32) / 255
        x0 = int(round((cx - ICON // 2 - grow + dx) * s))
        y0 = int(round((ICONY - grow + dy) * s))
        h_, w_ = m.shape
        canvas[y0:y0 + h_, x0:x0 + w_] = np.maximum(canvas[y0:y0 + h_, x0:x0 + w_], m)
    return fft_gauss(canvas, sigma * s)


def lay_shadows(img, s, icons):
    """Кладём от широкой к плотной: амбиент внизу, контакт сверху — так свет и
    убывает. Вторым возвращаем суммарную альфу: она нужна только для замеров.

    Подписи тени не боятся: при альфе 0.27 под подписью бумага даёт Y≈0.49, и
    чёрный текст на ней держит 10.8:1. Порог «альфа ниже 0.06» был выдуман.
    """
    total = np.zeros(img.shape[:2], np.float32)
    for _, sigma, dy, dx, grow, alpha, tint in reversed(STACK):
        a = _layer_alpha(s, icons, sigma, dy, dx, grow) * alpha
        img = img * (1 - a[..., None]) + np.float32(tint) * a[..., None]
        total = total + a - total * a
    return img, np.clip(total, 0, 1)


def _bump(t, m, q):
    """Ход кривизны в петле: всходит к пику в позиции m и сходит, НИГДЕ не
    замирая. Участок постоянной кривизны — это и есть окружность, и рисует её
    только циркуль: раньше петля была кругла ровно на 0.0%, и именно это
    читалось чертёжным. Плато убрано насовсем.

    q — острота пика, единственный рычаг «круг ↔ баллон»: 0.45 → некруглость
    6% (ещё почти циркуль), 0.70 → 9% (рукописная петля), 1.6 → 19% (баллон).
    Ровно постоянной кривизна не бывает ни при каком q.
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
    (6.3). Нормируем на единицу: амплитуда задаётся снаружи, в долях кривизны.
    """
    rng = np.random.default_rng(seed)
    w = np.zeros_like(u)
    for f, a in bands:
        w += a * np.sin(2 * math.pi * f * u + rng.uniform(0, 2 * math.pi))
    return w / np.abs(w).max()


def _gesture(Rmin, c_in, c_out, Lpi, Lpo, m, q, phi, amp, seed):
    """Росчерк задан одним непрерывным ходом кривизны по длине дуги:

        −c_in·(1−u)²   подхват   u = arc/Lpi, круче всего у самого хвоста
        kmax·bump      петля     всход к пику 1/Rmin и сход, без плато
        −c_out·u²      сбег

    Скачок кривизны читался бы изломом даже при совпадении касательных, поэтому
    все переходы непрерывны. Длина петли не задаётся, а следует из поворота:
    полный поворот берём 2π−2φ, поэтому выход идёт на 2φ ниже входа, а горка
    возникает сама — её не подпирают ни прогибом, ни наклоном.

    ТРЕМОР МНОЖИТЕЛЬНЫЙ: k = k_база·(1 + amp·w). Аддитивный (k_база + amp·kmax·w)
    качал кривизну на ±0.0171 одинаково — крутит рука петлю или уже не крутит. У
    хвоста петли bump спадает к нулю, и там любая добавка перекидывала знак:
    перегиб садился за 10pt ДО конца петли, линия успевала раскрутиться обратно и
    только потом уйти к наконечнику. При amp·|w| < 1 знак равен знаку k_база
    всюду, и перегибы теперь ровно в нулях самой программы — больше нигде.
    Так и вернее по существу: рука ошибается в том, НАСКОЛЬКО подкрутить, а не в
    какую сторону, и ошибка растёт вместе с поправкой. Где рука не крутит —
    ошибаться не в чем, и дрожи там нет сама собой.

    ЗНАК СБЕГА. c_out > 0 (сбег обратен петле) даёт перегиб на стыке ПО
    ПОСТРОЕНИЮ: петля крутит в одну сторону, сбег в другую, между ними кривизна
    обязана пройти через ноль. c_out = 0 даёт прямую по линейке — первая примета
    машинного росчерка. Остаётся c_out < 0: сбег продолжает крутиться по ходу
    петли и выполаживается к острию. Цена неустранимая и её надо знать: перегиб
    ЕСТЬ смена знака кривизны, поэтому «хвост виляет» и «у хвоста нет перегибов»
    — одно требование с разными знаками. Хвост — одна чистая дуга; дрожь живёт
    там, где рука и правда крутит: на подхвате и в петле.

    Поворот держим точно: вычитаем ВЗВЕШЕННОЕ кривизной среднее — только оно
    оставляет ∫k·ds нетронутым, иначе выход уехал бы мимо папки.
    """
    kmax = 1 / Rmin
    tt = np.linspace(0, 1, 4000)
    f = _bump(tt, m, q)
    share = np.sum((f[1:] + f[:-1]) / 2 * np.diff(tt))   # поворот на единицу длины
    Lloop = (2 * math.pi - 2 * phi + (c_in * Lpi + c_out * Lpo) / 3) / (kmax * share)
    L = Lpi + Lloop + Lpo
    arc = np.arange(0, L, 0.04)
    a, b = Lpi, Lpi + Lloop
    kb = np.where(arc < a, -c_in * (1 - arc / Lpi) ** 2,
         np.where(arc < b, kmax * _bump((arc - a) / Lloop, m, q),
                  -c_out * ((arc - b) / Lpo) ** 2))
    trap = lambda f_: np.sum((f_[1:] + f_[:-1]) / 2 * np.diff(arc))
    w = _tremor(arc / L, seed)
    tb = trap(kb)
    if abs(tb) > 1e-9:
        w = w - trap(kb * w) / tb
    if amp * np.abs(w).max() >= 1:
        raise ValueError('тремор перекидывает знак: amp·|w| = %.2f'
                         % (amp * np.abs(w).max()))
    k = kb * (1 + amp * w)
    tz = lambda f_: np.concatenate(
        [[0], np.cumsum((f_[1:] + f_[:-1]) / 2 * np.diff(arc))])
    th = tz(k)
    return tz(np.cos(th)), tz(-np.sin(th)), k, a, b


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


def _path(x0, x1, y0, Rmin=20.5, c_in=1 / 120, c_out=-1 / 240,
          phi=math.radians(15), m=0.50, q=0.70, skew=0.010, amp=0.0, seed=3):
    """Хорда росчерка кладётся ровно в пролёт между иконками. Подгоняется не
    масштабом (он увёл бы размер петли), а длиной подхвата: хорда растёт по ней
    монотонно, поэтому деление пополам. Дальше — поворот хорды в горизонт.

    skew и m — РАЗНЫЕ рычаги, их легко свалить в один и потом гадать, почему
    петля, кренясь, уползает: skew двигает её по пролёту (сбег длиннее подхвата
    — петля левее), m наклоняет.

    amp — тремор в долях кривизны, seed — конкретный росчерк. Зерно здесь не
    «любое», а ВЫБРАННОЕ: при 0.35 форма цела на всех зёрнах, но рисунок петли и
    просадка на подходе у каждого свои, и зерно 3 отобрано глазами из шести.
    Поднимая amp, пересматривать зёрна заново, на проверку ниже не полагаться.
    """
    lo, hi = 1.0, 400.0
    for _ in range(50):
        mid = (lo + hi) / 2
        gx, gy = _gesture(Rmin, c_in, c_out, mid * (1 - skew), mid * (1 + skew),
                          m, q, phi, amp, seed)[:2]
        if math.hypot(gx[-1] - gx[0], gy[-1] - gy[0]) < x1 - x0:
            lo = mid
        else:
            hi = mid
    mid = (lo + hi) / 2
    gx, gy, k, a, b = _gesture(Rmin, c_in, c_out, mid * (1 - skew), mid * (1 + skew),
                               m, q, phi, amp, seed)
    ang = -math.atan2(gy[-1] - gy[0], gx[-1] - gx[0])
    ca, sa = math.cos(ang), math.sin(ang)
    xs, ys = x0 + gx * ca - gy * sa, y0 + gx * sa + gy * ca
    n = _crossings(xs, ys)
    if n != 1:
        raise ValueError(f'тремор испортил петлю: перекрестий {n}, а не одно')
    if ys.min() < ICONY - 16:
        raise ValueError(f'петля лезет вверх на иконки: верх y={ys.min():.0f}')
    return xs, ys, k, a, b


def _cross_arc(xs, ys, step=8):
    """Дуговые координаты самопересечения на обеих ветвях: (s1, s2, acc).
    Считаем по точкам пути, не по прореженным: нужна не проверка, а координата.
    """
    seg = np.hypot(np.diff(xs), np.diff(ys))
    acc = np.concatenate([[0], np.cumsum(seg)])
    N = len(xs) - 1
    for i in range(0, N, step):
        i2 = min(i + step, N)
        px, py = xs[i], ys[i]
        rx, ry = xs[i2] - px, ys[i2] - py
        for j in range(i2 + step * 4, N, step):
            j2 = min(j + step, N)
            qx, qy = xs[j], ys[j]
            sx, sy = xs[j2] - qx, ys[j2] - qy
            den = rx * sy - ry * sx
            if abs(den) < 1e-12:
                continue
            t = ((qx - px) * sy - (qy - py) * sx) / den
            u = ((qx - px) * ry - (qy - py) * rx) / den
            if 0 <= t <= 1 and 0 <= u <= 1:
                return (acc[i] + t * (acc[i2] - acc[i]),
                        acc[j] + u * (acc[j2] - acc[j]), acc)
    raise ValueError('перекрестие не найдено')


def _beads(xs, ys, target, head_back, dot, tol=0.15):
    """Шаг РОВНЫЙ, ловит перекрестие обеими ветвями, и наконечник встаёт в ритм.

    Перекрестие. Если бусина не села в точку самопересечения точно, она садится
    вплотную к чужой ветви и срастается с ней в кляксу; отсев такой бусины (так
    было раньше) оставлял двойной зазор. Целимся в саму точку: пусть перекрестие
    лежит на дугах s1 и s2, тогда

        s1 = φ + i·h  и  s2 = φ + j·h   ⇒   h делит (s2 − s1) нацело

    значит h = (s2 − s1)/m при целом m, а фаза берётся из s1. Обе ветви кладут
    бусину в одну точку, и две сливаются в одну: ни кучки, ни пропуска.

    Наконечник. Условие выше оставляет шаг КВАНТОВАННЫМ, поэтому «отступи столько-
    то» ничего не решает: последняя бусина садится не куда просят, а куда попал
    узел сетки. Раньше m брался округлением delta/target — и просвет до
    наконечника выходил 8.75pt при обычном 4.29, ровно вдвое шире, это было
    видно. Считаем наконечник последней «бусиной» ритма: просвет до его выреза
    должен равняться просвету между бусинами (h − dot), то есть последняя бусина
    обязана отстоять от острия на

        want = (h − dot) + dot/2 + head_back = h − dot/2 + head_back

    Перебираем m, у которых шаг не ушёл от заказанного дальше tol, и берём тот,
    где промах по want наименьший. Бусину, налезающую на вырез, не рассматриваем.

    Ровный шаг снимает закон двух третей (в повороте рука тормозит, v ~ κ^(−1/3))
    — он заказан. Рукотворность держится траекторией: тремор в кривизне и
    некруглая петля. Ровный калибр при этом на печать не похож: приметой машины
    была линейка, а её нет.
    """
    s1, s2, acc = _cross_arc(xs, ys)
    L, delta, R = acc[-1], s2 - s1, dot / 2
    dmin = head_back + R + 0.4                    # ближе — бусина въедет в вырез
    best = None
    for m in range(1, int(delta / (target * (1 - tol))) + 2):
        h = delta / m
        if abs(h / target - 1) > tol:
            continue
        ph = s1 - math.floor(s1 / h) * h
        n = int((L - dmin - ph) // h)
        if n < 2:
            continue
        last = ph + n * h
        err = abs((L - last) - (h - R + head_back))
        if best is None or err < best[0]:
            best = (err, m, h, ph, n)
    if best is None:
        raise ValueError('ни один шаг не лёг: перекрестие и ритм несовместимы')
    _, m, h, ph, n = best
    return ph + np.arange(n + 1) * h, acc, h


_OFF = (np.arange(16) + 0.5) / 16


def _discs(ws, hs, dx, dy, dia):
    """Точное покрытие круга, 16×16 подвыборок на пиксель: форма не зависит от
    того, куда лёг центр. PIL рисует ellipse без сглаживания, и при суперсэмпле
    бусина выходила многоугольником, который скалывался по-своему в зависимости
    от субпиксельного положения — отсюда были «точки разного размера и формы».
    Но главным виновником был РАЗМЕР: Ø1.5pt при 2x — это 3 пикселя, а круга из
    трёх пикселей не бывает, всегда квадратик. Калибр поэтому Ø3.0.
    """
    lay = np.zeros((hs, ws), np.float32)
    for x, y, d in zip(dx, dy, dia):
        r = d / 2
        x0, x1 = int(math.floor(x - r - 1)), int(math.ceil(x + r + 1))
        y0, y1 = int(math.floor(y - r - 1)), int(math.ceil(y + r + 1))
        x0, y0 = max(x0, 0), max(y0, 0)
        x1, y1 = min(x1, ws), min(y1, hs)
        if x1 <= x0 or y1 <= y0:
            continue
        gx = (np.arange(x0, x1)[:, None] + _OFF).ravel() - x
        gy = (np.arange(y0, y1)[:, None] + _OFF).ravel() - y
        m = (gx[None, :] ** 2 + gy[:, None] ** 2 <= r * r).astype(np.float32)
        m = m.reshape(y1 - y0, 16, x1 - x0, 16).mean((1, 3))
        lay[y0:y1, x0:x1] = np.maximum(lay[y0:y1, x0:x1], m)
    return lay


def _poly(ws, hs, pts):
    """Тот же приём для наконечника: заливка многоугольника по подвыборкам.
    Бока только прямые — гнуть их пробовали и внутрь, и наружу, и всякий раз у
    острия вырастал клюв: контрольная точка утаскивает контур с касательной
    острия. Изящество берётся пропорцией, а не изгибом.
    """
    P = np.asarray(pts, np.float64)
    x0, y0 = np.floor(P.min(0) - 1).astype(int)
    x1, y1 = np.ceil(P.max(0) + 1).astype(int)
    x0, y0, x1, y1 = max(x0, 0), max(y0, 0), min(x1, ws), min(y1, hs)
    gx = (np.arange(x0, x1)[:, None] + _OFF).ravel()
    gy = (np.arange(y0, y1)[:, None] + _OFF).ravel()
    X, Y = np.meshgrid(gx, gy)
    inside = np.zeros(X.shape, bool)
    for i in range(len(P)):
        ax, ay = P[i]
        bx, by = P[(i + 1) % len(P)]
        if ay == by:
            continue
        hit = (ay > Y) != (by > Y)
        inside ^= hit & (X < (bx - ax) * (Y - ay) / (by - ay) + ax)
    m = inside.astype(np.float32).reshape(y1 - y0, 16, x1 - x0, 16).mean((1, 3))
    lay = np.zeros((hs, ws), np.float32)
    lay[y0:y1, x0:x1] = m
    return lay


def arrow_alpha(s):
    ws, hs = W * s, H * s
    y0 = ICONY + ICON // 2
    x0, x1 = APPX + ICON // 2 + 16, DSTX - ICON // 2 - 16
    xs, ys, k, a, b = _path(x0, x1, y0)
    at, acc, h = _beads(xs, ys, SPACING, HEAD['Lh'] * HEAD['notch'], DOT)
    dx, dy = np.interp(at, acc, xs), np.interp(at, acc, ys)
    lay = _discs(ws, hs, dx * s, dy * s, np.full(len(at), DOT * s))
    back = int(np.searchsorted(acc, acc[-1] - 6))
    ang = math.atan2(ys[-1] - ys[back],    # касательная по хорде в 6pt: шаг точек
                     xs[-1] - xs[back])    # пути неравномерен, индексом её не мерить
    ca, sa = math.cos(ang), math.sin(ang)
    L_, Wd, nt = HEAD['Lh'], HEAD['Wd'], HEAD['notch']
    pts = [(xs[-1] * s + (u * ca - v * sa) * s, ys[-1] * s + (u * sa + v * ca) * s)
           for u, v in [(0, 0), (-L_, -Wd), (-L_ * nt, 0), (-L_, Wd)]]
    return np.maximum(lay, _poly(ws, hs, pts)), at, k, a, b


def dither8(img_f, amp=1.2, seed=7):
    """Единственное квантование конвейера: TPDF независимо по каналам.
    Finder показывает фон 1:1, поэтому мелкого октава достаточно.

    amp мерян так: самый длинный прогон одного байта ТАМ, ГДЕ ГРАДИЕНТ ИДЁТ
    (|df/dy| > 0.03), рядом контроль без дизера — он обязан быть хуже, иначе врёт
    сам тест. Без дизера 31px, 0.8 → 27, 1.2 → 18, 2.2 → 9, но шум уже виден.
    Критерий «байт стоит, пока float ушёл на единицу» тавтологичен: без дизера
    байт стоит ровно тогда, когда float не вышел из своей корзины.
    """
    rng = np.random.default_rng(seed)
    tpdf = (rng.random(img_f.shape, np.float32) +
            rng.random(img_f.shape, np.float32) - 1) * amp
    return np.clip(np.rint(img_f + tpdf), 0, 255).astype(np.uint8)


def render_background(s, icons):
    """Фон DMG: бумага + слоистая тень + росчерк. Иконки кладёт Finder."""
    img = page_field(s)
    img, _ = lay_shadows(img, s, icons)
    a = arrow_alpha(s)[0][..., None]
    img = img * (1 - a) + np.float32(LEAD) * a
    return Image.fromarray(dither8(img), 'RGB')


def render_mockup(bg2x, icons):
    """Контрольный макет: окно Finder с иконками и подписями — сверить глазами.
    Подписи ЧЁРНЫЕ, потому что чёрными их и кладёт Finder: ради этого весь фон и
    переехал на светлое. Если они тут вдруг нечитаемы — светлое не помогло.
    """
    s = 2
    win = Image.new('RGBA', (W * s, (H + TITLE) * s), (0, 0, 0, 0))
    win.paste(Image.new('RGB', (W * s, TITLE * s), (246, 246, 246)), (0, 0))
    content = bg2x.convert('RGBA')
    for cx, ic in icons:
        content.alpha_composite(ic.resize((ICON * s, ICON * s), Image.LANCZOS),
                                ((cx - ICON // 2) * s, ICONY * s))
    d = ImageDraw.Draw(content)
    try:
        f = ImageFont.truetype('/System/Library/Fonts/SFNS.ttf', 11 * s)
        for cx, t in ((APPX, 'Foundry'), (DSTX, 'Applications')):
            d.text((cx * s - d.textlength(t, font=f) / 2, LABY * s), t,
                   font=f, fill=(0, 0, 0))
    except OSError:
        pass                                    # нет системного шрифта — не беда
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
