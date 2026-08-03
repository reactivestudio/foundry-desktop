# -*- coding: utf-8 -*-
"""Сборка кадров доски из ОДНОЙ модели данных.

Правило, ради которого это переписано: каждое число на экране существует
ровно в одном месте, и каждая карточка несёт ровно один чип — «чей ход».
"""
import pathlib, sys, re

SP = pathlib.Path(sys.argv[1])
NB = ' '

def nb(s):
    """Неразрывные там, где число липнет к счётному слову."""
    s = re.sub(r'(\d+)\s+(мин|ч|д|с|вопрос\w*|задач\w*|строк\w*|дней|дня|стади\w+)\b', r'\1'+NB+r'\2', s)
    s = re.sub(r'(\d+)\s+из\s+(\d+)', r'\1'+NB+'из'+NB+r'\2', s)
    # Токен, начинающийся с точки или слэша (.foundry, /wt), не имеет права
    # открывать строку: строка, начатая точкой, читается как многоточие или
    # как обрыв. Ловилось на карточке «Падение на пустом .foundry», где
    # перенос ставил «.foundry» в начало второй строки.
    s = re.sub(r'\s+(?=[./][\w-])', NB, s)
    for w in ('в','к','с','о','у','и','а','на','по','из','до','за','от','не','со','во','что','как','для','при','без','это','чем','чтобы','пока','если','или','но','же',
              'против','через','между','после','перед','вместо','ради','около','кроме','среди','сквозь','под','над','про','вокруг','вдоль','поверх'):
        s = re.sub(r'(?<![\wЀ-ӿ-])(' + w + r')\s+(?=[\wЀ-ӿ«(])', r'\1'+NB, s, flags=re.I)
    return s

# ── модель ───────────────────────────────────────────────────────────────────
# ход: wait — ваш ход, live — ход агента, stall/fail — встало, done — принят
# ОДНА ШКАЛА НА СОСТОЯНИЕ — и на янтарь, и на нейтраль.
# Все чипы «ваш ход» меряют ОДНО И ТО ЖЕ — сколько change ждёт человека.
# Стояло вперемешку: «3 вопроса» (количество) и «ждёт 12 мин» (возраст). В
# колонке, которую и правда читают вертикально — в срезе «ваш ход», — сравнивать
# было нечего: что срочнее, три вопроса или час ожидания, экран не отвечал.
# Хуже: change, сутки простоявший с тремя незаданными вопросами, назван в самом
# документе «самым дорогим простоем в продукте» — и был на доске неотличим от
# только что заданного. Число вопросов ушло в тред: оно про объём работы,
# а не про очередь. Порядок карточек в колонке — по этому же сроку, сверху
# самые давние; закрывающая проверка внизу файла роняет сборку при нарушении.
# То же самое пришлось сделать с нейтралью. Внутри «хода агента» шкалы было
# две: «пишет 20 мин» (срок) и «4 из 7» (доля). Колонка Implement оказывалась
# несравнимой сама с собой — что дольше стоит, «встало 1 ч» или «4 из 7»,
# экран не отвечал, — а проверка порядка эти колонки просто пропускала.
# Хуже другое: «7» — это атомарные задачи, второй уровень зума (они и
# появляются-то только после Plan). Доска считает change'и; доля задач на
# карточке change'а мешает два масштаба в одном чипе. Прогресс по задачам
# живёт в инспекторе, где для него есть степпер и место назвать единицу.
BOARD = [
 ('Questions', [
   ('cycle',   'Скоупы бинов Spark',             'feat/spark-scopes',      'wait', 'ждёт 26 ч'),
   ('feature', 'Нотч-хелпер',                    'feat/notch-helper',      'wait', 'ждёт 3 ч'),
   ('feature', 'Экспорт диффа в печатной палитре','feat/diff-export-light', 'wait', 'ждёт 25 мин'),
 ]),
 ('Research', [
   ('feature', 'Liquid Glass',                   'research/liquid-glass',  'live', 'идёт 18 мин'),
   ('doc',     'APCA против WCAG',               'research/apca',          'live', 'идёт 4 мин'),
 ]),
 ('Design', [
   ('doc',     'Стадии CRISPY',                  'docs/crispy-stages',     'wait', 'ждёт 1 ч'),
   ('feature', 'Пустые состояния доски',         'feat/board-empty',       'live', 'идёт 20 мин'),
   ('feature', 'Токены тёмной темы',             'feat/dark-tokens',       'wait', 'ждёт 12 мин'),
   # «На доработке» отсюда убрано: чип отвечает ровно на один вопрос — чей ход
   # и сколько это длится. Почему change вернулся на стадию назад — вопрос
   # второй, и на него отвечает инспектор, а не подпись в 110 px.
   ('doc',     'Пустая доска нового проекта',    'docs/empty-board',       'live', 'идёт 2 мин'),
 ]),
 ('Structure', [
   ('feature', 'Контекст доски',                 'feat/board-context',     'stall','встало 6 ч'),
   ('cycle',   'Хранилище инбокса',              'refactor/inbox-store',   'live', 'идёт 8 с'),
 ]),
 ('Plan', [
   ('feature', 'Слоты агентов и лимиты',         'feat/agent-slots',       'live', 'идёт 40 мин'),
 ]),
 ('Worktree', [
   ('feature', 'Инспектор по требованию',        'feat/inspector-overlay', 'live', 'идёт 12 с'),
 ]),
 ('Implement', [
   ('feature', 'Орб-лоадер',                     'feat/orb-loader',        'live', 'идёт 6 ч'),
   ('cycle',   'Тост отмены',                    'feat/undo-toast',        'stall','встало 1 ч'),
   ('feature', 'Горячие клавиши инспектора',     'feat/inspector-keys',    'live', 'идёт 8 мин'),
 ]),
 ('PR', [
   # «CI упал» стояло здесь и было последним чипом без срока. Причина отказа —
   # работа инспектора (кадр 27 её и показывает), а на доске коралл обязан
   # мериться тем же, чем меряются два других коралла: сколько уже стоит.
   ('flag',    'Контраст по APCA',               'feat/apc-contrast',      'fail', 'упало 3 ч'),
   ('feature', 'Свёртка колонки «Готово»',       'feat/done-collapse',     'wait', 'ждёт 2 ч'),
 ]),
 ('Готово', [
   ('feature', 'Онбординг',                      'feat/onboarding',        'done', 'вчера, 14:32'),
   ('doc',     'Дизайн-канон',                   'docs/design-canon',      'done', 'пт, 11:20'),
 ]),
]
DONE_TOTAL = 12          # в колонке «Готово» 12, показаны две последние

# Счётчик проекта — то же самое число, что и сумма среза: сколько change’ей
# в работе. Не «сколько всего», иначе он спорил бы с доской, где принятые
# свёрнуты в «Готово». Рукой пишутся только чужие проекты — их доску никто
# не видит и проверить нечем; своё число и «Все проекты» выводятся.
# МИР ОДИН НА ВСЕ КАДРЫ. Раньше каждый кадр считал по-своему: на одном
# «foundry-desktop 18», на другом 2, на третьем 42, и «Все проекты» гуляли
# 33 / 55 / 17. Кадры делались порознь, и каждый был прав внутри себя —
# а разворот врал. Теперь проект и его пайплайны заданы ОДИН раз, сайдбар
# на всех кадрах одинаков с точностью до выбранной строки, а доска кадра
# обязана сойтись с той клеткой этой таблицы, которую она показывает.
WORLD = {
 'foundry-desktop': {'Фича в одном сервисе': 18, 'Баг': 3, 'Инцидент': 1},
 'crispy-core':     {'Хотфикс': 2, 'Фича в нескольких сервисах': 7},
 'monorepo':        {'Фича в одном сервисе': 42},
 'memory-vault':    {'Фича в одном сервисе': 4},
 'books':           {'Фича в одном сервисе': 2},
 'дизайн-система':  {},
}
# Чей ход за невыбранной вкладкой — цвет её чипа
PIPE_MOVE = {('foundry-desktop', 'Баг'): 'wait',
             ('foundry-desktop', 'Инцидент'): 'stop',
             ('crispy-core', 'Хотфикс'): 'wait',
             ('crispy-core', 'Фича в нескольких сервисах'): 'live'}

# Порядок списка проектов ФИКСИРОВАН. Сортировка по числу переставляла строки
# на каждом кадре: выбранный проект уезжал в середину, и найти его глазами
# получалось только чтением всех подписей. Список, который не стоит на месте,
# нельзя запомнить рукой.
ORDER = ['foundry-desktop', 'crispy-core', 'monorepo', 'memory-vault',
         'books', 'дизайн-система']
assert set(ORDER) == set(WORLD)

def proj_total(name):
    """Счётчик проекта считает ПРОЕКТ, а не доску: работа за другими
    вкладками — тоже работа. Разницу между ним и суммой среза читатель
    закрывает не верой, а сложением: числа вкладок стоят на самих вкладках."""
    return sum(WORLD[name].values())

def projects(*_a, **_k):
    rows = [(n, proj_total(n)) for n in ORDER]
    return ([('Все проекты', sum(v for _, v in rows), 'stack')]
            + [(n, v, 'repo') for n, v in rows])
# Стадии — по docs/reference/ui/domain-model.md. Пайплайны РАЗНОЙ длины,
# и это значимая информация, а не дефект вёрстки.
STAGES = {
 'Фича в одном сервисе':   ['Questions','Research','Design','Structure','Plan','Worktree','Implement','PR'],
 'Фича в нескольких сервисах':['Questions','Research','Design','Contracts','Structure','Plan','Worktree','Implement','Integration','PR'],
 'Баг':                  ['Repro','Diagnose','Fix','Test','PR'],
 'Хотфикс':              ['Repro','Fix','Ship'],
 'Инцидент':             ['Triage','Mitigate','RCA','Postmortem'],
}
PIPES = list(STAGES)
MAIN = PIPES[0]

# Вкладка пайплайна — не украшение, а ПЕРЕКЛЮЧАТЕЛЬ ДОСКИ: за невыбранной
# вкладкой лежит работа, которой на экране не видно. Счётчики вкладок сняли
# как «третью копию числа» — и это была ошибка: копией счётчик был только
# у ВЫБРАННОЙ вкладки (там же доска, там же срез), а у остальных он —
# единственный источник. Инцидент, вставший за вкладкой, экран обязан назвать.
# Число несут только невыбранные вкладки; выбранная называет длину пайплайна.

assert [n for n, _ in BOARD if n != 'Готово'] == STAGES[MAIN]

# Второй канал чипа — знак, и он обязан работать, а не повторять цвет.
# На всех янтарных чипах стояла реплика, включая те, где никто ничего
# не спрашивал: на карточке ждали приёмки артефакта, а знак обещал вопрос.
# Теперь реплика — там, где вопросы, лупа над листом — там, где ждут ревью;
# это тот же знак, которым в рейле назван раздел «Ревью артефактов».
CHIP = {'wait': ('st warn', 'i-ask'), 'live': ('st live', None),
        'stall': ('st err', 'i-alert'), 'fail': ('st err', 'i-alert'),
        # У «принят» второго канала нет и не нужно: чип не несёт цвета,
        # а глиф съедал три знака подписи в дорожке шириной 110 px.
        'done': ('st done', None)}

