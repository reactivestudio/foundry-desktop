#!/usr/bin/env python3
"""Собирает docs/data-model.md в один самодостаточный HTML со встроенными картинками."""

import base64
import html
import io
import pathlib
import re

from PIL import Image

HERE = pathlib.Path(__file__).resolve().parent
MD = HERE.parent / "data-model.md"
IMG = HERE / "img"
OUT = HERE / "data-model.html"

_cache = {}


def data_uri(stem):
    if stem not in _cache:
        im = Image.open(IMG / f"{stem}.webp").convert("RGB")
        buf = io.BytesIO()
        im.save(buf, "WEBP", quality=88, method=6)
        _cache[stem] = "data:image/webp;base64," + base64.b64encode(buf.getvalue()).decode()
    return _cache[stem]


IMG_RE = re.compile(r'<img src="data-model/img/([a-z0-9-]+)\.webp"[^>]*>')


def figures(cell):
    """Вынимает вырезки из ячейки, возвращает (текст без картинок, [stem])."""
    stems = IMG_RE.findall(cell)
    text = IMG_RE.sub("", cell).replace("<br>", " ").strip()
    return text, stems


def inline(s):
    s = html.escape(s, quote=False)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
    return s


def shots(stems, cls="shot"):
    if not stems:
        return '<span class="noshot" aria-hidden="true">—</span>'
    return "".join(
        f'<button class="{cls}" type="button" data-src="{data_uri(s)}" '
        f'aria-label="Открыть кадр {s} крупно">'
        f'<img src="{data_uri(s)}" alt="Кадр: {s}" loading="lazy"></button>'
        for s in stems
    )


def render_table(rows):
    head, body = rows[0], rows[2:]

    # таблица без кадров (каталог гейтов) — обычная сетка
    if not any(IMG_RE.search(c) for r in body for c in r):
        cells = "".join(f"<th>{inline(c)}</th>" for c in head)
        out = [f'<div class="plain"><table><thead><tr>{cells}</tr></thead><tbody>']
        for r in body:
            out.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>")
        out.append("</tbody></table></div>")
        return "\n".join(out)

    computed = len(head) == 3  # «Что видно | Из чего | Кадр»
    out = ['<div class="rows">']
    for r in body:
        if computed:
            name, desc, cell = r
            example = ""
        else:
            name, example, desc, cell = r
        desc, cell_stems = figures(desc)
        _, stems = figures(cell)
        stems = cell_stems + stems
        tag = "term" if computed else "field"
        out.append(f'<div class="row"><div class="meta">')
        out.append(f'<div class="{tag}">{inline(name)}</div>')
        if example:
            out.append(f'<div class="example">{inline(example)}</div>')
        out.append(f'<p class="desc">{inline(desc)}</p></div>')
        out.append(f'<div class="frame">{shots(stems)}</div></div>')
    out.append("</div>")
    return "\n".join(out)


