# -*- coding: utf-8 -*-
"""Ищет обрезанные чипы по пикселям, а не на глаз.

Два раза подряд подпись уезжала за кромку карточки и обрубалась посреди буквы,
и оба раза это ловилось только зумом. Признак формальный и не зависит от
геометрии: у целой пилюли крайний правый столбец — это закругление, в нём
два-три пикселя; у обрезанной там ровный вертикальный срез во всю высоту.
"""
import sys
from collections import deque
from PIL import Image

CHIPS = {'янтарь': (251, 191, 36), 'коралл': (255, 138, 115),
         'нейтральный': (46, 46, 54), 'принят': (38, 38, 44)}
FLAT = 13         # пикселей в крайнем столбце — уже срез, а не закругление
CHIP_H = (18, 22) # высота пилюли; всё прочее того же цвета — не чип
FULL = 106        # шире этого чип не бывает: значит, подпись урезана многоточием

im = Image.open(sys.argv[1]).convert('RGB')
W, H = im.size
px = im.load()

def dist(a, b):
    return sum(abs(a[i] - b[i]) for i in range(3))


def cut(right, wall, col):
    """Ровный срез и ЗАТУХАНИЕ дают одинаково прямую стену: проверка сравнивает
    цвета точно, а под градиентом прибитой колонки точное совпадение кончается
    по вертикали — ровно там, где цвет начал гаснуть. Без развилки проверка
    ловит не брак, а сознательный приём, и тогда её отключают целиком — что хуже.

    Срез описывается одним физическим фактом: за ним стоит РОВНЫЙ ФОН. Он виден
    с двух сторон, и обе стороны обязаны сойтись. Вдоль стены — столбец справа
    одноцветен (за срезом фон, а не продолжение чипа с его буквами). Поперёк —
    цвет справа не гаснет: на девять пикселей правее он тот же самый, тогда как
    затухание там уже заметно слабее."""
    if right + 9 >= W:
        return True
    outs = {px[right + 1, y] for y in wall}
    if len(outs) > 1:
        return False                      # справа не фон, а чип: буквы и края
    near = outs.pop()
    far = px[right + 9, wall[len(wall) // 2]]
    return near == far or dist(near, col) >= dist(far, col)


bad = 0
for name, col in CHIPS.items():
    seen = set()
    hit = {(x, y) for y in range(H) for x in range(W) if px[x, y] == col}
    for p in hit:
        if p in seen:
            continue
        comp, q = [], deque([p])
        seen.add(p)
        while q:
            x, y = q.popleft()
            comp.append((x, y))
            for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = (x + d[0], y + d[1])
                if n in hit and n not in seen:
                    seen.add(n)
                    q.append(n)
        if len(comp) < 300:
            continue                      # не пилюля, а мелочь
        xs = [c[0] for c in comp]
        ys0 = [c[1] for c in comp]
        h = max(ys0) - min(ys0) + 1
        if not (CHIP_H[0] <= h <= CHIP_H[1]):
            continue
        right = max(xs)
        width = right - min(xs) + 1
        if width >= FULL:
            print(f'ЧИП ВО ВСЮ ШИРИНУ ({name}) x={min(xs)}..{right}, y≈{min(ys0)} — '
                  f'подпись уперлась в дорожку и ушла в многоточие')
            bad += 1
        wall = sorted(c[1] for c in comp if c[0] == right)
        tall = len(wall)
        if tall >= FLAT and cut(right, wall, col):
            ys = ys0
            print(f'ОБРЕЗАН чип ({name}): правый край x={right}, '
                  f'y={min(ys)}..{max(ys)}, ровный срез {tall} px')
            bad += 1

print('обрезанных чипов:', bad)
sys.exit(1 if bad else 0)
