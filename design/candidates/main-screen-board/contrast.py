# -*- coding: utf-8 -*-
"""Контраст каждой надписи — числом, а не глазом на своём мониторе.

    python3 design/candidates/main-screen-board/contrast.py <собранный .html>

Пункт «проверить на другой яркости дисплея» глазом не проверяется вовсе:
на тусклом экране падает не контраст (он у пары цветов один и тот же), а запас
над порогом — и надпись, стоявшая на 4.3:1, перестаёт читаться первой. Значит,
мерить надо не «видно ли мне», а отношение яркостей каждой пары «текст на своём
фоне», и делать это на всех кадрах сразу.

Chrome отдаёт вычисленные стили; фон собирается вверх по предкам с наложением
альфы, потому что подложки в теме полупрозрачные и «background-color» самого
элемента почти всегда прозрачен. Порог — WCAG: 4.5:1 для текста и 3:1 для
крупного (24 px или 18.7 px полужирным).

ИСКЛЮЧЕНИЯ НАЗВАНЫ ПОИМЁННО и лежат в EXEMPT: молчаливого послабления нет.
Всё, что ниже порога и не названо, роняет сборку.
"""
import json, pathlib, re, subprocess, sys, tempfile

CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'

# Ниже порога — и это осознанно. Ключ — селектор, значение — почему.
# Список обязан быть ЖИВЫМ: исключение, которое ни разу не сработало, роняет
# сборку наравне с нарушением. Мёртвая строка тут — то же рукописное враньё
# рядом с вычислимым, что и высота кадра, записанная от руки: она утверждает
# про экран то, чего на экране нет.
EXEMPT = {
    # Выключенная кнопка обязана быть тише работающей: контраст здесь и
    # кодирует недоступность. WCAG выводит неактивные элементы из-под
    # требования ровно по этой причине. 4.18:1 — прочесть, чего нельзя, всё
    # ещё можно.
    '.btn.primary.dis': 'выключенная кнопка — контраст кодирует недоступность',
}

PROBE = r"""
<script>
window.addEventListener('load', () => {
  const px = s => parseFloat(s) || 0;
  const rgba = s => {
    const m = String(s).match(/[\d.]+/g);
    if (!m) return null;
    return [+m[0], +m[1], +m[2], m.length > 3 ? +m[3] : 1];
  };
  const over = (fg, bg) => {            // наложение fg на непрозрачный bg
    const a = fg[3];
    return [fg[0]*a + bg[0]*(1-a), fg[1]*a + bg[1]*(1-a), fg[2]*a + bg[2]*(1-a), 1];
  };
  const bgOf = el => {                  // фон собирается вверх по предкам
    const stack = [];
    for (let n = el; n; n = n.parentElement) {
      const c = rgba(getComputedStyle(n).backgroundColor);
      if (c && c[3] > 0) { stack.push(c); if (c[3] === 1) break; }
    }
    let out = [5, 3, 13, 1];            // подложка страницы
    for (let i = stack.length - 1; i >= 0; i--) out = over(stack[i], out);
    return out;
  };
  const sel = el => {
    let s = el.tagName.toLowerCase();
    if (el.className && typeof el.className === 'string')
      s += '.' + el.className.trim().split(/\s+/).join('.');
    const p = el.parentElement;
    if (p && p.className && typeof p.className === 'string')
      s = p.className.trim().split(/\s+/).map(c => '.' + c).join('') + ' ' + s;
    return s;
  };
  const out = [];
  document.querySelectorAll('.win *').forEach(el => {
    const own = [...el.childNodes]
      .filter(n => n.nodeType === 3 && n.textContent.trim())
      .map(n => n.textContent.trim()).join(' ');
    if (!own) return;
    const cs = getComputedStyle(el), r = el.getBoundingClientRect();
    if (!r.width || !r.height) return;
    if (cs.visibility === 'hidden' || +cs.opacity === 0) return;
    const fg = rgba(cs.color);
    if (!fg) return;
    const bg = bgOf(el);
    out.push({
      sel: sel(el), text: own.slice(0, 40),
      fg: over(fg, bg).slice(0, 3).map(v => +v.toFixed(1)),
      bg: bg.slice(0, 3).map(v => +v.toFixed(1)),
      size: px(cs.fontSize), weight: +cs.fontWeight || 400,
      win: (el.closest('.win') || {}).className || '',
    });
  });
  const p = document.createElement('pre'); p.id = 'CONTRAST';
  p.textContent = JSON.stringify(out); document.body.appendChild(p);
});
</script>
"""