# Ширина дорожки — свойство пайплайна, а не окна: одна и та же карточка обязана
# быть одного размера на доске из трёх стадий и из восьми.
# «Готово» — не девятая стадия, а корзина, и подпись «CRISPY, 8 стадий» это
# прямо утверждает. Значит, между PR и «Готово» шов обязан быть шире, чем
# между стадиями: внутреннее меньше внешнего. Шов сделан ОТДЕЛЬНОЙ дорожкой
# грида, а не отступом внутри колонки, — отступ съедал бы ширину карточки
# и та же карточка оказывалась бы уже соседних (уже наступали).
# ЧЕТЫРЕ ВЕЛИЧИНЫ, И ВСЕ ЧЕТЫРЕ РАЗНЫЕ. Стояло 12 = 12 = 12: поле внутри
# карточки, зазор между карточками в стопке и зазор между колонками были одним
# и тем же числом. Карточка при этом не отделялась от соседа ничем — её
# собственное поле равнялось рву вокруг неё, и доска читалась однородной
# сеткой 12 px, а не набором объектов. Теперь порядок величин виден:
# 8 внутри карточки · 12 между карточками · 16 между колонками · 24 поле
# плиты · 52 шов перед «Готово». Внутреннее меньше внешнего на каждом уровне
# вложенности, и лестница монотонна снизу доверху.
#
# ДОРОЖКА — КОНСТАНТА. Стояла формула «сколько влезет, но не больше 168», и на
# трёхстадийном хотфиксе дорожка честно доезжала до потолка: одна и та же
# карточка оказывалась на 27 % шире, чем на восьмистадийной фиче. То есть закон,
# ради которого формулу писали, ею же и нарушался. Короткий пайплайн теперь
# не растягивает карточки, а оставляет канвас пустым справа: пустота и есть
# сообщение «стадий всего три».
# 1280 — не круглое число, а ЗАМЕР: ширина плиты канваса минус её поля.
# Стояло 1316, и доска на 4 px вылезала за собственное правое поле — «Готово»
# кончалось правее плиты. 9 × 124 + 9 × 16 + 20 = 1280 ровно — и это ЗАМЕР
# плиты у Chrome, а не арифметика на бумаге: сборка сверяет их между собой.
# ПОЛЕ ОКНА БЫЛО РАВНО ШВУ МЕЖДУ ПЛИТАМИ: 16 и 16. Четыре плиты внутри окна
# не читались группой — внешнее не было больше внутреннего, и .md при этом
# объявляла шов в 8. Поле окна поднято до 24, шов оставлен 16.
# ТО ЖЕ РАВЕНСТВО СТОЯЛО ЭТАЖОМ НИЖЕ, и его нашли сразу два критика: поле
# самой плиты канваса тоже было 16 при зазоре между дорожками 16. Крайняя
# колонка отстояла от кромки своей плиты ровно настолько же, насколько её
# плита — от соседней, и девять колонок не читались группой ВНУТРИ плиты.
# Поле плиты поднято до 24. Ширина окна при этом не изменилась ни на пиксель:
# 16 px, которые канвас потерял с каждой стороны, сняты с дорожки и шва
# (126 → 124, 18 → 20), а плита осталась той же ширины: 1280 + 48 = 1328.
# ПОЛЕ МЕРЯЕТСЯ С ПРОСВЕТОМ ВНУТРИ СВОЕЙ ПЛИТЫ, а не со швом между плитами:
# шов разделяет две ВИДИМЫЕ плоскости, и работу разделения там делает кромка,
# а не пустота. Поэтому 24 > 16 внутри плиты — закон, а 16 между плитами при
# поле 24 — не нарушение: сравнивать их не на чем.
WINPAD, GAP, BOARDPAD = 24, 16, 24
CANVAS, SEAM, LANE = 1280, 20, 124

def lane_px(n_cols):
    return LANE

DONE_GAP_CELL = '<i class="kb-gap"></i>'

def seam_px(n_cols):
    """Шов — тоже константа: между PR и «Готово» пустая дорожка 20 плюс два
    зазора по 16, итого 52 видимых пикселя против 16 между стадиями."""
    return SEAM

def board_style(n_cols, extra=''):
    """n_cols считает и «Готово»: последняя дорожка отделена швом."""
    L = lane_px(n_cols)
    return (f'class="board tmpl{extra}" style="grid-template-columns:'
            f'repeat({n_cols - 1},{L}px) {seam_px(n_cols)}px {L}px"')

def work(board):
    """Сколько change’ей в работе: «Готово» — не стадия, а корзина."""
    it = board.items() if isinstance(board, dict) else board
    return sum(len(c) for n, c in it if n != 'Готово')

def num(v):
    """Тысячи — тонкой шпацией: 1 247, а не 1247 и не 1,247."""
    return f'{v:,}'.replace(',', ' ') if isinstance(v, int) else v

def counts(board):
    n = {'wait': 0, 'live': 0, 'stop': 0}
    for name, cards in board:
        if name == 'Готово':
            continue
        for _, _, _, mv, _ in cards:
            n['stop' if mv in ('stall', 'fail') else mv] += 1
    return n

def card(kind, title, branch, move, text, sel=False, snapshot=False, state='', ask=False):
    cls = 'kb-card' + (' sel' if sel else '') + (f' {state}' if state else '')
    chip, glyph = CHIP[move]
    # Знак различает, ЧЕГО от вас ждут. Раньше он выводился из слова «вопрос»
    # в подписи чипа; подпись стала однородной («ждёт срок»), и признаком
    # служит стадия: на Questions агент спрашивает, дальше — показывает
    # артефакт и ждёт приёмки.
    if move == 'wait' and not ask:
        glyph = 'i-review'
    if snapshot and move == 'live':
        chip, glyph, text = 'st mute', None, 'нет связи'
    dot = ('<span class="dot"></span>' if chip.endswith('live')
           else (f'<svg class="ic ic-x"><use href="#{glyph}"/></svg>' if glyph else ''))
    # Ветка с карточки снята. На восемнадцати карточках доски она была
    # транслитерацией собственного заголовка («Ноутч-хелпер» → feat/notch-helper),
    # то есть строкой-дублем, — и при этом у трети карточек не помещалась
    # и обрывалась многоточием. Строка, которая ничего не добавляет и вдобавок
    # врёт обрывком, снимается по тесту удаления; ветка осталась там, где она
    # нужна для дела, — в инспекторе, откуда её копируют.
    return f'''<div class="{cls}">
                <div class="kc-top"><span class="kc-pict"><svg class="ic ic-s"><use href="#i-{kind}"/></svg></span><span class="kc-title">{nb(title)}</span></div>
                <div class="kc-meta">
                  <div class="kc-foot"><span class="{chip}">{dot}<span class="st-tx">{nb(text)}</span></span></div>
                </div>
              </div>'''

def column(name, cards, snapshot=False, sel_title=None, empty_note=None, folded=True,
           of=None):
    n = (DONE_TOTAL if folded else len(cards)) if name == 'Готово' else len(cards)
    if of is not None:
        n = f'{n} <span class="kbn-of">из {of}</span>'
    body = '\n'.join(card(*c, sel=(c[1] == sel_title), snapshot=snapshot,
                          ask=(name == 'Questions' or name == 'Repro'))
                     for c in cards)
    if not cards and empty_note:
        body = f'<div class="kb-empty">{nb(empty_note)}</div>'
    hidden = DONE_TOTAL - len(cards)
    fold = (f'<div class="fold-note">{nb(f"Ещё {hidden} принятых")}</div>'
            if name == 'Готово' and folded and hidden > 0 else '')
    done = ' done' if name == 'Готово' else ''
    return f'''<div class="kb-col{done}">
              <div class="kb-col-head">
                <div class="kbrow"><span class="kbt">{name}</span><span class="kbn">{n}</span></div>
              </div>
              {body}
              {fold}
            </div>'''

def rail(sel='board'):
    # Восемь незнакомых пиктограмм без единого слова — ребус: рейл называл
    # разделы только всплывающей подсказкой, то есть тому, кто уже знает,
    # куда наводить. Теперь под каждым знаком стоит слово. Заплачено 32 px
    # канваса (CANVAS уменьшен на столько же), выручено — весь каркас стал
    # называть себя сам, и два дубля слова «Канбан» ушли: заголовок сайдбара
    # и хвост в заголовке окна.
    items = [('inbox','Инбокс'),('board','Канбан'),('review','Ревью'),
             ('tasks','Задачи'),('projects','Проекты'),('insights','Аналитика'),('skills','Навыки')]
    out = []
    for ic, title in items:
        cls = 'rl sel' if ic == sel else 'rl'
        out.append(f'<span class="{cls}"><svg class="ic"><use href="#i-{ic}"/></svg>'
                   f'<span class="rl-tx">{title}</span></span>')
    out.append('<span class="rl-sp"></span>')
    out.append('<span class="rl"><svg class="ic"><use href="#i-settings"/></svg>'
               '<span class="rl-tx">Настройки</span></span>')
    return '<nav class="rail">\n          ' + '\n          '.join(out) + '\n        </nav>'

def sidebar(slice_counts, project_rows, sel_project='foundry-desktop', unknown=False,
            sel_slice='Всё в работе'):
    # «Всё в работе» — состояние «фильтр снят», а не четвёртое число:
    # его значение и так лежит суммой трёх строк ниже. Одно число — одно место.
    #
    # При потере связи прочерк ставится ТОЛЬКО у «Хода агента». Сколько
    # change’ей ждут вас и сколько встало, видно по снапшоту: янтарные и
    # коралловые чипы никуда с доски не делись. Прочерк там, где их три,
    # спорил бы с доской — а спорить с тем, что читатель видит, нельзя.
    # Срез называет состояния ТЕМИ ЖЕ словами, что и чипы на карточках.
    # Стояло «Ждут вас · Агент работает · Встало» при чипах «ваш ход · ход
    # агента · встало»: два словаря на одну и ту же тройку состояний, и глазу
    # приходилось их сопоставлять вместо того, чтобы просто узнать.
    rows = [('Всё в работе', ''),
            ('Ваш ход',   slice_counts['wait']),
            ('Нет связи' if unknown else 'Ход агента', slice_counts['live']),
            ('Ничей ход',  slice_counts['stop'])]
    rows = [(label, val, label == sel_slice) for label, val in rows]
    srez = ''
    for label, val, sel in rows:
        srez += (f'<div class="side-item bare{" sel" if sel else ""}">'
                 f'<span class="grow">{label}</span>'
                 f'<span class="count">{val}</span></div>\n            ')
    proj = ''
    for label, val, ic in project_rows:
        sel = label == sel_project
        proj += (f'<div class="side-item bare{" sel" if sel else ""}">'
                 f'<span class="grow">{label}</span>'
                 f'<span class="count">{num(val)}</span></div>\n            ')
    # Заголовка «Канбан» здесь больше нет: раздел назван в рейле, и слово
    # стояло на экране трижды — в рейле, тут и в заголовке окна.
    return f'''<aside class="pane sidebar">
          <div class="side-sec">
            <div class="side-cap">Срез</div>
            {srez}</div>
          <div class="side-sec">
            <div class="side-cap">Проект</div>
            {proj}</div>
        </aside>'''

def pipebar(sel=0, project='foundry-desktop', compact=False):
    # Число несёт КАЖДАЯ вкладка, у которой есть работа, включая выбранную.
    # Сначала выбранная вкладка числа не носила («там же доска, там же срез»),
    # и тогда сумма на экране не сходилась: счётчик проекта 22 не с чем было
    # сложить, а «3» у соседней вкладки стояло в том же слоте, что «8 стадий»
    # у выбранной, и честно читалось как число стадий. Теперь слот один и тот
    # же у всех: чип с числом change’ей; длина пайплайна ушла в подпись.
    tabs = ''
    # На минимуме ширины полоса вкладок обрезалась кромкой плиты, и вкладка
    # «Инцидент» исчезала целиком — вместе с единственным на экране словом
    # о работе, которой на доске не видно. Дефицит ширины сворачивает
    # вкладки в остаток со своим числом, а не срезает их.
    if compact:
        rest = [n for i, n in enumerate(PIPES) if i != sel]
        cnt = sum(WORLD[project].get(n, 0) for n in rest)
        name = PIPES[sel]
        k = len(STAGES[name])
        word = 'стадии' if k in (2, 3, 4) else 'стадий'
        chip = f'<span class="pipe-n">{WORLD[project].get(name, 0)}</span>' if WORLD[project].get(name) else ''
        more = (f'<div class="pipe-tab more"><div class="pipe-name">{nb(f"Ещё {len(rest)} вкладки")}</div>'
                f'<span class="pipe-n">{cnt}</span></div>') if cnt else ''
        return (f'<div class="pipe-bar">\n            <div class="pipe-tab sel">'
                f'<div class="pipe-name">{nb(name)}</div>{chip}'
                f'<div class="pipe-meta">{nb(f"{k} {word}")}</div></div>\n            {more}</div>')
    for i, name in enumerate(PIPES):
        cls = 'pipe-tab sel' if i == sel else 'pipe-tab'
        n = len(STAGES[name])
        word = 'стадии' if n in (2, 3, 4) else 'стадий'
        cnt = WORLD[project].get(name, 0)
        # Ноль на вкладке — не величина, а её отсутствие. На пустом проекте
        # экран печатал семнадцать нулей, и приглашение «заведите первый»
        # конкурировало по площади с семнадцатью повторами одного факта.
        chip = f'<span class="pipe-n">{cnt}</span>' if cnt else ''
        meta = f'<div class="pipe-meta">{nb(f"{n} {word}")}</div>' if i == sel else ''
        tabs += (f'<div class="{cls}"><div class="pipe-name">{nb(name)}</div>'
                 f'{chip}{meta}</div>\n            ')
    return f'<div class="pipe-bar">\n            {tabs}</div>'

