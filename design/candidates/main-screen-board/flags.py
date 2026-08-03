# -*- coding: utf-8 -*-
"""Проверка флагов и дорожек по РЕАЛЬНОЙ геометрии, а не по глазу.

    python3 design/candidates/main-screen-board/flags.py <собранный .html>

Chrome прогоняет страницу и отдаёт `getBoundingClientRect` каждого элемента,
который обязан стоять на общей вертикали. Проверяются шесть законов:

  1. Флаг канваса один: вкладки пайплайнов, строка среза, первая колонка
     и кромки её карточек стоят на одной левой линии.
  2. Внутри колонки — один флаг: шапка и кромки карточек на кромке колонки,
     заголовок и чип отступают ровно на поле карточки (вложенность, а не
     третья вертикаль). Чип, стоявший по центру, ловится именно здесь.
  3. Дорожка — константа на любом пайплайне: тот же change того же размера
     и на трёх стадиях, и на десяти.
  4. «Готово» — якорь: на доске, которая едет вбок, её правый край совпадает
     с правым полем канваса. Короткий пайплайн ничего не растягивает.
  5. Видимая часть доски равна девяти дорожкам со швом: плиту меряем
     у Chrome, а не выводим на бумаге — арифметика ошибается молча, и доска
     на 2 px вылезает за собственное поле.
  6. Порядок величин: поле карточки < зазор между карточками < зазор между
     колонками < поле плиты < шов перед «Готово».
  7. Поле плиты канваса больше зазора между её колонками: девять дорожек
     обязаны читаться группой ВНУТРИ плиты, а при 16 = 16 крайняя стояла
     от кромки ровно так же, как от соседки.
  8. Каждое поле карточки МЕНЬШЕ зазора между карточками: поле, равное рву
     вокруг объекта, растворяет объект в однородной сетке. Отсюда же и отказ
     разводить поля по сторонам: свободных значений шкалы между 4 и 12 нет.
  9. Плавающий инспектор той ширины, из которой посчитан минимум окна.
     Разбор считает по этому числу, сколько дорожек оверлей закрыл бы на
     минимуме, — и разошёлся бы с вёрсткой молча, правь его хоть где.

Ошибка печатается в пикселях и роняет сборку — числа спорить не умеют.
"""
import json, pathlib, re, subprocess, sys, tempfile

CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
LANE, CARD_PAD, CARD_GAP, COL_GAP, BOARD_PAD, SEAM = 124, 8, 12, 16, 24, 52
# Ширина видимой части доски — не арифметика на бумаге, а замер плиты.
# Ровно на этом ловится расхождение: генератор считал 1298 и был уверен,
# что девять дорожек садятся впритык, а плита отдавала 1296 — доска на
# 2 px вылезала за собственное правое поле, чего глаз не видит вовсе.
# Восемь стадий, пустая дорожка шва и «Готово» — девять дорожек и девять
# зазоров; видимый шов SEAM включает в себя два из этих зазоров.
PLATE = 1280
INSP_W = 440       # ширина плавающего инспектора (правка 65 слоя)
assert PLATE == 9 * LANE + (SEAM - 2 * COL_GAP) + 9 * COL_GAP

PROBE = r"""
<script>
window.addEventListener('load', () => {
  const L = e => +e.getBoundingClientRect().x.toFixed(1);
  const R = e => +(e.getBoundingClientRect().x + e.getBoundingClientRect().width).toFixed(1);
  const out = { boards: [] };
  document.querySelectorAll('.board').forEach(b => {
    const cs = getComputedStyle(b), box = b.getBoundingClientRect();
    const cols = [...b.querySelectorAll('.kb-col')].map(c => {
      const head = c.querySelector('.kb-col-head');
      const cards = [...c.querySelectorAll('.kb-card')];
      return {
        done: c.classList.contains('done'),
        sticky: getComputedStyle(c).position === 'sticky',
        left: L(c), right: R(c), width: +c.getBoundingClientRect().width.toFixed(1),
        head: head ? +(L(head) - L(c)).toFixed(1) : null,
        cards: [...new Set(cards.map(k => +(L(k) - L(c)).toFixed(1)))],
        titles: [...new Set(cards.map(k => k.querySelector('.kc-title'))
                  .filter(Boolean).map(t => +(L(t) - L(t.closest('.kb-card'))).toFixed(1)))],
        chips: [...new Set(cards.map(k => k.querySelector('.st')).filter(Boolean)
                  .map(s => +(L(s) - L(s.closest('.kb-card'))).toFixed(1)))],
        stack: [...new Set(cards.slice(1).map((k, i) =>
                  +(k.getBoundingClientRect().y - R2(cards[i])).toFixed(1)))],
        pads: [...new Set(cards.map(k => {
                  const s = getComputedStyle(k);
                  return [s.paddingTop, s.paddingBottom, s.paddingLeft].join('/');
               }))],
      };
    });
    function R2(e) { const r = e.getBoundingClientRect(); return r.y + r.height; }
    out.boards.push({
      inner: +(box.width - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight)).toFixed(1),
      narrow: !!b.closest('.win.min'),
      left: +(box.x + parseFloat(cs.paddingLeft)).toFixed(1),
      right: +(box.x + box.width - parseFloat(cs.paddingRight)).toFixed(1),
      scrolls: b.scrollWidth > Math.ceil(box.width),
      cols: cols,
    });
  });
  out.plates = [...new Set([...document.querySelectorAll('.pane.list')].map(e => {
                 const s = getComputedStyle(e);
                 return s.paddingLeft + '/' + s.paddingRight; }))];
  out.insp = [...new Set([...document.querySelectorAll('.overlay-insp')]
              .filter(e => !e.closest('.win.min') && !e.closest('.win.rt'))
              .map(e => Math.round(e.getBoundingClientRect().width)))];
  out.bars = [...new Set([...document.querySelectorAll('.pipe-bar, .slice-note')]
              .map(e => +(e.getBoundingClientRect().x + parseFloat(getComputedStyle(e).paddingLeft)).toFixed(1)))];
  const p = document.createElement('pre'); p.id = 'PROBE';
  p.textContent = JSON.stringify(out); document.body.appendChild(p);
});
</script>
"""