def build():
    lines = MD.read_text().split("\n")
    body, toc = [], []
    i, n = 0, len(lines)
    seen_title = False

    while i < n:
        ln = lines[i]

        if ln.startswith("```"):
            fence = [];  i += 1
            while i < n and not lines[i].startswith("```"):
                fence.append(lines[i]); i += 1
            i += 1
            body.append("<pre><code>" + html.escape("\n".join(fence)) + "</code></pre>")
            continue

        if ln.startswith("|"):
            rows = []
            while i < n and lines[i].startswith("|"):
                rows.append([c.strip() for c in lines[i].strip().strip("|").split("|")])
                i += 1
            body.append(render_table(rows))
            continue

        if ln.startswith("# "):
            t = ln[2:].strip()
            if not seen_title:
                seen_title = True
                body.append(f'<h1 class="doc-title">{inline(t)}</h1>')
            else:
                m = re.match(r"(\d+)\.\s+(.*)", t)
                num, rest = (m.group(1), m.group(2)) if m else ("", t)
                sid = f"s{num or len(toc)}"
                toc.append((num, rest, sid))
                body.append(
                    f'<section id="{sid}"><h2><span class="num">{num}</span>'
                    f'<span>{inline(rest)}</span></h2>'
                )
            i += 1
            continue

        if ln.startswith("## "):
            body.append(f"<h3>{inline(ln[3:].strip())}</h3>")
            i += 1
            continue

        if ln.strip() == "---":
            i += 1
            continue

        if IMG_RE.fullmatch(ln.strip()):
            body.append(f'<div class="frame wide">{shots(IMG_RE.findall(ln))}</div>')
            i += 1
            continue

        if re.match(r"^\s*[-\d]", ln) and ln.strip():
            ordered = bool(re.match(r"^\d+\.", ln.strip()))
            items, cur = [], []
            while i < n and (lines[i].strip() or (cur and lines[i + 1 : i + 2] and lines[i + 1].startswith("  "))):
                s = lines[i]
                if not s.strip():
                    i += 1; continue
                m = re.match(r"^(?:[-*]|\d+\.)\s+(.*)", s.strip())
                if m:
                    if cur: items.append(cur)
                    cur = [m.group(1)]
                elif s.startswith("  ") and cur:
                    cur.append(s.strip())
                else:
                    break
                i += 1
            if cur: items.append(cur)
            tag = "ol" if ordered else "ul"
            html_items = []
            for it in items:
                txt = " ".join(it)
                txt, stems = figures(txt)
                html_items.append(f"<li>{inline(txt)}" + (f'<div class="frame">{shots(stems)}</div>' if stems else "") + "</li>")
            body.append(f"<{tag}>" + "".join(html_items) + f"</{tag}>")
            continue

        if ln.strip():
            para = [ln.strip()]
            i += 1
            while i < n and lines[i].strip() and not lines[i].startswith(("|", "#", "-", "```")) and lines[i].strip() != "---":
                para.append(lines[i].strip()); i += 1
            txt = " ".join(para)
            txt, stems = figures(txt)
            if txt:
                body.append(f"<p>{inline(txt)}</p>")
            if stems:
                body.append(f'<div class="frame wide">{shots(stems)}</div>')
            continue

        i += 1

    # закрыть секции
    out = "\n".join(body).replace("<section id=", "</section><section id=", 1) if False else "\n".join(body)
    out = re.sub(r'(<section id="s\d+">)', r"</section>\1", out)
    out = out.replace("</section>", "", 1) + "</section>"
    # слитный список: markdown разрывает нумерацию картинкой внутри пункта
    out = re.sub(r"</(ol|ul)>\s*<\1>", "", out)

    nav = "".join(
        f'<a href="#{sid}"><span class="num">{num}</span>{html.escape(rest)}</a>'
        for num, rest, sid in toc
    )
    return TEMPLATE.replace("{{NAV}}", nav).replace("{{BODY}}", out)


