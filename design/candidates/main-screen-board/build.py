# -*- coding: utf-8 -*-
"""Сборка кандидата `main-screen-board.html` и его проверка.

    python3 design/candidates/main-screen-board/build.py

Кадры собираются генератором `gen.py` из ОДНОЙ модели данных, вставляются
в макет `docs/design/mockups/foundry-mockups.html` вместе со слоем
переопределений `canon-layer.html`, рендерятся безголовым Chrome и проверяются
двумя инструментами вместо глаза: `clip.py` ищет обрезанные подписи чипов
по геометрии связных областей, `flags.py` снимает у Chrome настоящие
`getBoundingClientRect` и сверяет флаги, дорожки, зазоры и якорь «Готово»,
`contrast.py` считает отношение яркостей каждой пары «текст на своём фоне» —
это и есть проверка на другой яркости дисплея, глазом не проверяемая вовсе, —
а `type.py` сверяет кегль и интерлиньяж каждой надписи с таблицей.
"""
import pathlib, re, subprocess, sys, tempfile

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = HERE.parent / 'main-screen-board.html'
# Промежуточные файлы — во временный каталог: в репозитории лежат только
# исходники сборки и её результат.
TMP = pathlib.Path(tempfile.gettempdir()) / 'main-screen-board'
TMP.mkdir(exist_ok=True)
PNG = TMP / 'main-screen-board.png'
# Высота кадра НЕ пишется рукой. Записанная рукой, она отстаёт от вёрстки
# молча: страница выросла до 8480, рендер остался 8300 — и нижние 180 px
# последнего кадра (панель действий инспектора) просто не попадали в снимок,
# а проверки ищут обрез чипов, не обрез страницы. Высоту спрашиваем у Chrome.
W, H = 1740, 8300
CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
HEIGHT_PROBE = ('<script>window.addEventListener("load",()=>{const p=document.createElement("pre");'
                'p.id="H";p.textContent=document.documentElement.scrollHeight;'
                'document.body.appendChild(p);});</script>')


def page_height(html_path):
    probe = TMP / '_height.html'
    src = html_path.read_text()
    probe.write_text(src.replace('</body>', HEIGHT_PROBE + '</body>')
                     if '</body>' in src else src + HEIGHT_PROBE)
    dom = subprocess.run([CHROME, '--headless=new', '--disable-gpu',
                          '--virtual-time-budget=5000', f'--window-size={W},{H}',
                          '--dump-dom', f'file://{probe}?bare'],
                         capture_output=True, text=True).stdout
    m = re.search(r'<pre id="H">(\d+)</pre>', dom)
    return int(m.group(1)) if m else H

(TMP / '_sprite.html').write_text((HERE / '_sprite.html').read_text())
subprocess.run([sys.executable, str(HERE / 'gen.py'), str(TMP)], check=True)

src = (ROOT / 'docs/design/mockups/foundry-mockups.html').read_text()
anchor = '<div class="wrap">'
prefix = src[:src.find(anchor) + len(anchor)]
OUT.write_text(prefix
               + (HERE / 'canon-layer.html').read_text()
               + (TMP / 'part-canon.html').read_text()
               + '\n</div>\n</div>\n')
print('собрано:', OUT)

if not pathlib.Path(CHROME).exists():
    print('Chrome не найден — рендер и проверка пропущены')
    raise SystemExit(0)

H = page_height(OUT)
# Высота есть и во фронтматтере разбора — и она такая же вычислимая, как
# высота рендера. Записанная рукой, она отстанет от вёрстки ровно так же
# и ровно так же молча, поэтому её проставляет сборка.
MD = OUT.with_suffix('.md')
if MD.exists():
    md = MD.read_text()
    fixed = re.sub(r'(?m)^height: \d+$', f'height: {H}', md, count=1)
    if fixed != md:
        MD.write_text(fixed)
        print('высота в разборе:', H)
subprocess.run([CHROME, '--headless=new', '--disable-gpu', '--hide-scrollbars',
                '--virtual-time-budget=5000', f'--window-size={W},{H}',
                f'--screenshot={PNG}', f'file://{OUT}?bare'], capture_output=True)
print(f'отрисовано: {PNG} ({W}×{H})')
rc = subprocess.run([sys.executable, str(HERE / 'clip.py'), str(PNG)]).returncode
rc |= subprocess.run([sys.executable, str(HERE / 'flags.py'), str(OUT)]).returncode
rc |= subprocess.run([sys.executable, str(HERE / 'contrast.py'), str(OUT)]).returncode
rc |= subprocess.run([sys.executable, str(HERE / 'type.py'), str(OUT)]).returncode
raise SystemExit(rc)