def titlebar(project='foundry-desktop'):
    # Главное действие экрана названо словом, а не одним плюсом: на пустой
    # доске оно зовётся «Новый change», и безымянная иконка в титлбаре была
    # тем же действием под другим именем. Лупа остаётся иконкой — поиск
    # опознаётся без подписи, а создание нет.
    # Заголовок окна называет тот проект, который выбран в сайдбаре. Стояло
    # жёстко «foundry-desktop», и на кадре пустого проекта окно спорило
    # с подсветкой в списке слева.
    return f'''<div class="titlebar">
        <div class="lights"><i class="r"></i><i class="y"></i><i class="g"></i></div>
        <span class="win-title">{project}</span>
        <div class="spacer"></div>
        <span class="tb-btn named"><svg class="ic"><use href="#i-search"/></svg>Поиск<kbd class="tb-k">⌘K</kbd></span>
        <span class="tb-btn named"><svg class="ic"><use href="#i-plus"/></svg>Новый change<kbd class="tb-k">⌘N</kbd></span>
      </div>'''

# ── кадры ────────────────────────────────────────────────────────────────────
# Срез считает ровно то, что видно на доске: пересчитав чипы, читатель обязан
# получить те же числа. Поэтому они не пишутся рукой, а выводятся из модели.
SREZ = counts(BOARD)
C = SREZ
IN_WORK = work(BOARD)
assert SREZ['wait'] + SREZ['live'] + SREZ['stop'] == IN_WORK == 18
PROJ = proj_total('foundry-desktop')
assert PROJ == 22 == IN_WORK + 3 + 1

# Порядок карточек в колонке — по времени без движения, сверху самые давние.
# Порядок, который не заявлен и не соблюдается, читатель всё равно ищет —
# и находит несуществующий. Проверка ниже роняет сборку при нарушении и
# ИСКЛЮЧЕНИЙ БОЛЬШЕ НЕ ЗНАЕТ: раньше от неё были свободны колонки с чипами-долями
# («4 из 7», «ревью 1 из 2») — то есть код прямо расписывался, что сравнить эти
# карточки с соседними нечем. Доли сняты (см. закон одной шкалы выше), и вместе
# с ними исчезло исключение.
UNIT = {'с': 1 / 60, 'мин': 1, 'ч': 60, 'д': 1440}

def age(text):
    m = re.search(r'(\d+)\s*(мин|ч|д|с)\b', text)
    return int(m.group(1)) * UNIT[m.group(2)] if m else None

def check_order(board, label):
    it = board.items() if isinstance(board, dict) else board
    for name, cards in it:
        # «Готово» живёт по другому правилу и говорит об этом словом «принят»:
        # корзина, сверху последнее принятое. Стадии живут по сроку простоя.
        if name == 'Готово':
            continue
        ages = [age(c[4]) for c in cards]
        assert all(a is not None for a in ages), (label, name, [c[4] for c in cards])
        assert ages == sorted(ages, reverse=True), (label, name, ages)
assert SREZ == {'wait': 6, 'live': 9, 'stop': 3}

def queue_pos(title, kind='wait'):
    """«N-й из M, кто ждёт вас» — обе величины считаются по доске. Стояло
    «4-й из 5» при пятом по старшинству простоя: число, которое читатель
    пересчитывает глазами по этому же экрану, было написано рукой."""
    same = [c for _n, cs in BOARD for c in cs
            if (c[3] in ('stall', 'fail') if kind == 'stop' else c[3] == kind)]
    same.sort(key=lambda c: -age(c[4]))
    names = [c[1] for c in same]
    assert title in names, (title, names)
    word = 'кто ждёт вас' if kind == 'wait' else 'кто встал'
    return f'{names.index(title) + 1}-й из {len(names)}, {word}'

def undated_last(cards):
    """На снапшоте у «хода агента» срока нет вовсе: он мог кончиться в любую
    секунду. Карточки без срока, оставленные вперемешку, ломают единственный
    заявленный закон колонки — сверху самые давние, — поэтому они уходят
    в конец, и баннер об этом говорит словом."""
    return [c for c in cards if c[3] != 'live'] + [c for c in cards if c[3] == 'live']

def board_html(snapshot=False, sel_title=None, only=None, scrollx=False):
    """only — код хода: доска под срезом показывает лишь его карточки."""
    full = dict((n, len(c)) for n, c in BOARD)
    board = ([(n, [c for c in cards if (c[3] in ('stall', 'fail') if only == 'stop' else c[3] == only)])
              for n, cards in BOARD] if only else BOARD)
    if snapshot:
        board = [(n, undated_last(cs)) for n, cs in board]
    cols = [column(n, c, snapshot=snapshot, sel_title=sel_title, folded=only is None,
                   of=(DONE_TOTAL if n == 'Готово' else full[n]) if only else None)
            for n, c in board]
    cols.insert(-1, DONE_GAP_CELL)
    return (f'<div {board_style(len(board), " scrollx" if scrollx else "")}>\n            '
            + '\n            '.join(cols) + '\n          </div>')

def frame(inner, cls='win', project='foundry-desktop', style=''):
    style = f' style="{style}"' if style else ''
    return f'<div class="{cls}"{style}>\n      {titlebar(project)}\n\n      <div class="two">\n        {inner}\n      </div>\n    </div>'

def sec(num, h2, lead, body, caption):
    return f'''
  <section class="block wide">
    <div class="sec-head">
      <span class="sec-num">{num}</span>
      <h2>{nb(h2)}</h2>
      <p>{nb(lead)}</p>
    </div>

    {body}

    <div class="caption">{caption}</div>
  </section>
'''

TOAST = '''<div class="toast-dock">
            <div class="toast">
              <span class="tx"><b>«Хранилище инбокса»</b> перенесён в Structure</span>
              <span class="undo">Отменить <span style="font-family:var(--font-mono);opacity:0.7">⌘Z</span></span>
              <span class="bar"></span>
            </div>
          </div>'''

# 20 — доска
f20 = frame(f'''{rail()}

        {sidebar(SREZ, projects())}

        <div class="pane list">
          {pipebar()}
          {board_html()}
          {TOAST}
        </div>''')

# 21 — инспектор по требованию
# Шапка инспектора одна на все три спроса. В ней появились две вещи, которых
# не было: ВЫХОД (закрытие держалось на ненарисованном клике по скриму — про
# Esc знал только текст спецификации) и МЕСТО В ОЧЕРЕДИ. Очередь важнее: экран
# существует ради того, чтобы разобрать всех, кто ждёт, а инспектор умел
# открыться и закрыться — пять раз открыть, пять раз закрыть и каждый раз
# заново искать карточку глазами.
def insp_head(name, branch, where, pos):
    return f'''<div class="insp-head">
              <div class="insp-top">
                <div class="insp-name">{nb(name)}</div>
                <div class="insp-nav">
                  <span class="in-b">Пред. <kbd>⌥←</kbd></span>
                  <span class="in-b">След. <kbd>⌥→</kbd></span>
                  <span class="in-x">Закрыть <kbd>Esc</kbd></span>
                </div>
              </div>
              <div class="sub"><span class="mono">{branch}</span></div>
              <div class="insp-where">{nb(where)}</div>
              <div class="insp-where in-pos">{nb(pos)}</div>
            </div>'''

INSP = f'''<div class="board-scrim"></div>

          <aside class="overlay-insp">
            {insp_head('Токены тёмной темы', 'feat/dark-tokens',
                       'Стадия 3 из 8 — <b>Design</b>. Дальше Structure.',
                       queue_pos('Токены тёмной темы'))}
            <div class="artifact">
              <h4>Артефакт</h4>
              <div class="kv">design.md, 214 строк</div>
              <p>Тема одна — тёмная. Поверхности выше базы <b>обесцвечены</b>: хрома фона тянет к себе тёплый акцент и делает его грязным.</p>
              <p>Текст — альфа-белый <code>92% / 70% / 56% / 44%</code>; цвет не идёт текстом, он приходит <b>залитым чипом</b> малой площади.</p>
              <ul>
                <li>«ваш ход» — янтарный, «встало» — коралловый;</li>
                <li>ход агента цвета не получает: это норма, а не событие;</li>
                <li>ультрамарин зарезервирован за действием.</li>
              </ul>
              <p>Ступени поверхностей идут по светлоте примерно через пять единиц светлоты: база, плита, карточка, оверлей — четыре, и все. Наведение ступенью не считается: оно поднимает карточку на месте и гаснет вместе с курсором. Ниже базы уходит только выемка — место, откуда карточку вынули.</p>
              <p>Тень на почти-чёрном не работает как тень: гасить нечего. Отделение даёт свет по кромке в один пиксель, а тёмное гало остаётся только там, где под ним живой рой частиц.</p>
              <p>Состояния складываются: карточку можно одновременно выбрать, навести и держать на ней фокус. Поэтому ни одно из них не занимает канал соседнего.</p>
            </div>
            <div class="actionbar">
              <div class="insp-more">{nb('Открыть design.md целиком')}</div>
              <div class="comment-field">Комментарий к ревью…</div>
              <div class="act-cost">{nb('Приняв, вы запускаете Structure: это ход агента и расход токенов. Отмена доступна 10 с.')}</div>
              <div class="btns">
                <span class="btn secondary">Вернуть на доработку</span>
                <span class="btn primary">Принять <kbd>⌘⏎</kbd></span>
              </div>
            </div>
          </aside>'''

f21 = frame(f'''{rail()}

        {sidebar(SREZ, projects())}

        <div class="pane list">
          {pipebar()}
          {board_html(sel_title='Токены тёмной темы')}
          {INSP}
        </div>''', cls='win ovl tall')

# 22 — ядро не отвечает: экран показывает снапшот и не выдаёт незнание за факт
BANNER = '''<div class="degrade">
            <span class="dg-ic"><svg class="ic"><use href="#i-alert"/></svg></span>
            <span class="dg-tx"><b>foundry CLI не отвечает.</b> Доска показывает снапшот, ему 2 мин. Пишет в проект только CLI, поэтому сейчас нельзя ничего: ни ответить на вопросы, ни принять артефакт, ни перетащить карточку. Сколько change у агента сейчас, знать неоткуда: 9 — столько их было в снапшоте, и карточки без срока стоят в конце своих колонок.</span>
            <span class="btn secondary">Проверить снова</span>
          </div>'''

f22 = frame(f'''{rail()}

        {sidebar(SREZ, projects(), unknown=True)}

        <div class="pane list">
          {BANNER}
          {pipebar()}
          {board_html(snapshot=True)}
        </div>''')


# 24 — экстремумы данных: то, на чём композиция обязана не разваливаться
LONG = ('feature',
        'Экспорт диффа в светлой печатной палитре с постраничной нумерацией',
        'feat/diff-export-light-print-paginated-with-line-numbers',
        'wait', 'ждёт 49 ч')
EXTREME = [
 ('Questions', []),
 ('Research',  [LONG]),
 ('Design',    []),
 ('Structure', [('cycle', 'Хранилище инбокса', 'refactor/inbox-store', 'live', 'идёт 3 мин')]),
 ('Plan',      []),
 ('Worktree',  []),
 # Порядок в сорока карточках — тот же закон, что и на всей доске: сверху те,
 # что дольше без движения. Стояли вперемешку («встало 2 ч» через каждые три
 # карточки по 4 мин), и колонка, которую в этом кадре как раз и разглядывают,
 # единственная жила без правила. Проверка внизу файла теперь считает и её.
 ('Implement', [('feature', f'Пакетная правка {i:02d}', f'feat/batch-{i:02d}',
                 'stall' if i <= 5 else 'live',
                 f'встало {8 - i} ч' if i <= 5 else f'идёт {46 - i} мин')
                for i in range(1, 41)]),
 ('PR',        []),
 ('Готово',    [('feature', 'Онбординг', 'feat/onboarding', 'done', 'вчера, 14:32')]),
]
# Подписи в пустых колонках сняты: «В проекте нет активной работы» под
# колонкой Questions на доске с сорока двумя карточками — прямая неправда,
# а «ничего не ждёт вас» повторяет то, что и так видно по отсутствию чипов.
# Пустая колонка при непустой доске — хорошая новость и молчит.
EMPTY_NOTE = {}

def extreme_board():
    out = []
    for name, cards in EXTREME:
        n = 1247 if name == 'Готово' else len(cards)
        if cards:
            body = '\n'.join(card(*c) for c in cards)
        else:
            note = EMPTY_NOTE.get(name, '')
            body = f'<div class="kb-empty">{nb(note)}</div>' if note else ''
        scroll = ' scrolls' if len(cards) > 6 else ''
        done = ' done' if name == 'Готово' else ''
        fold = (f'<div class="fold-note">{nb(f"Ещё {num(1247 - len(cards))} принятых")}</div>'
                if name == 'Готово' else '')
        out.append(f'''<div class="kb-col{done}{scroll}">
              <div class="kb-col-head">
                <div class="kbrow"><span class="kbt">{name}</span><span class="kbn">{n if n != 1247 else "1 247"}</span></div>
              </div>
              <div class="kb-stack">{body}</div>
              {fold}
            </div>''')
    out.insert(-1, DONE_GAP_CELL)
    return (f'<div {board_style(len(EXTREME))}>\n            '
            + '\n            '.join(out) + '\n          </div>')