def lum(c):
    def ch(v):
        v /= 255
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return 0.2126 * ch(c[0]) + 0.7152 * ch(c[1]) + 0.0722 * ch(c[2])


def ratio(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def need(size, weight):
    """Крупным считается 24 px или 18.7 px полужирным — тогда порог 3:1."""
    return 3.0 if (size >= 24 or (size >= 18.66 and weight >= 700)) else 4.5


def measure(html):
    src = pathlib.Path(html).read_text()
    tmp = pathlib.Path(tempfile.gettempdir()) / 'main-screen-board' / '_contrast.html'
    tmp.parent.mkdir(exist_ok=True)
    tmp.write_text(src + PROBE)
    dom = subprocess.run([CHROME, '--headless=new', '--disable-gpu',
                          '--virtual-time-budget=5000', '--window-size=1740,12000',
                          '--dump-dom', f'file://{tmp}?bare'],
                         capture_output=True, text=True).stdout
    m = re.search(r'<pre id="CONTRAST">(.*?)</pre>', dom, re.S)
    if not m:
        raise SystemExit('проба не отработала — Chrome не отдал стили')
    return json.loads(m.group(1).replace('&quot;', '"').replace('&amp;', '&')
                      .replace('&lt;', '<').replace('&gt;', '>'))


USED = set()

def exempt_of(item):
    for key, why in EXEMPT.items():
        if all(part in item['sel'] for part in key.split()):
            USED.add(key)
            return why
    return None


def main(html):
    rows = measure(html)
    bad, spared, worst, graded = [], 0, {}, []
    for it in rows:
        r = ratio(it['fg'], it['bg'])
        mode = ('увеличенный контраст' if ' hc' in it['win'] + ' '
                else 'уменьшенная прозрачность' if ' rt' in it['win'] + ' '
                else 'обычный')
        graded.append((r, it['sel'], it['text'], mode))
        cur = worst.get(mode)
        if cur is None or r < cur[0]:
            worst[mode] = (r, it['sel'], it['text'])
        if r + 0.005 >= need(it['size'], it['weight']):
            continue
        if exempt_of(it):
            spared += 1
            continue
        bad.append(f'{r:.2f}:1 при пороге {need(it["size"], it["weight"])} — '
                   f'{it["sel"]} «{it["text"]}»')
    for line in sorted(set(bad)):
        print('КОНТРАСТ:', line)
    for mode in ('обычный', 'увеличенный контраст', 'уменьшенная прозрачность'):
        if mode in worst:
            r, s, t = worst[mode]
            print(f'  запас, {mode}: худшая пара {r:.2f}:1 — {s} «{t}»')
    # Пол по режимам. Настройка «Увеличить контраст» обязана не просто
    # «добавить кромок»: у неё есть измеримое обещание — ни одна пара на
    # экране не опускается ниже AAA. Обещание, которое нечем проверить,
    # через месяц перестанет выполняться молча. Смотрим ВСЕ пары режима,
    # а не одну худшую: худшая может оказаться названным исключением
    # и прикрыть собой вторую.
    for mode, floor in (('обычный', 4.5), ('увеличенный контраст', 7.0)):
        low = sorted({(round(r, 2), sl, tx) for r, sl, tx, m in graded
                      if m == mode and r + 0.005 < floor and not exempt_of({'sel': sl})})
        for r, sl, tx in low[:6]:
            bad.append(f'пол режима «{mode}» — {floor}:1, а пара {r}:1 ({sl} «{tx}»)')
            print('КОНТРАСТ:', bad[-1])
        if len(low) > 6:
            print(f'КОНТРАСТ: …и ещё {len(low) - 6} пар ниже пола режима «{mode}»')
    dead = [k for k in EXEMPT if k not in USED]
    for k in dead:
        print('КОНТРАСТ: исключение', k, '— не сработало ни разу, значит оно врёт')
    print(f'надписей промерено: {len(rows)} / ниже порога: {len(set(bad))}'
          f' / названных исключений: {spared} / мёртвых исключений: {len(dead)}')
    return 1 if bad or dead else 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1]))
