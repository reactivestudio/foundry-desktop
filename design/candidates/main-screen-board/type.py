# -*- coding: utf-8 -*-
"""Кегли и интерлиньяжи — ПО ТАБЛИЦЕ КАНОНА, а не по своей таблице рядом.

    python3 design/candidates/main-screen-board/type.py <собранный .html>

Интерлиньяж, заданный множителем, даёт у каждого кегля своё дробное число:
11 px жили на восьми разных интерлиньяжах сразу (11, 14, 15.4, 15.95, 16, 17,
17.05, 18), и ни один из них никто не выбирал — их выбрало наследование.
Разнобой не виден на отдельной надписи и виден на экране целиком: строки
соседних блоков перестают попадать в одну сетку.

Первая починка свела экран к пяти парам — и была ошибкой того же рода:
пары придумал автор, а таблица есть в каноне и в нём же записано, что
«новый размер добавляется только через пересмотр таблицы, не на месте».
Из тринадцати пар на экране в канон попадало шесть. Здесь стоит РОВНО
таблица канона (docs/design/04-typography.md, часть 3.2), список пар
переписан из неё; добавить пару можно только правкой канона.

Общей сетки базовых линий канон не требует и прямо от неё отказывается
вслед за Нозиком: «общая базовая сетка для текста 13/18 и кода 12/20
математически недостижима — и не нужна; достаточно кратных интерлиньяжей
и согласованных высот». Поэтому проверяется таблица, а не модуль.

Исключения названы поимённо и обязаны срабатывать — мёртвое исключение
роняет сборку так же, как нарушение.
"""
import json, pathlib, re, subprocess, sys, tempfile

CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'

# Таблица канона, часть 3.2: стиль → (кегль, интерлиньяж).
CANON = {
    'display':  (26, 32),
    'title':    (20, 25),
    'heading':  (16, 21),
    'body':     (13, 18),
    'body-em':  (13, 18),
    'caption':  (11, 14),
    'caption2': (10, 13),
    'label':    (11, 13),
    'mono':     (12, 20),
    'mono-s':   (10, 14),
}
PAIRS = sorted(set(CANON.values()))

# Свой интерлиньяж — и вот почему. Ключ: селектор, значение: (интерлиньяж, why)
EXEMPT = {
    'code': (18, 'моноширинная вставка ВНУТРИ прозы держит интерлиньяж прозы: '
                 'собственные 20 рвали бы строку абзаца, в котором она стоит, '
                 'и абзац шёл бы рваной лесенкой. Блочный код (.log) — 12/20 '
                 'по канону, как и положено коду'),
}

PROBE = r"""
<script>
window.addEventListener('load', () => {
  const o = [];
  document.querySelectorAll('.win *').forEach(el => {
    const own = [...el.childNodes].filter(n => n.nodeType === 3 && n.textContent.trim())
                .map(n => n.textContent.trim()).join(' ');
    if (!own) return;
    const cs = getComputedStyle(el), r = el.getBoundingClientRect();
    if (!r.width || !r.height) return;
    if (cs.visibility === 'hidden' || +cs.opacity === 0) return;
    o.push({s: Math.round(parseFloat(cs.fontSize) * 100) / 100,
            l: Math.round(parseFloat(cs.lineHeight) * 100) / 100,
            sel: (el.className && typeof el.className === 'string'
                  ? '.' + el.className.trim().split(/\s+/).join('.')
                  : el.tagName.toLowerCase()),
            t: own.slice(0, 24)});
  });
  const p = document.createElement('pre'); p.id = 'TYPE';
  p.textContent = JSON.stringify(o); document.body.appendChild(p);
});
</script>
"""


def measure(html):
    tmp = pathlib.Path(tempfile.gettempdir()) / 'main-screen-board' / '_type.html'
    tmp.parent.mkdir(exist_ok=True)
    tmp.write_text(pathlib.Path(html).read_text() + PROBE)
    dom = subprocess.run([CHROME, '--headless=new', '--disable-gpu',
                          '--virtual-time-budget=5000', '--window-size=1740,13043',
                          '--dump-dom', f'file://{tmp}?bare'],
                         capture_output=True, text=True).stdout
    m = re.search(r'<pre id="TYPE">(.*?)</pre>', dom, re.S)
    if not m:
        raise SystemExit('проба не отработала — Chrome не отдал типографику')
    return json.loads(m.group(1).replace('&quot;', '"').replace('&amp;', '&')
                      .replace('&lt;', '<').replace('&gt;', '>'))


def main(html):
    rows = measure(html)
    bad, used = set(), set()
    for it in rows:
        size, lead, sel = it['s'], it['l'], it['sel']
        hit = next((k for k in EXEMPT if all(p in sel for p in k.split('.') if p)), None)
        if hit and abs(lead - EXEMPT[hit][0]) < 0.51:
            used.add(hit)
            continue
        near = [p for p in PAIRS if p[0] == size]
        if not near:
            bad.add(f'кегль {size} — не из таблицы канона '
                    f'{sorted({p[0] for p in PAIRS})} ({sel} «{it["t"]}»)')
            continue
        if not any(abs(lead - p[1]) < 0.51 for p in near):
            bad.add(f'{size}/{lead} — нет такой пары в таблице канона; '
                    f'для кегля {size} канон знает {[p[1] for p in near]} '
                    f'({sel} «{it["t"]}»)')
    dead = [k for k in EXEMPT if k not in used]
    for k in dead:
        bad.add(f'исключение {k} не сработало ни разу, значит оно врёт')
    for line in sorted(bad):
        print('КЕГЛЬ:', line)
    print(f'надписей промерено: {len(rows)} / вне таблицы: {len(bad)}'
          f' / названных исключений: {len(used)}')
    return 1 if bad else 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1]))