def empty_board():
    cols = []
    for st in STAGES[MAIN] + ['Готово']:
        done = ' done' if st == 'Готово' else ''
        cols.append(f'''<div class="kb-col{done}">
              <div class="kb-col-head"><div class="kbrow"><span class="kbt">{st}</span><span class="kbn">0</span></div></div>
            </div>''')
    cols.insert(-1, DONE_GAP_CELL)
    # nogrow: доска с пустыми колонками не имеет права забирать свободную
    # высоту — иначе блок-приглашение прижимается к низу канваса вместо того,
    # чтобы стоять в свободной зоне под шапками.
    board = (f'<div {board_style(len(STAGES[MAIN]) + 1, " nogrow")}>\n            '
             + '\n            '.join(cols) + '\n          </div>')
    hero = f'''<div class="board-none">
            <div class="bn-t">{nb('В этом проекте ещё нет ни одного change')}</div>
            <div class="bn-s">{nb('Первый встанет в Questions: агент задаст вопросы, вы ответите, дальше он поведёт change по стадиям сам.')}</div>
            <span class="btn primary">Новый change <kbd>⌘N</kbd></span>
          </div>'''
    return board + hero

EX_WORK = work(EXTREME)
EX_ZERO = sum(1 for n, c in EXTREME if n != 'Готово' and not c)
EX_MAX = max(len(c) for n, c in EXTREME if n != 'Готово')
EX_CAP = (f'{EX_MAX} карточек в одной колонке, 1 247 в архиве, '
          f'ноль в {EX_ZERO} стадиях из {len(STAGES[MAIN])}')

f24 = f'''<div class="pipe-pair">
      <div class="pipe-case">
        <div class="pipe-case-cap">{nb(EX_CAP)}</div>
        {frame(f"""{rail()}

        {sidebar(counts(EXTREME), projects(), sel_project='monorepo')}

        <div class="pane list">
          {pipebar(project='monorepo')}
          {extreme_board()}
        </div>""", project='monorepo')}
      </div>
      <div class="pipe-case">
        <div class="pipe-case-cap">Ноль: новый проект, в котором ещё ничего не заводили</div>
        {frame(f"""{rail()}

        {sidebar({'wait': 0, 'live': 0, 'stop': 0}, projects(), sel_project='дизайн-система')}

        <div class="pane list short">
          {pipebar(project='дизайн-система')}
          {empty_board()}
        </div>""", project='дизайн-система')}
      </div>
    </div>'''

# 25 — пайплайны разной длины: три стадии и десять
def board_for(pipe, by_stage, done, done_total, scrollx=False):
    cols = []
    for st in STAGES[pipe]:
        cards = by_stage.get(st, [])
        body = '\n'.join(card(*c, ask=(st in ('Questions', 'Repro', 'Triage'))) for c in cards)
        cols.append(f'''<div class="kb-col">
              <div class="kb-col-head"><div class="kbrow"><span class="kbt">{st}</span><span class="kbn">{len(cards)}</span></div></div>
              {body}
            </div>''')
    hidden = done_total - len(done)
    fold = (f'<div class="fold-note">{nb(f"Ещё {num(hidden)} принятых")}</div>'
            if hidden > 0 else '')
    cols.append(f'''<div class="kb-col done">
              <div class="kb-col-head"><div class="kbrow"><span class="kbt">Готово</span><span class="kbn">{done_total}</span></div></div>
              {"".join(card(*c) for c in done)}
              {fold}
            </div>''')
    cols.insert(-1, DONE_GAP_CELL)
    return (f'<div {board_style(len(STAGES[pipe]) + 1, " scrollx" if scrollx else "")}>'
            '\n            ' + '\n            '.join(cols) + '\n          </div>')

HOTFIX = {
  # Путь с карточки убран намеренно: имя файла в заголовке ломалось переносом
 # так, что вторая строка открывалась точкой («.foundry»), а связать его
 # неразрывным с предыдущим словом нельзя — пара не влезает в дорожку 111 px
 # и режется без многоточия. Карточка называет change человеческими словами,
 # путь живёт в ветке и в инспекторе, откуда его копируют.
 'Repro': [('feature', 'Падение на пустом проекте', 'hotfix/empty-foundry', 'wait', 'ждёт 40 мин')],
 'Fix':   [('feature', 'Гонка в очереди стадий',     'hotfix/stage-race',    'live', 'идёт 6 мин')],
 'Ship':  [],
}
MANY = {
 'Questions': [('feature', 'Единый идентификатор change', 'feat/change-id', 'wait', 'ждёт 2 ч')],
 'Research':  [],
 'Design':    [('feature', 'Формат события стадии', 'feat/stage-event', 'live', 'идёт 9 мин')],
 'Contracts': [('doc', 'Схема события v2', 'docs/event-schema', 'wait', 'ждёт 3 ч'),
               ('feature', 'Обратная совместимость v1', 'feat/event-compat', 'live', 'идёт 2 мин')],
 'Structure': [],
 'Plan':      [('feature', 'Очередь ретраев', 'feat/retry-queue', 'live', 'идёт 12 мин')],
 'Worktree':  [],
 'Implement': [('feature', 'Публикация событий', 'feat/event-publish', 'stall', 'встало 3 ч')],
 'Integration':[('feature', 'Сквозной прогон трёх сервисов', 'feat/e2e-three', 'live', 'идёт 2 ч')],
 'PR':        [],
}

f25 = f'''<div class="pipe-pair">
      <div class="pipe-case">
        <div class="pipe-case-cap">Хотфикс — три стадии</div>
        {frame(f"""{rail()}

        {sidebar(counts(list(HOTFIX.items())), projects(), sel_project='crispy-core')}

        <div class="pane list short">
          {pipebar(sel=3, project='crispy-core')}
          {board_for('Хотфикс', HOTFIX, [('feature', 'Утечка дескрипторов', 'hotfix/fd-leak', 'done', 'вт, 09:40')], 31)}
        </div>""", project='crispy-core')}
      </div>
      <div class="pipe-case">
        <div class="pipe-case-cap">Фича в нескольких сервисах — десять стадий, доска едет вбок</div>
        {frame(f"""{rail()}

        {sidebar(counts(list(MANY.items())), projects(), sel_project='crispy-core')}

        <div class="pane list short">
          {pipebar(sel=1, project='crispy-core')}
          {board_for('Фича в нескольких сервисах', MANY,
                    [('doc', 'Словарь событий', 'docs/event-glossary', 'done', 'сб, 16:10')], 4, scrollx=True)}
        </div>""", project='crispy-core')}
      </div>
    </div>'''

# 26 — срез применён: сайдбар не только называет числа, но и режет доску
def slice_note(name, shown, total):
    """Фильтр, который прячет данные, обязан вслух сказать, что прячет."""
    # Знаменатель назван словом: сумма знаменателей в шапках колонок даёт
    # тридцать, потому что в неё входит корзина, а срез считает работу.
    # Читатель, который пересчитывает числа глазами, обязан сойтись.
    return (f'''<div class="slice-note">Срез <b>{nb(name)}</b>: {nb(f"показаны {shown} из {total}")}
            {nb('change в работе, остальные скрыты. Снять срез — строкой «Всё в работе» в пульте слева.')}</div>''')

f26 = frame(f"""{rail()}

        {sidebar(SREZ, projects(), sel_slice='Ваш ход')}

        <div class="pane list">
          {pipebar()}
          {slice_note('«Ваш ход»', SREZ['wait'], IN_WORK)}
          {board_html(only='wait')}
        </div>""")

CAP26 = (f'<b>Сайдбар назван пультом — значит, нажатие обязано быть нарисовано.</b> Строка среза не подсвечивает карточки и не крутит доску к ним: она убирает с доски всё остальное, оставляя колонки на месте. Дорожки той же ширины, карточка того же размера, стадии в том же порядке — глазу не нужно заново искать, где Design; меняется только населённость колонок. '
         f'<b>Счётчики среза остаются {SREZ["wait"]} / {SREZ["live"]} / {SREZ["stop"]}, а не превращаются в {SREZ["wait"]} / 0 / 0.</b> Это размеры срезов, а не содержимое доски: обнулив соседние строки, пульт отнял бы у себя единственный способ показать, куда ещё можно нажать. По той же причине счётчик проекта остаётся {PROJ} — он считает работу, а не показ. '
         f'<b>Отсюда строка под вкладками.</b> Три числа на экране — {SREZ["wait"]} в колонках, {IN_WORK} в знаменателе и {PROJ} в списке проектов — обязаны быть связаны словом, иначе читатель решит, что одно из них врёт. Знаменателем строка называет работу, а не сумму шапок: шапки складываются в {IN_WORK} плюс корзина, и без слова «в работе» пересчёт дал бы третье число. Выхода строка не даёт вовсе — он один и лежит в пульте: два одинаково названных выхода заставляли бы выбирать между ними вместо того, чтобы просто выйти. '
         '<b>Колонки с нулём молчат</b> — тот же закон, что на кадре 24: пусто в Research под срезом «ваш ход» значит «здесь вас не ждут», и это хорошая новость.')

# 27 — инспектор отвечает на ТОТ спрос, который на карточке
# Три из шести янтарных чипов доски — вопросы агента, а нарисован был один
# инспектор: приёмка артефакта. Большинство «вашего хода» упиралось в экран,
# на котором нет ни вопроса, ни поля ответа, зато есть «Принять» — кнопка,
# которой в этом спросе принимать нечего. То же со вставшим: чип кричит
# «встало 6 ч», а инспектор предлагал принять артефакт, которого нет.
QUESTIONS = [
 'Скоуп по умолчанию — синглтон на весь контейнер или на модуль? '
 'В Spring синглтон на контейнер, но у нас модули поднимаются порознь.',
 'Прототипы вообще нужны? В коде два места, где бин пересоздают руками, '
 'и оба обходятся фабрикой.',
 'Бин, у которого зависимость шире собственного скоупа, — падать при сборке '
 'контейнера или на первом обращении?',
]

def thread():
    qs = ''.join(f'<div class="q"><span class="qn">{i}</span>'
                 f'<p>{nb(t)}</p></div>' for i, t in enumerate(QUESTIONS, 1))
    return f"""<div class="artifact thread">
              <h4>Вопросы агента</h4>
              <div class="kv">заданы вчера, 09:40</div>
              {qs}
              <div class="q-note">{nb('Пока вы не ответите, change стоит: следующая стадия зависит от ответов.')}</div>
            </div>"""

INSP_ASK = f'''<div class="board-scrim"></div>

          <aside class="overlay-insp">
            {insp_head('Скоупы бинов Spark', 'feat/spark-scopes',
                       'Стадия 1 из 8 — <b>Questions</b>. Дальше Research.',
                       queue_pos('Скоупы бинов Spark'))}
            {thread()}
            <div class="actionbar">
              <div class="cf-block">
                <div class="cf-head">Ответ агенту<span class="cf-to">{nb('на все три вопроса сразу, номерами')}</span></div>
                <div class="comment-field ask">{nb('Ответ…')}</div>
              </div>
              <div class="btns">
                <span class="btn primary">Ответить агенту <kbd>⌘⏎</kbd></span>
              </div>
            </div>
          </aside>'''

INSP_STALL = f'''<div class="board-scrim"></div>

          <aside class="overlay-insp">
            {insp_head('Контекст доски', 'feat/board-context',
                       'Стадия 4 из 8 — <b>Structure</b>. Встало 6 ч.',
                       queue_pos('Контекст доски', 'stop'))}
            <div class="artifact stall">
              <h4>Причина</h4>
              <p>{nb('Агент трижды подряд получил один и тот же отказ от')} <code>foundry stage run</code>: {nb('рабочее дерево занято, его держит другой change.')}</p>
              <div class="kv">{nb('дерево .foundry/wt/board-context держит «Орб-лоадер» (Implement, идёт 6 ч)')}</div>
              <h4 class="second">Хвост лога</h4>
              <div class="kv">{nb('третья попытка из трёх, 08:41')}</div>
              <pre class="log">stage run structure --change board-context
fatal: worktree .foundry/wt/board-context is locked
  by feat/orb-loader since 08:41
retry 3/3 failed — stage paused</pre>
              <div class="insp-more">Открыть лог стадии целиком</div>
            </div>
            <div class="actionbar">
              <div class="btns">
                <span class="btn secondary">Открыть «Орб-лоадер»</span>
                <span class="btn primary">Повторить стадию <kbd>⌘R</kbd></span>
              </div>
            </div>
          </aside>'''