def measure(html):
    src = pathlib.Path(html).read_text()
    tmp = pathlib.Path(tempfile.gettempdir()) / 'main-screen-board' / '_flags.html'
    tmp.parent.mkdir(exist_ok=True)
    tmp.write_text(src.replace('</body>', PROBE + '</body>') if '</body>' in src else src + PROBE)
    dom = subprocess.run([CHROME, '--headless=new', '--disable-gpu', '--virtual-time-budget=5000',
                          '--window-size=1740,8300', '--dump-dom', f'file://{tmp}?bare'],
                         capture_output=True, text=True).stdout
    m = re.search(r'<pre id="PROBE">(.*?)</pre>', dom, re.S)
    if not m:
        raise SystemExit('проба не отработала — Chrome не отдал геометрию')
    return json.loads(m.group(1).replace('&quot;', '"'))


def main(html):
    d = measure(html)
    bad = []
    flag = d['boards'][0]['left']
    for i, b in enumerate(d['boards']):
        say = lambda t: bad.append(f'доска {i}: {t}')
        if not b['narrow'] and b['inner'] != PLATE:
            say(f'видимая часть доски {b["inner"]}, а девять дорожек занимают {PLATE}')
        if b['left'] != flag:
            say(f'левое поле {b["left"]}, а у первой доски {flag}')
        if b['cols'] and b['cols'][0]['left'] != flag:
            say(f'первая колонка на {b["cols"][0]["left"]}, флаг канваса {flag}')
        stages = [c for c in b['cols'] if not c['done']]
        for c in b['cols']:
            if c['width'] != LANE:
                say(f'дорожка {c["width"]}, а должна быть {LANE}')
            if c['head'] not in (0, None):
                say(f'шапка колонки отступает от кромки на {c["head"]}, а должна на 0')
            if set(c['cards']) - {0}:
                say(f'кромки карточек отступают на {sorted(set(c["cards"]))}, а должны на 0')
            if set(c['titles']) - {CARD_PAD}:
                say(f'заголовки отступают на {sorted(set(c["titles"]))}, поле карточки {CARD_PAD}')
            if set(c['chips']) - {CARD_PAD}:
                say(f'чип отступает на {sorted(set(c["chips"]))}, а заголовок на {CARD_PAD}'
                    ' — чип обязан стоять на флаге карточки')
            if set(c['stack']) - {CARD_GAP}:
                say(f'зазор между карточками {sorted(set(c["stack"]))}, а закон {CARD_GAP}')
            for p in c['pads']:
                if max(float(v.rstrip('px')) for v in p.split('/')) >= CARD_GAP:
                    say(f'поле карточки {p} не меньше зазора между карточками {CARD_GAP}')
        gaps = sorted({round(b2['left'] - a['right']) for a, b2 in zip(stages, stages[1:])})
        if gaps and gaps != [COL_GAP]:
            say(f'зазоры между стадиями {gaps}, а закон {COL_GAP}')
        done = next((c for c in b['cols'] if c['done']), None)
        if done and not done['sticky'] and stages:
            seam = round(done['left'] - stages[-1]['right'])
            if seam != SEAM:
                say(f'шов перед «Готово» {seam}, а закон {SEAM}')
        if done and b['scrolls'] and round(done['right']) != round(b['right']):
            say(f'доска едет вбок, а «Готово» кончается на {done["right"]}'
                f' вместо правого поля {b["right"]}')
    if d['bars'] not in ([flag], []):
        bad.append(f'вкладки и строка среза на {d["bars"]}, флаг канваса {flag}')
    if d['insp'] not in ([INSP_W], []):
        bad.append(f'плавающий инспектор шириной {d["insp"]}, а разбор считает по {INSP_W}')
    want = f'{BOARD_PAD}px/{BOARD_PAD}px'
    if d['plates'] not in ([want], []):
        bad.append(f'поля плиты канваса {d["plates"]}, а закон {want}')
    if not (CARD_PAD < CARD_GAP < COL_GAP < BOARD_PAD < SEAM):
        bad.append('порядок величин нарушен: '
                   f'{CARD_PAD} {CARD_GAP} {COL_GAP} {BOARD_PAD} {SEAM}')
    for line in bad:
        print('ФЛАГ:', line)
    print(f'досок проверено: {len(d["boards"])} / расхождений: {len(bad)}')
    return 1 if bad else 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1]))