TEMPLATE = r"""<title>Модель данных наблюдаемой системы</title>
<style>
:root{
  --base:#FBFAF7; --plate:#FFFFFF; --sunk:#F3F1EC; --rule:#E4E0D6;
  --ink:#191720; --ink-2:#5F5B54; --ink-3:#8C877D;
  --amber:#B26A00; --amber-chip:#FFB020; --shot-bg:#0B0910;
  --add:#7A5C12;
}
@media (prefers-color-scheme:dark){:root{
  --base:#05030D; --plate:#141417; --sunk:#0D0B14; --rule:#24242A;
  --ink:#E9E6E0; --ink-2:#9C978D; --ink-3:#6E6A63;
  --amber:#FFB020; --amber-chip:#FFB020; --shot-bg:#0B0910;
  --add:#C9A34E;
}}
:root[data-theme=light]{
  --base:#FBFAF7; --plate:#FFFFFF; --sunk:#F3F1EC; --rule:#E4E0D6;
  --ink:#191720; --ink-2:#5F5B54; --ink-3:#8C877D;
  --amber:#B26A00; --add:#7A5C12;
}
:root[data-theme=dark]{
  --base:#05030D; --plate:#141417; --sunk:#0D0B14; --rule:#24242A;
  --ink:#E9E6E0; --ink-2:#9C978D; --ink-3:#6E6A63;
  --amber:#FFB020; --add:#C9A34E;
}
*{box-sizing:border-box}
body{
  margin:0; background:var(--base); color:var(--ink);
  font:400 16px/1.6 -apple-system,BlinkMacSystemFont,"SF Pro Text","Segoe UI",Roboto,sans-serif;
  -webkit-font-smoothing:antialiased;
}
code,pre,.example,.field,.num{font-family:ui-monospace,"SF Mono",SFMono-Regular,Menlo,Consolas,monospace}

.wrap{display:grid; grid-template-columns:230px minmax(0,1fr); gap:0; max-width:1360px; margin:0 auto}

nav{
  position:sticky; top:0; align-self:start; height:100vh; overflow-y:auto;
  padding:40px 20px 40px 28px; border-right:1px solid var(--rule);
  display:flex; flex-direction:column; gap:1px;
}
nav .cap{
  font-size:11px; letter-spacing:.14em; text-transform:uppercase; color:var(--ink-3);
  margin-bottom:14px;
}
nav a{
  display:flex; gap:10px; align-items:baseline; text-decoration:none; color:var(--ink-2);
  font-size:13.5px; line-height:1.35; padding:5px 8px; border-radius:5px;
}
nav a:hover{color:var(--ink); background:var(--sunk)}
nav a .num{font-size:11px; color:var(--ink-3); min-width:15px; text-align:right}
nav a:hover .num,nav a.on .num{color:var(--amber)}
nav a.on{color:var(--ink); background:var(--sunk)}
nav a:focus-visible,.shot:focus-visible{outline:2px solid var(--amber); outline-offset:2px}

main{padding:40px 44px 140px; min-width:0}

.doc-title{
  font-size:38px; line-height:1.1; letter-spacing:-.022em; font-weight:700;
  margin:0 0 6px; text-wrap:balance;
}
h2{
  display:flex; gap:14px; align-items:baseline; margin:0 0 22px;
  font-size:23px; line-height:1.2; letter-spacing:-.018em; font-weight:650;
}
h2 .num{
  font-size:12px; font-weight:500; color:var(--amber);
  border:1px solid var(--rule); border-radius:4px; padding:3px 7px;
}
h3{font-size:13px; letter-spacing:.12em; text-transform:uppercase; color:var(--ink-3); font-weight:600; margin:34px 0 12px}
section{padding:34px 0; border-top:1px solid var(--rule)}
p{margin:0 0 14px; max-width:68ch; color:var(--ink-2)}
main>p:first-of-type{color:var(--ink-2)}
strong{color:var(--ink); font-weight:600}
code{
  font-size:.885em; background:var(--sunk); border:1px solid var(--rule);
  border-radius:4px; padding:1px 5px; color:var(--ink);
}
pre{
  background:var(--sunk); border:1px solid var(--rule); border-radius:8px;
  padding:16px 18px; overflow-x:auto; margin:0 0 18px;
}
pre code{background:none; border:0; padding:0; font-size:13px; line-height:1.65; color:var(--ink-2)}
ul,ol{margin:0 0 16px; padding-left:22px; max-width:68ch; color:var(--ink-2)}
li{margin-bottom:7px}
li::marker{color:var(--ink-3)}

/* строки полей */
.rows{border-top:1px solid var(--rule); margin:6px 0 8px}
.row{
  display:grid; grid-template-columns:minmax(0,1fr) 440px; gap:28px;
  align-items:start; padding:16px 0; border-bottom:1px solid var(--rule);
}
.row:hover{background:color-mix(in oklab,var(--sunk) 60%,transparent)}
.meta{min-width:0}
.field{
  font-size:14px; font-weight:600; color:var(--ink); letter-spacing:-.01em;
  word-break:break-word;
}
.term{font-size:15px; font-weight:600; color:var(--ink); letter-spacing:-.01em}
.example{
  font-size:12.5px; color:var(--amber); margin-top:4px; word-break:break-word;
  font-variant-numeric:tabular-nums;
}
.desc{margin:7px 0 0; font-size:14.5px; line-height:1.55; color:var(--ink-2); max-width:60ch}
.desc code{font-size:.9em}

.plain{overflow-x:auto; margin:2px 0 22px; max-width:1000px}
.plain table{border-collapse:collapse; width:100%; min-width:660px; font-size:14.5px}
.plain tr td:first-child{white-space:nowrap; color:var(--ink)}
.plain tr td:not(:first-child){min-width:180px}
.plain th{
  text-align:left; font-size:11.5px; letter-spacing:.11em; text-transform:uppercase;
  color:var(--ink-3); font-weight:600; padding:0 16px 8px 0; border-bottom:1px solid var(--rule);
  white-space:nowrap;
}
.plain td{padding:11px 16px 11px 0; border-bottom:1px solid var(--rule); color:var(--ink-2); vertical-align:top}


.frame{display:flex; flex-direction:column; gap:8px}
.frame.wide{margin:4px 0 22px; max-width:760px}
.shot{
  display:block; padding:0; border:1px solid var(--rule); border-radius:8px;
  background:var(--shot-bg); overflow:hidden; cursor:zoom-in; width:100%;
  transition:border-color .14s ease, transform .14s ease;
}
.shot:hover{border-color:var(--amber); transform:translateY(-1px); transition-duration:.7s}
.shot img{display:block; width:100%; height:auto}
.noshot{color:var(--ink-3); font-size:14px; padding-top:2px}

/* лупа */
dialog{
  border:0; padding:0; background:none; max-width:96vw; max-height:96vh;
}
dialog::backdrop{background:rgba(5,3,13,.86)}
dialog img{
  display:block; max-width:96vw; max-height:96vh; width:auto; border-radius:10px;
  border:1px solid var(--rule); background:var(--shot-bg);
}

@media (max-width:1080px){
  .wrap{grid-template-columns:1fr}
  nav{position:static; height:auto; border-right:0; border-bottom:1px solid var(--rule);
       flex-direction:row; flex-wrap:wrap; gap:4px; padding:20px}
  main{padding:26px 22px 90px}
  .row{grid-template-columns:1fr; gap:12px}
  .frame{max-width:560px}
}
@media (prefers-reduced-motion:reduce){*{transition:none!important}}
</style>

<div class="wrap">
  <nav aria-label="Разделы">
    <div class="cap">Разделы</div>
    {{NAV}}
  </nav>
  <main>{{BODY}}</main>
</div>

<dialog id="lb"><img alt=""></dialog>
<script>
const lb=document.getElementById('lb'), lbi=lb.querySelector('img');
document.addEventListener('click',e=>{
  const b=e.target.closest('.shot');
  if(b){ lbi.src=b.dataset.src; lbi.alt=b.querySelector('img').alt; lb.showModal(); return; }
  if(e.target===lb||e.target===lbi) lb.close();
});
const links=[...document.querySelectorAll('nav a')];
const io=new IntersectionObserver(es=>{
  es.forEach(en=>{
    if(!en.isIntersecting) return;
    links.forEach(a=>a.classList.toggle('on', a.getAttribute('href')==='#'+en.target.id));
  });
},{rootMargin:'-15% 0px -75% 0px'});
document.querySelectorAll('section').forEach(s=>io.observe(s));
</script>
"""

if __name__ == "__main__":
    OUT.write_text(build())
    print("готово:", OUT, round(OUT.stat().st_size / 1024 / 1024, 2), "MB")