# Инспектор ХОДА АГЕНТА. Половина доски — девять карточек из восемнадцати —
# живёт в этом состоянии, и до сих пор оно было единственным, у которого
# инспектора не нарисовано вовсе: заглянуть внутрь идущей стадии, увидеть
# прогресс и остановить прогон было неоткуда. Хуже: доли «4 из 7» сняли
# с карточки под обещание «прогресс по задачам живёт в инспекторе, где есть
# место назвать единицу», а места этого на экране не было ни одного — величину
# убрали, обещанного адреса не дали.
# Здесь же закрывается и вопрос «кто виноват»: карточка, которая шесть часов
# держит рабочее дерево и через это остановила соседний change, помечать
# на доске нечем — чип отвечает на «чей ход», а «блокирует» это не ход,
# а отношение двух change’ей. Отношение живёт там, где его можно прочесть
# словами, — в инспекторе обоих участников.
TASKS = [
 ('done', 'Рой частиц на Metal'),
 ('done', 'Цикл 54 с и семьи цветов'),
 ('done', 'Тень на рое'),
 ('done', 'Кадрирование на hero-экранах'),
 ('live', 'Разлёт финального экрана'),
 ('wait', 'Пресет для слабых GPU'),
 ('wait', 'Замер кадра на 60 Гц'),
]
TASKS_DONE = sum(1 for st, _ in TASKS if st == 'done')

def tasklist():
    rows = ''.join(f'<div class="tk {st}"><span class="tk-n">{i}</span>'
                   f'<span class="tk-t">{nb(t)}</span></div>'
                   for i, (st, t) in enumerate(TASKS, 1))
    return f'<div class="tasks">{rows}</div>'

INSP_LIVE = f'''<div class="board-scrim"></div>

          <aside class="overlay-insp">
            {insp_head('Орб-лоадер', 'feat/orb-loader',
                       'Стадия 7 из 8 — <b>Implement</b>. Идёт 6 ч.',
                       'Вашей очереди не занимает: ход агента')}
            <div class="artifact">
              <h4>Задачи</h4>
              <div class="kv">{nb(f'{len(TASKS)} задач поставлено на Plan, принято {TASKS_DONE}')}</div>
              {tasklist()}
              <div class="insp-more">{nb('Открыть лог стадии целиком')}</div>
            </div>
            <div class="actionbar">
              <div class="act-cost">{nb('От вас сейчас ничего не нужно: когда стадия кончится, change встанет в срез «Ваш ход». Рабочее дерево .foundry/wt/orb-loader занято этой стадией — из-за неё стоит «Контекст доски».')}</div>
              <div class="btns">
                <span class="btn secondary">Остановить стадию <kbd>⌘.</kbd></span>
              </div>
            </div>
          </aside>'''

f27 = f'''<div class="pipe-pair">
      <div class="pipe-case">
        <div class="pipe-case-cap">{nb('Спрос — вопросы: тред и поле ответа')}</div>
        {frame(f"""{rail()}

        {sidebar(SREZ, projects())}

        <div class="pane list">
          {pipebar()}
          {board_html(sel_title='Скоупы бинов Spark')}
          {INSP_ASK}
        </div>""", cls='win ovl tall')}
      </div>
      <div class="pipe-case">
        <div class="pipe-case-cap">{nb('Спрос — встало: причина, лог и повтор')}</div>
        {frame(f"""{rail()}

        {sidebar(SREZ, projects())}

        <div class="pane list">
          {pipebar()}
          {board_html(sel_title='Контекст доски')}
          {INSP_STALL}
        </div>""", cls='win ovl tall')}
      </div>
      <div class="pipe-case">
        <div class="pipe-case-cap">{nb('Спрос — никакого: ход агента, задачи и остановка')}</div>
        {frame(f"""{rail()}

        {sidebar(SREZ, projects())}

        <div class="pane list">
          {pipebar()}
          {board_html(sel_title='Орб-лоадер')}
          {INSP_LIVE}
        </div>""", cls='win ovl tall')}
      </div>
    </div>'''

CAP27 = (f'<b>Инспектор отвечает на тот спрос, который написан на карточке.</b> Он был один на всё — приёмка артефакта, — хотя из {SREZ["wait"]} янтарных чипов доски три говорят «вопросы», а {SREZ["stop"]} коралловых не говорят про артефакт вовсе. Человек, нажавший карточку с чипом «ждёт 26 ч» и значком реплики, попадал на экран, где нет ни вопроса, ни поля ответа, зато есть «Принять»: кнопка, которой в этом спросе принимать нечего. '
         '<b>Вопросы — переписка, а не дифф.</b> Они пронумерованы, потому что отвечать на них будут по одному; строка внизу называет цену молчания — стадия стоит, пока вы не ответите, и это единственная причина, по которой change сутки не двигался. Число вопросов ушло с чипа сюда: на доске сравнивают срок, в треде — читают вопросы. '
         '<b>У вставшего первым делом спрашивают «почему».</b> Причина названа словами, под ней — хвост лога, из которого она взята, и он же показывает, что виновник рядом на этой же доске: дерево держит другой change. Кнопка называет действие, а не намерение: «Повторить стадию». '
         f'<b>Шапка одна на все три спроса</b> и несёт то, чего не было ни в одном: выход (<code>Esc</code>) и место в очереди — «{queue_pos("Скоупы бинов Spark")}». Клавиша в шапке стоит при слове, а не вместо него: «⌥←» без подписи называет способ, а не действие, и узнать его можно было только наведением. Разбирают не карточку, а очередь; инспектор, умеющий только открыться и закрыться, заставлял {SREZ["wait"]} раз искать следующую карточку глазами.')

# 28 — крайние состояния, которых не было в кадре 24: длинный ТЕКСТ и старое
# ВРЕМЯ. Кадр 24 брал экстремумы по количеству — сорок карточек, тысяча
# в архиве, ноль во всю доску. Но два поля экрана меряются не штуками:
# комментарий к ревью меряется знаками, а снапшот при потере связи — минутами,
# и оба растут сами, без участия вёрстки.

# Настоящий текст, а не рыба: экстремум, набранный «жжж», ничего не проверяет —
# ни переносов, ни длины строки, ни того, влезает ли мысль в отведённое место.
REVIEW = [
 'Направление принимаю целиком, спорить по существу не о чем: тема одна, '
 'поверхности выше базы обесцвечены, цвет приходит чипом малой площади. '
 'Ниже — четыре места, где документ говорит меньше, чем нужно тому, кто '
 'будет по нему верстать, и одно, где он говорит неправду.',

 'Ступени. «Примерно через пять единиц светлоты» — это намерение, а не значение. «Примерно» '
 'нельзя проверить, и через месяц в макете будет шесть ступеней вместо '
 'четырёх, каждая по чьему-то глазу. Нужны четыре конкретных числа и запрет '
 'на пятое, записанный словами: наведение ступенью не считается, ниже базы '
 'уходит только выемка. Это в тексте есть, но стоит абзацем ниже определения '
 'и читается как пояснение, а не как правило.',

 'Текст. «Альфа-белый 92% / 70% / 56% / 44%» — четыре числа без единого имени. '
 'Называть их будут каждый раз заново и каждый раз по-разному. Дайте им имена '
 'и покажите на каждом ту роль, ради которой ступень заведена: 44 % '
 'существует только для выключенного, и пока это не сказано, им будут '
 'набирать подписи.',

 'Чипы — здесь неправда. Сказано, что ход агента цвета не получает, потому '
 'что это норма, а не событие. Но фон нейтрального чипа стоит на карточке '
 'с отношением 1,3:1 — от карточки он не отличается ничем, кроме текста '
 'внутри. «Не получает цвета» на деле означает «не читается как чип». Либо '
 'поднимайте фон до ступени, которую видно, либо признайте, что нейтрального '
 'чипа нет вовсе и ход агента кодируется отсутствием чипа. Второе честнее.',

 'Тени. «Отделение даёт свет по кромке в один пиксель» — принято и проверено. '
 'А вот «тёмное гало остаётся там, где под ним живой рой частиц» описывает '
 'онбординг: на рабочем экране роя нет ни на одном кадре. Уберите фразу или '
 'скажите прямо, что на доске тёмных теней не бывает ни одной. Иначе первый '
 'же оверлей приедет с тенью в 64 пикселя, она окажется невидимой, и никто '
 'этого не заметит — документ её вроде бы разрешил.',

 'Состояния складываются — верно и важно, но проверить это по документу '
 'нельзя. Нужна таблица «выбрано × наведено × фокус», восемь клеток, и в '
 'каждой сказано, какой канал занят. Иначе первый, кто заведёт девятое '
 'состояние, займёт чужой канал и узнает об этом от тестировщика.',

 'Выемка названа, но не описана. «Место, откуда карточку вынули» — это '
 'единственное, что уходит ниже базы, то есть ступень, которой в лестнице '
 'нет. Чем она отличается от пустой колонки, в документе не сказано ни '
 'словом, а различать их придётся: пустая колонка — норма и хорошая новость, '
 'выемка — след незаконченного перетаскивания и живёт полсекунды.',

 'Про кромочный свет нет ни одного числа. «Свет по кромке в один пиксель» — '
 'это про ширину, а не про яркость, и яркость тут как раз важнее: на '
 'карточке и на оверлее она разная, иначе оверлей не отделяется от того, '
 'что под ним. Дайте два значения и скажите, от чего они зависят — от '
 'ступени поверхности или от того, что лежит ниже.',

 'Отдельно — порядок чтения. Документ начинается с поверхностей и кончается '
 'состояниями, а верстают наоборот: сперва спрашивают «какое это состояние», '
 'потом «на какой оно поверхности». Переставьте разделы или дайте в начале '
 'сводку на страницу: 214 строк подряд читают один раз, а возвращаются в них '
 'по десять раз в неделю.',

 'Возвращаю. Блокирующий пункт один — чипы; остальное правится без второго '
 'круга.',
]
REVIEW_LEN = sum(len(p) for p in REVIEW) + len(REVIEW) - 1
# Экстремум объявлен в 3 000 знаков — значит, он и должен быть не меньше,
# а число под полем считает Python, а не рука. Рукописное число рядом
# с вычислимым — то же враньё, что рукописная высота кадра.
assert REVIEW_LEN >= 3000, REVIEW_LEN
VISIBLE_TAIL = 2  # сколько последних абзацев видно над кареткой

INSP_LONG = f'''<div class="board-scrim"></div>

          <aside class="overlay-insp">
            {insp_head('Токены тёмной темы', 'feat/dark-tokens',
                       'Стадия 3 из 8 — <b>Design</b>. Дальше Structure.',
                       queue_pos('Токены тёмной темы'))}
            <div class="artifact">
              <h4>Артефакт</h4>
              <div class="kv">design.md, 214 строк</div>
              <p>Тема одна — тёмная. Поверхности выше базы <b>обесцвечены</b>: хрома фона тянет к себе тёплый акцент и делает его грязным.</p>
              <p>Текст — альфа-белый <code>92% / 70% / 56% / 44%</code>; цвет не идёт текстом, он приходит <b>залитым чипом</b> малой площади.</p>
            </div>
            <div class="actionbar">
              <div class="cf-block">
                <div class="cf-head">Комментарий к ревью<span class="cf-to">{nb('уйдёт агенту, если вернуть; в PR, если принять')}</span></div>
                <div class="comment-long foc">
                  {''.join(f'<p>{nb(p)}</p>' for p in REVIEW[-VISIBLE_TAIL:-1])}
                  <p>{nb(REVIEW[-1])}<span class="caret"></span></p>
                </div>
                <div class="cf-meta">{nb(f'{num(REVIEW_LEN)} знаков, видна концовка — поле прокручено к каретке.')}<span class="cf-draft"><kbd>Esc</kbd> {nb('свернёт инспектор: черновик сохранится и откроется вместе с этим change.')}</span></div>
              </div>
              <div class="act-cost">{nb('Приняв, вы запускаете Structure и отправляете комментарий в PR. Отмена доступна 10 с.')}</div>
              <div class="btns">
                <span class="btn secondary">Вернуть на доработку</span>
                <span class="btn primary">Принять <kbd>⌘⏎</kbd></span>
              </div>
            </div>
          </aside>'''

# Старение снапшота. Экран доращивает РОВНО ТЕ сроки, которые не могли кончиться
# без него: ответить на вопрос и снять change со стадии умеет только CLI,
# а CLI молчит — значит, «ждёт» и «встало» точно всё ещё ждут и стоят, и час
# простоя, прошедший при мёртвом ядре, это такой же час простоя. Ход агента,
# наоборот, мог кончиться в любую секунду: там число врало бы, и оно снято
# ещё в кадре 22 («нет связи»).
STALE = 160  # 2 ч 40 мин: снапшот 14:22, на часах 17:02

def fmt_age(m):
    # Суток в таблице длительностей канона (05-text, часть 5) нет: с, мин, ч.
    # Двадцать шесть часов — не «1 д»: доска сравнивает сроки вертикально,
    # а «1 д» и «3 ч» сравнивать нечем, между ними пропасть в округлении.
    if m >= 60:
        return f'{int(m // 60)} ч'
    return f'{int(m)} мин'

def fmt_span(m):
    """Возраст снапшота — единственное место, где срок называют двумя единицами:
    его не сравнивают с соседним, его вычитают из часов на стене."""
    return f'{m // 60} ч {m % 60} мин' if m % 60 else f'{m // 60} ч'

def grow(board, plus):
    out = []
    for name, cards in board:
        cs = []
        for kind, title, branch, move, text in cards:
            if move in ('wait', 'stall', 'fail'):
                text = f'{text.split()[0]} {fmt_age(age(text) + plus)}'
            cs.append((kind, title, branch, move, text))
        out.append((name, cs))
    return out

STALE_BOARD = grow(BOARD, STALE)

# Доращивание не имеет права переставить карточки местами: прибавка одна на
# всех, значит порядок «сверху самые давние» обязан уцелеть до знака.
for _n, _cs in STALE_BOARD:
    if _n == 'Готово':
        continue
    _a = [age(c[4]) for c in _cs if c[3] in ('wait', 'stall', 'fail')]
    assert _a == sorted(_a, reverse=True), (_n, _a)

def stale_board_html():
    cols = [column(n, undated_last(c), snapshot=True) for n, c in STALE_BOARD]
    cols.insert(-1, DONE_GAP_CELL)
    return (f'<div {board_style(len(STALE_BOARD))}>\n            '
            + '\n            '.join(cols) + '\n          </div>')

BANNER_STALE = f'''<div class="degrade old">
            <span class="dg-ic"><svg class="ic"><use href="#i-alert"/></svg></span>
            <span class="dg-tx"><b>{nb(f'foundry CLI не отвечает {fmt_span(STALE)}.')}</b> {nb('Снапшот сделан в 14:22, и с тех пор экран пробовал сам 8 раз, последний — в 17:01. Сроки ожидания на карточках доращены на это время: ответить на вопрос и снять change со стадии умеет только CLI, поэтому то, что ждало вас в 14:22, ждёт и сейчас. Сроки работы агента сняты — она могла кончиться в любую минуту, и карточки без срока стоят в конце своих колонок.')}
              <span class="dg-hint">{nb('Отвечает ли foundry CLI, скажет')} <code>foundry doctor</code> {nb('в терминале.')}</span></span>
            <span class="btn secondary">Проверить снова</span>
          </div>'''

f28 = f'''<div class="pipe-pair">
      <div class="pipe-case">
        <div class="pipe-case-cap">{nb(f'Текст: комментарий к ревью на {num(REVIEW_LEN)} знаков')}</div>
        {frame(f"""{rail()}

        {sidebar(SREZ, projects())}

        <div class="pane list">
          {pipebar()}
          {board_html(sel_title='Токены тёмной темы')}
          {INSP_LONG}
        </div>""", cls='win ovl tall')}
      </div>
      <div class="pipe-case">
        <div class="pipe-case-cap">{nb(f'Время: тот же снапшот {fmt_span(STALE)} спустя')}</div>
        {frame(f"""{rail()}

        {sidebar(SREZ, projects(), unknown=True)}

        <div class="pane list">
          {BANNER_STALE}
          {pipebar()}
          {stale_board_html()}
        </div>""")}
      </div>
    </div>'''

CAP28 = ('<b>Комментарий к ревью меряется не штуками, а знаками, и растёт сам.</b> Поле было нарисовано одной строкой-приглашением — то есть кадр молча обещал, что длиннее строки не пишут. Пишут: разбор чужого документа на 214 строк естественным образом выходит в три тысячи знаков, и на них вёрстка обязана не развалиться. '
         '<b>Поле растёт до предела и дальше прокручивается внутри себя.</b> Предел — не круглое число, а смысл: артефакт, который вы рецензируете, обязан остаться на экране. Поле, съевшее артефакт, заставляет писать вслепую, поэтому оно уступает первым. Затухание идёт по ВЕРХНЕЙ кромке поля: текст ушёл вверх, каретка внизу, и обрыв сверху — единственное, что об этом говорит. '
         '<b>У длинного текста назван адресат и названа судьба.</b> Три тысячи знаков не пишут в никуда: подпись поля говорит, куда они уедут при каждом из двух исходов, а строка под полем — что будет с ними при <code>Esc</code>. Черновик, потерянный по случайному нажатию, здесь дороже всего остального на экране. '
         '<b>Опасность видно, и она уже закрыта:</b> человек, написавший три тысячи знаков возражений, жмёт <code>⌘⏎</code> по привычке — и принимает. Кнопки не меняются местами и не меняют ролей (двигать цель под курсором нельзя), а страхует то же, что и всегда: приёмку можно отменить десять секунд, и цена названа рядом с кнопкой. '
         '<b>Снимок меряется минутами и тоже растёт сам.</b> «Снимок от 14:22» верно ровно две минуты; через два часа сорок минут эта строка требует от читателя посмотреть на часы и вычесть. Теперь у снапшота два числа — когда снят и сколько назад, — и сказано, что экран пробовал сам: кнопка «Проверить снова» на двухчасовом сбое иначе выглядит советом, которому уже восемь раз не повезло. '
         '<b>Экран доращивает ровно те сроки, которые не могли кончиться без него.</b> Ответить на вопрос агента и снять change со стадии умеет только CLI — он молчит, значит ждавшее в 14:22 ждёт и сейчас, и «ждёт 25 мин» честно становится «ждёт 3 ч». Ход агента, наоборот, мог кончиться в любую секунду: там число снято совсем. Одно и то же событие — потеря связи — по-разному действует на две шкалы, и экран это различает. '
         '<b>Чем дольше нет связи, тем конкретнее совет.</b> На свежем сбое «Проверить снова» — весь разумный ответ. На двухчасовом он уже не ответ, и рядом названа команда, которая скажет, жив ли демон. Экран не чинит себя сам и не делает вид, что починит.')

# 29 — две системные настройки, которые меняют экран сильнее любых фикстур.
# Кадр собирается ИЗ ТОГО ЖЕ инспектора и той же доски, что кадр 21: сравнивать
# можно только одно и то же, а нарисованная отдельно «версия для доступности»
# через месяц разойдётся с рабочей и никто не заметит.
def a11y_win(mode):
    return frame(f"""{rail()}

        {sidebar(SREZ, projects())}

        <div class="pane list">
          {pipebar()}
          {board_html(sel_title='Токены тёмной темы')}
          {INSP}
        </div>""", cls=f'win ovl tall {mode}')

f29 = f'''<div class="pipe-pair">
      <div class="pipe-case">
        <div class="pipe-case-cap">{nb('Системная настройка «Увеличить контраст»')}</div>
        {a11y_win('hc')}
      </div>
      <div class="pipe-case">
        <div class="pipe-case-cap">{nb('Системная настройка «Уменьшить прозрачность»')}</div>
        {a11y_win('rt')}
      </div>
    </div>'''

CAP29 = ('<b>Тема, построенная на четырёх ступенях по пять единиц светлоты и на разделении воздухом, — первый кандидат на то, чтобы развалиться, когда система попросит кромки.</b> Обе настройки живут в системных настройках macOS, включены у части людей постоянно, и проверить экран под ними нельзя, глядя на свой монитор при своей яркости. Кадр собран из того же инспектора и той же доски, что кадр 21: сравнивать можно только одно и то же. '
         '<b>Увеличенный контраст возвращает кромки ровно туда, где разделял воздух:</b> плиты, карточки, оверлей, выбранная строка сайдбара. Третья ступень текста поднимается до второй, выключенная — до третьей. И здесь в полный рост вылезает то, что на почти-чёрном было сказано вполголоса: тень не разделитель. Она не работает как разделитель и в обычном режиме, а при этой настройке обязана уступить место сплошной линии — иначе оверлей отделяет от доски ничто. '
         '<b>Уменьшенная прозрачность почти не меняет картинку — и это хороший знак.</b> Альфа-заливки под текстом становятся сплошными той же светлоты, а светлоту им и подбирали: если бы после замены что-то заметно поехало, значит, заливка держалась на просвечивающем фоне, а не на своём цвете. Единственная настоящая потеря — скрим. Он становится непрозрачным, и инспектор перестаёт быть слоем над доской: он слой над одной карточкой, той самой, ради которой открыт. Обещание «карточка остаётся там, где на неё смотрел глаз» держится буквально в единственном пункте, который тут можно удержать. '
         '<b>Альфа-белый текст полупрозрачностью не считается.</b> Он лежит на фоне известного цвета и равен сплошному — настройка его не касается, и подменять его на hex ради галочки значит завести вторую палитру, которая разойдётся с первой. '
         '<b>Чего не меняет ни одна из настроек:</b> ширины дорожки, шва перед «Готово», флага канваса, порядка карточек и словаря цветов. Настройка доступности имеет право добавить кромку и поднять контраст — и не имеет права перекроить композицию: человек, включивший её, работает с теми же людьми на том же экране.')

# 30 — окно сжато до минимума. Минимум не выдуман, а посчитан из тех же
# констант, которыми живёт доска: поля окна, рейл, сайдбар, зазоры между
# плитами и плита канваса на три дорожки, шов и «Готово» со своими полями.
# Ни одно число здесь не написано рукой — все они уже стоят выше.
MIN_RAIL, MIN_SIDE, MIN_LANES = 76, 214, 3
MIN_CANVAS = (MIN_LANES + 1) * LANE + SEAM + (MIN_LANES + 1) * GAP + 2 * BOARDPAD
MIN_WIN = 2 * WINPAD + MIN_RAIL + GAP + MIN_SIDE + GAP + MIN_CANVAS
assert CANVAS == 9 * LANE + SEAM + 9 * GAP, CANVAS
assert MIN_WIN == 998, MIN_WIN

# Ширина плавающего инспектора — не из головы: она стоит в слое переопределений
# (правка 65), и то же число проверяет flags.py у настоящего элемента. Здесь оно
# нужно, чтобы посчитать, сколько дорожек оверлей закрыл бы на минимуме, —
# а не написать это число рукой и разойтись с вёрсткой на следующей правке.
INSP_W = 440
_left = MIN_CANVAS - WINPAD - INSP_W          # левая кромка оверлея на плите
_lanes = [BOARDPAD + k * (LANE + GAP) for k in range(MIN_LANES)]
_lanes.append(BOARDPAD + MIN_LANES * (LANE + GAP) + SEAM - 2 * GAP)
MIN_HIDDEN = sum(1 for x in _lanes if x + LANE > _left)
MIN_LEFT = len(_lanes) - MIN_HIDDEN

f30 = f'''<div class="pipe-pair">
      <div class="pipe-case">
        <div class="pipe-case-cap">{nb(f'Минимум окна — {MIN_WIN} px: три стадии, шов и «Готово»')}</div>
        {frame(f"""{rail()}

        {sidebar(SREZ, projects())}

        <div class="pane list">
          {pipebar(compact=True)}
          {board_html(scrollx=True)}
        </div>""", cls='win min', style=f'width:{MIN_WIN}px')}
      </div>
      <div class="pipe-case">
        <div class="pipe-case-cap">{nb('На минимуме инспектор перестаёт быть слоем и занимает канвас')}</div>
        {frame(f"""{rail()}

        {sidebar(SREZ, projects())}

        <div class="pane list">
          {pipebar(compact=True)}
          {board_html(sel_title='Токены тёмной темы', scrollx=True)}
          {INSP}
        </div>""", cls='win min ovl', style=f'width:{MIN_WIN}px')}
      </div>
    </div>'''

CAP30 = (f'<b>Минимум не выдуман, а посчитан из тех же констант, которыми живёт доска:</b> {MIN_RAIL} рейл, {MIN_SIDE} сайдбар, плита канваса на три дорожки, шов и «Готово», зазоры по {GAP} — {MIN_WIN} px, и уже. Три дорожки — не круглое число: доска отвечает на вопрос «чей ход», а взгляд собирает состояние пайплайна минимум из «до · сейчас · после». На двух дорожках это уже не доска, а список. '
         '<b>Дефицит ширины забирает канвас, и только он.</b> Рейл сузить нечем — он уже минимален, значок со словом; сайдбар — пульт, а обрезанный пульт хуже отсутствующего, и сворачиваться ему запрещено решением о каркасе. Канвас уступает первым по единственной причине, которая тут есть: он один умеет ехать вбок, ничего не теряя. Дорожка при этом остаётся {LANE} — та же карточка того же размера, что на полном окне; подгонять число колонок под ширину доска не начинает и на минимуме. Это проверяет <code>flags.py</code> вместе с остальными досками. '
         '<b>«Готово» остаётся прибитым к правому краю,</b> и затухание на его левой кромке говорит то же, что на десятистадийном пайплайне: между видимой стадией и корзиной спрятаны ещё. Слева не спрятано ничего — доска показана с начала, и первый столбец стоит на флаге канваса. '
         f'<b>Инспектор на минимуме перестаёт быть слоем.</b> Оверлей шириной {INSP_W} на канвасе в {MIN_CANVAS} закрыл бы {MIN_HIDDEN} дорожки из {len(_lanes)}, оставив от доски одну, и обещание «доска не пересобирается, карточка остаётся видимой» перестало бы выполняться вовсе — а обещание, которое держится через раз, хуже, чем не данное. Поэтому он занимает канвас целиком и становится видом, а не слоем: доска под ним не исчезает, она ждёт, и <code>Esc</code> возвращает её ровно туда же. Скрим при этом снят: затемнять нечего, а тёмная плёнка поверх пустоты — украшение. '
         '<b>Что не меняется ни на пиксель:</b> ширина дорожки, шов, флаг канваса, порядок карточек, словарь цветов и высота карточки. Сужение окна — не повод для другой композиции: человек, дотянувший окно до минимума, работает с той же доской.')

# 23 — лист состояний. Собирается ИЗ ТЕХ ЖЕ функций, что и доска: рукописная
# калька рано или поздно расходится с экраном, и тогда врёт именно она.
SAMPLE = ('feature', 'Токены тёмной темы', 'feat/dark-tokens', 'wait', 'ждёт 12 мин')

def cell(stage, lab, cls=''):
    return (f'<div class="spec-cell {cls}"><div class="spec-stage">{stage}</div>'
            f'<div class="spec-lab">{lab}</div></div>')

def row(cap, cells):
    return (f'<div class="spec-row"><div class="spec-cap">{nb(cap)}</div>'
            f'<div class="spec-set">{"".join(cells)}</div></div>')

def sec23():
    cs = card
    r1 = row('Карточка change', [
      cell(cs(*SAMPLE), '<b>Покой</b>Ни бордера, ни тени: плашка на ступень выше плиты — этого хватает.'),
      cell(cs(*SAMPLE, state='hov'), '<b>Наведение</b>Тело светлеет на ступень и получает свет по верхней кромке. Ни рамки, ни подъёма: строка ряда не должна дрожать.'),
      cell(cs(*SAMPLE, state='act'), '<b>Нажата</b>Темнее покоя на ступень и без канта. Палец вдавил карточку, а не подсветил её.'),
      cell(cs(*SAMPLE, sel=True), '<b>Выбрана</b>Ультрамарин внутренней тенью 2 px и подложка. Выбор держится, когда курсор ушёл, — поэтому он цветной, а наведение нет.'),
      cell(cs(*SAMPLE, state='foc'), '<b>Фокус с клавиатуры</b>Кольцо снаружи, не внутри: тогда фокус и выбор видны одновременно и не спорят.'),
      cell(cs(*SAMPLE, state='drag'), '<b>Поднята</b>Тень 40 px и наклон 1,6°. Карточка физически «в руке», а не просто подсвечена.'),
      cell(cs(*SAMPLE, state='fresh'), '<b>Только что изменилась</b>Светлый кант на 2 с. Доску двигает агент, пока вы смотрите в другое место, — иначе изменение придётся искать глазами.'),
      cell('<div class="kb-slot"></div>', '<b>Место приземления</b>Не пунктир, а выемка: то же место, откуда карточку вынули. Тёмное на тёмном читается как углубление.'),
      cell(f'<div class="drag-no">{cs(*SAMPLE, state="drag")}'
           f'<span class="no-badge"><svg class="ic ic-s"><use href="#i-no"/></svg></span></div>',
           '<b>Над зоной, куда нельзя</b>Выемка не появляется, колонка не подсвечивается, а у карточки в руке — знак «нельзя». Интерфейс не обещает того, чего не сделает.'),
    ])
    si = lambda c, label, cnt: (f'<div class="side-item bare {c}"><span class="grow">{label}</span>'
                                f'<span class="count">{cnt}</span></div>')
    # ДОРОЖКА ЛИСТА = СОСТОЯНИЕ. Сетка обещает сравнение по вертикали, и до
    # этой правки обещание не выполнялось: «фокус» карточки стоял в пятой
    # дорожке, «фокус» кнопки — в четвёртой, и глаз честно ставил фокус против
    # «идёт приёмка». Первые пять дорожек — общая лестница (покой, наведение,
    # нажат, выбран, фокус), а ПУСТАЯ КЛЕТКА прямо говорит, что такого
    # состояния у этого объекта нет. Заодно разъехались объекты, которые
    # стояли одним рядом: главная и вторичная кнопки, пункт сайдбара и значок
    # рейла — у каждого своя лестница, и покой вторичной больше не встаёт
    # в дорожку «идёт приёмка» главной.
    HOLE = '<div class="spec-cell hole"></div>'
    r2 = row('Пункт сайдбара', [
      cell(si('', 'Ваш ход', SREZ['wait']), '<b>Покой</b>Текст вторичный, число третьей ступенью: оно уточняет строку, а не спорит с ней.'),
      cell(si('hov', 'Ваш ход', SREZ['wait']), '<b>Наведение</b>Подложка вдвое слабее выбранной — чтобы их нельзя было спутать.'),
      cell(si('act', 'Ваш ход', SREZ['wait']), '<b>Нажат</b>Подложка гаснет: то же правило, что у карточки.'),
      cell(si('sel', 'Ваш ход', SREZ['wait']), '<b>Выбран</b>Текст белеет, подложка сплошная. Цвет не нужен: позиция и вес уже сказали всё.'),
      HOLE,
    ])
    rl = lambda c: (f'<span class="rl {c}"><svg class="ic"><use href="#i-inbox"/></svg>'
                    f'<span class="rl-tx">Инбокс</span></span>')
    r2b = row('Значок рейла', [
      cell(rl(''), '<b>Покой</b>Значок всегда белый штрих: цвет на этом экране занят состоянием change’а, и раздавать его разделам значит завести вторую шкалу теми же красками.'),
      cell(rl('hov'), '<b>Наведение</b>Та же подложка, что у пункта сайдбара: правило одно на оба пульта.'),
      cell(rl('act'), '<b>Нажат</b>Подложка уходит ниже плиты — гаснуть плоскому значку нечем.'),
      cell(rl('sel'), '<b>Выбран</b>Подложка сплошная, подпись белеет. Счётчика на значке нет: числа, которое он бы показывал, в модели нет, а нарисованное состояние без источника — обещание, которого продукт не выполнит.'),
      HOLE,
    ])
    b = lambda c, t: f'<div class="btn-set"><span class="btn {c}">{t}</span></div>'
    r3 = row('Главная кнопка', [
      cell(b('primary', 'Принять'), '<b>Покой</b>Единственный ультрамарин на экране кроме выбора.'),
      cell(b('primary hov', 'Принять'), '<b>Наведение</b>Свет по верхней кромке, а заливка — на ступень ГЛУБЖЕ. Светлеть ей нельзя: белой подписи на ультрамарине 5,13:1, и осветление роняет её до 4,19 — под порог. Замерено, а не на глаз.'),
      cell(b('primary act', 'Принять'), '<b>Нажата</b>Ещё глубже: у кнопки обе ступени идут в одну сторону. 7,74:1.'),
      HOLE,
      cell(b('primary foc', 'Принять'), '<b>Фокус с клавиатуры</b>То же кольцо, что у карточки, — правило одно на все объекты.'),
      cell('<div class="btn-set"><span class="btn primary load"><span class="spin"></span>Принимается…</span></div>',
           '<b>Идёт приёмка</b>Кнопка занята собой, а не гаснет: пропавшая надпись заставила бы гадать, ушёл ли клик. Второй раз нажать нельзя.'),
      cell(b('primary dis', 'Принять'),
           '<b>Недоступна</b>Заливка уходит в нейтраль: цвет действия там, где действия нет, — обещание рукой.'),
      cell(b('primary dis hov', 'Принять'),
           '<b>Она же под курсором</b>Ничего не происходит и не должно: подсветить недоступное — соврать рукой. Почему нельзя, говорит подсказка рядом, а не сама кнопка.'),
    ])
    r3b = row('Вторичная кнопка', [
      cell(b('secondary', 'Вернуть на доработку'), '<b>Покой</b>Обводка, а не заливка: два залитых пятна спорили бы за главное действие.'),
      cell(b('secondary hov', 'Вернуть на доработку'), '<b>Наведение</b>Кромка светлеет, заливки не появляется: вторичная не имеет права на наведении стать главной.'),
    ])
    r4 = row('Поле комментария', [
      cell('<div class="comment-field">Комментарий к ревью…</div>',
           '<b>Покой</b>Утоплено внутренней тенью — на тёмном это единственный честный способ сказать «сюда вводят».'),
      HOLE, HOLE, HOLE,
      cell('<div class="comment-field foc"><span class="cf-tx">Верните чипы к одному механизму</span><span class="caret"></span></div>',
           '<b>Фокус</b>То же кольцо, что у карточки и кнопки. Утопленность остаётся: фокус добавляется к состоянию, а не заменяет его.'),
      cell('<div class="field-case"><div class="comment-field err">Комментарий к ревью…</div>'
           '<div class="field-err">Возвращая на доработку, объясните, что править: без этого агент начнёт с того же самого.</div></div>',
           '<b>Ошибка</b>Кораллом обведено само поле, а текст говорит, что случилось и что делать. Красной надписи «обязательное поле» здесь нет: она называет правило, а не выход.'),
    ])
    note = ('<div class="spec-note"><b>Время.</b> Всё, что меняется на наведении, входит за 0,14 с и выходит за 0,70 с — '
            'быстро под рукой, медленно вслед за ней. Нажатие мгновенно (0,06 с), возврат — 0,20 с. '
            '<b>Порядок силы:</b> нажатие слабее наведения, наведение слабее выбора, выбор слабее фокуса, фокус слабее поднятой карточки. '
            'Ни одно состояние не занимает силу соседнего, поэтому они складываются: карточку можно одновременно выбрать, навести и держать на ней фокус — и все три видно.</div>')
    body = (f'<style>.spec-stage .kb-card,.spec-stage .kb-slot{{width:{LANE}px}}</style>'
            f'<div class="win spec-win"><div class="spec">{r1}{r2}{r2b}{r3}{r3b}{r4}{note}</div></div>')
    cap = ('<b>Почему выемка, а не пунктир.</b> Пунктирная рамка — линия, а линий на этом экране нет ни одной: расстояния и плоскости справляются сами. '
           'Выемка говорит то же самое честнее — карточка вынута отсюда и сюда встанет. '
           '<b>Почему у наведения нет цвета.</b> Цвет на этом экране означает состояние change’а, а не положение курсора; подсветить наведение янтарём значит соврать. '
           'Наведение меняет только светлоту — единственный канал, который ничего не значит в модели данных. '
           '<b>Почему у карточки наведение светлеет, а у кнопки темнеет.</b> Общий язык у них один — свет по верхней кромке; расходятся только заливки, и по делу. '
           'У карточки заливка — ступень поверхности, и «ближе» на ней значит светлее. У кнопки заливка — цвет действия, а белой подписи на ультрамарине уже 5,13:1: осветлив её, экран роняет подпись до 4,19 — под порог. '
           'Поймал это не глаз (глазу как раз нравилось: кнопка стала ярче), а промер каждой пары «текст на своём фоне» на всех кадрах разом. '
           '<b>Почему лист собран из тех же функций, что и доска.</b> Рукописная калька расходится с экраном на первой же правке, и дальше врёт именно она: '
           'на прошлой сборке карточки здесь ещё носили снятый значок вида и чип старой палитры.')
    return sec('23 — состояния', 'Как интерфейс отвечает на руку',
      'Состояния — не отделка, а часть смысла: пока их нет, экран мёртв, и любая доводка цвета идёт вслепую. '
      'Здесь весь набор ответов интерфейса на одном листе, чтобы они читались как одна семья, а не собирались по чужим дефолтам в каждом виджете.',
      body, cap)

# ── сборка ───────────────────────────────────────────────────────────────────
CAP20 = ('<b>Одна карточка — один чип.</b> Раньше подвал карточки нёс две случайные величины подряд: возраст, объём диффа, номер PR, дату приёмки. Колонку читают вертикально, сравнивая одинаково стоящие числа, — а сравнивать было нечего. Теперь на каждой карточке ровно один чип, и он отвечает на единственный вопрос доски: <b>чей ход</b>. Янтарный — ваш, коралловый — ничей (встало или упало), серый — принято. Ход агента цвета не получает вовсе: он большинство, а красить большинство значит не покрасить ничего. Вопрос агента теперь тоже «ваш ход»: change, сутки стоящий с тремя незаданными вопросами, — самый дорогой простой в продукте, и раньше он выглядел на доске спокойнее, чем ревью, ждущее двенадцать минут. '
         f'<b>Числа не размножаются.</b> Шапка «Июль 2026» снята целиком: месяц не сущность продукта, дат у карточек нет, «осталось 16 дней» ни с чем не связано, — а «17 в работе» было третьей копией числа, уже стоявшего в сайдбаре и на вкладке. Счётчики вкладок сняты по той же причине. Осталось одно место, где считают: срез, и он считает ровно то, что видно на доске, — пересчитав чипы глазами, читатель обязан получить те же {SREZ['wait']}, {SREZ['live']} и {SREZ['stop']}. Строка «Всё в работе» числа не носит: это состояние «фильтр снят», а не четвёртая величина, и своё значение она уже сложила из трёх строк ниже — и повторила строкой «foundry-desktop {PROJ}», где счётчик проекта считает ту же работу — только всю, а не одной вкладки: {IN_WORK} на этой доске плюс числа соседних вкладок. Принятые в него не входят, иначе он спорил бы с доской, где они свёрнуты в «Готово». '
         '<b>Подпись колонки стоит рядом со своим числом,</b> а не прижата к правому краю дорожки: прижатое число оказывалось в двенадцати пикселях от заголовка СОСЕДНЕЙ колонки и в сотне — от своего собственного. Ряд чисел читался красиво и группировал неверно; близость важнее линейки. '
         '<b>Воркtree стал колонкой как все.</b> Он был свёрнут в тридцатипиксельную полоску не по смыслу, а чтобы девять колонок влезли в канвас: карточку нельзя было ни увидеть, ни открыть, ни сдвинуть, а в счёт она входила. '
         '<b>Значок вида с карточки снят:</b> он повторял префикс ветки, который виден всегда, и отнимал восемнадцать пикселей у заголовка в дорожке шириной {LANE} — «Инспектор по требованию» срезало на последней букве. Внутри карточки остался ровный флаг из трёх строк, а ветка и чип прижаты парой к низу, чтобы сквозь весь ряд шли три горизонтали, а не плавали вслед за длиной заголовка.')

CAP21 = ('<b>Объект не меняет личность при открытии.</b> Инспектор звался веткой <code>feat/dark-tokens</code>, хотя кликали по карточке «Токены тёмной темы»: иерархия переворачивалась ровно на том объекте, на который только что смотрел глаз. Теперь имя главное здесь и там, ветка — подпись. '
         '<b>Степпер снят.</b> Восемь безымянных кружков не говорили, что такое стадия 6, а строка под ними переживала их удаление без потерь. Заодно ушли синий узел «текущая» и зелёные кольца «пройдено» — состояние подавалось цветом контура, хотя закон тёмной темы требует чипа. '
         '<b>Карточка-источник действительно выбрана</b> — раньше она была утоплена скримом наравне с остальными, и обещание «якорь остаётся там, где на него смотрел глаз» на рендере не подтверждалось. Скрим больше не обесцвечивает доску: <code>saturate(0.7)</code> превращал янтарный чип в оливу — ровно ту грязь, ради устранения которой сделан кандидат. '
         '<b>«Открыть design.md целиком»</b> — потому что принимать 214 строк, увидев начало, значит превращать ревью в ритуал.')

CAP25 = (f'<b>Число колонок задаёт модель, а не окно.</b> Хотфикс — три стадии, фича в одном сервисе — восемь, фича в нескольких сервисах — десять; в модели это разные пайплайны, и подгонять их под одну ширину значит врать про длину пути. Три дорожки не растягиваются на весь канвас поодиночке: они держат ту же ширину, что и на восьмистадийной доске, — иначе один и тот же change менял бы размер при переключении вкладки. '
         f'<b>Ниже {LANE} пикселей дорожка не сжимается.</b> На десяти стадиях доска едет вбок и обрывается затуханием у правой кромки: пусть человек прокрутит, чем читает кашу из переносов по слогам. Затухание, а не обрез по кромке плиты, — единственный способ сказать «дальше есть ещё», не тратя на это ни строки текста. '
         '<b>Подпись вкладки считает стадии честно</b> — «CRISPY, 8 стадий», а не девять: девятая колонка «Готово» стадией не является. Что она не стадия, говорят её имя, серые чипы, «+N раньше» и шов вчетверо шире обычного промежутка. Шов сделан отдельной дорожкой грида, а не отступом внутри колонки: отступом его уже пробовали, и он съедал ширину карточек этой же колонки — подпись уходила в многоточие ровно в ней одной. Остаток от деления канваса тоже уходит в шов, поэтому поля доски слева и справа равны.')

CAP22 = (f'<b>Экран не выдаёт незнание за факт.</b> Раньше при оборванной связи сайдбар уверенно писал «Ход агента 0» — это не факт, а незнание: агенты, возможно, работают, просто сказать об этом некому. Теперь прочерк стоит ровно у одной строки — «Ход агента»: чем занят агент, знать неоткуда, а его чипы на карточках сменились на «нет связи», и карточки без срока ушли в конец своих колонок: закон «сверху самые давние» иначе перестал бы работать молча. Два других счётчика остаются числами, и это не полумера: янтарные и коралловые чипы со снапшота никуда не делись, их {SREZ['wait']} и {SREZ['stop']}, и прочерк на их месте спорил бы с доской, которую читатель видит. Гаснут только устаревшие карточки — «ждёт вас» и «встало» держат полную силу, потому что они правда и на снапшоте. '
         '<b>Доска не худеет при сбое</b> — она из снапшота, а снапшот не теряет карточек. В прошлой сборке при обрыве связи часть карточек молча исчезала, обучая ровно тому, чего баннер пытался избежать: считать увиденное полной картиной. '
         '<b>Красный, а не янтарный:</b> недоступное ядро и оборванный стрим — одна и та же поломка, и кодировать её двумя цветами значит развалить словарь.')

CAP24 = ('<b>Это кадр, на котором композиция обязана не развалиться.</b> Колонка на сорок карточек прокручивается внутри себя и обрывается затуханием, а не кромкой плиты: раньше сорок первая карточка просто исчезала под <code>overflow: hidden</code> без единого знака. Счётчики трёхзначные и с разрядкой. '
         '<b>Длинное имя обрезается многоточием, длинная ветка — тоже:</b> прежде ветка стояла под <code>text-overflow: clip</code> внутри карточки с <code>overflow: hidden</code>, то есть обрубалась посреди буквы — ровно тот «срез по букве», который в соседнем абзаце назван браком вёрстки. '
         '<b>Пустая колонка молчит.</b> Подписи в ней стояли и сняты: «в проекте нет активной работы» под колонкой Questions на доске с сорока двумя карточками — прямая неправда, а «ничего не ждёт вас» повторяет то, что и так видно по отсутствию чипов. Пустая колонка при непустой доске — хорошая новость, и звать в ней некуда. Слово нужно ровно в одном случае — когда пуста вся доска, и оно вынесено на второе окно кадра: там колонки стоят с нулями, чтобы было видно, куда встанет первый change, а зовёт одна кнопка.')

SEC = []
SEC.append(sec('20 — главный экран после онбординга',
  'Доска change’ей: чей ход — за один взгляд',
  'Полезное действие взято из канона дословно: «понять состояние пайплайна за один взгляд; сдвинуть change». Прошлая сборка отвечала на вопрос «что где лежит» и плохо отвечала на «чей ход» — взгляд собирал четыре числа из четырёх областей видимости, а самый застрявший change был единственным без всякого признака.',
  f20, CAP20))
SEC.append(sec('21 — тот же экран, инспектор по требованию',
  'Решение принимают, не теряя доски',
  'Инспектор приходит поверх по ⌘⌥I и уходит по Esc. Доска под ним не пересобирается, карточка-источник остаётся выбранной и видимой.',
  f21, CAP21))
SEC.append(sec('22 — foundry CLI не отвечает',
  'Снимок, который честно называет себя снапшотом',
  'Худшее, что может сделать экран при сбое, — продолжать выглядеть уверенно. Здесь он называет, что случилось, чем это грозит данным на экране, что стало недоступно и чего он про мир больше не знает.',
  f22, CAP22))
SEC.append(sec23())
SEC.append(sec('24 — экстремумы данных',
  'Сорок карточек, тысяча в архиве и ноль во всю доску',
  'Макет на удачных фикстурах ничего не доказывает. Здесь собраны величины, на которых вёрстка ломается первой: переполненная колонка, пустые колонки, четырёхзначные счётчики, имена и ветки, которые не помещаются, — и отдельным окном совсем пустая доска.',
  f24, CAP24))
SEC.append(sec('25 — пайплайны разной длины',
  'Три стадии и десять — та же доска',
  'Колонки доски равны стадиям выбранного пайплайна, а пайплайны в модели разной длины: хотфикс — три стадии, фича в одном сервисе — восемь, фича в нескольких сервисах — десять. Это значимая информация, а не край вёрстки, поэтому доска не подгоняет число колонок под ширину окна.',
  f25, CAP25))
SEC.append(sec('26 — срез применён',
  'Пульт, у которого видно нажатие',
  'Отдельной панели фильтров нет: срез в сайдбаре и есть фильтр. До сих пор он был нарисован только как четыре числа, и кадр умалчивал о главном — что происходит с доской, когда по числу нажали.',
  f26, CAP26))

# Доска каждого кадра обязана сойтись с той клеткой мира, которую показывает.
assert WORLD['foundry-desktop'][MAIN] == IN_WORK
assert WORLD['monorepo'][MAIN] == EX_WORK
assert WORLD['crispy-core']['Хотфикс'] == work(HOTFIX)
assert WORLD['crispy-core']['Фича в нескольких сервисах'] == work(MANY)
assert not WORLD['дизайн-система']

check_order(EXTREME, 'EXTREME')
check_order(BOARD, 'BOARD')
check_order(MANY, 'MANY')
check_order(HOTFIX, 'HOTFIX')

SEC.append(sec('27 — инспектор под спрос',
  'Вопросы, приёмка и разбор вставшего — три разных экрана',
  'Полезное действие экрана состоит из двух половин: «понять состояние за один взгляд» и «сдвинуть change». Первая была сделана, вторая — нет: доска звала к пяти действиям, а нарисовано было одно из трёх, и то не самое частое.',
  f27, CAP27))
SEC.append(sec('28 — экстремумы, которые растут сами',
  'Три тысячи знаков и снапшот двухчасовой давности',
  'Кадр 24 брал экстремумы по количеству — сорок карточек, тысяча в архиве, ноль во всю доску. Два поля экрана меряются не штуками: комментарий к ревью меряется знаками, а снапшот при потере связи — минутами. Оба растут без участия вёрстки, и оба до сих пор были нарисованы в самом удобном своём значении.',
  f28, CAP28))
SEC.append(sec('29 — системные настройки доступности',
  'Тот же экран под «Увеличить контраст» и «Уменьшить прозрачность»',
  'До сих пор экран проверяли на одном мониторе при одной яркости. Две системные настройки macOS меняют его сильнее, чем любые фикстуры: первая требует кромок там, где разделял воздух, вторая запрещает подложкам просвечивать. У темы, построенной на четырёх ступенях по пять единиц светлоты и на разделении воздухом, обе бьют в опору.',
  f29, CAP29))
SEC.append(sec('30 — окно сжато до минимума',
  'Кто уступает первым и на чём доска перестаёт быть доской',
  f'Последняя непроверенная строка раздела 10. Каркас обещает, что дефицит ширины забирает канвас и никто больше, а дорожка остаётся {LANE} на любом окне. Обещание проверяется единственным способом — окном минимальной ширины, посчитанной из тех же констант, а не подобранной на глаз.',
  f30, CAP30))

(SP/'part-canon.html').write_text((SP/'_sprite.html').read_text() + '\n'.join(SEC))
print('собрано; кадров:', len(SEC))
