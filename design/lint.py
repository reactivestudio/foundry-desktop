#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Линт дизайн-системы foundry-desktop.

Правило, которое не проверяется механически, не существует — доктрина проекта.
Здесь проверяется всё, что объявлено в design/parts/README.md, «Что проверяет линт».

Запуск из корня репозитория:  python3 design/lint.py
Выход 0 — чисто, 1 — есть нарушения.

Зависимостей нет — только стандартная библиотека Python 3 и design/build.py,
из которого берётся генерация: сравнивая её результат с файлами на диске,
линт ловит правку сгенерированного руками.
"""

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build

ROOT = build.ROOT

# Приёмная, кладбище и референсы — заведомо грязные зоны: кандидату можно быть
# неопрятным, в этом и смысл приёмной.
DIRTY_DIRECTORIES = [
    ROOT / "design" / "candidates",
    ROOT / "design" / "rejected",
    ROOT / "reference",
]

# Поблажка на сырые значения — пофайловая и с названной ценой, а не на папку.
# Папка «2-marks» была исключена целиком «потому что там canvas и WebGL» —
# формулировка, под которую пролезает что угодно. На деле иконка и орб оказались
# картинками и проходят полный линт; сырьё осталось ровно в одном файле и ровно
# в двух строчках. Пусть исключение и стоит там, где стоит цена.
RAW_VALUE_EXEMPT_FILES = {
    # Два белых с альфой в letterpress лейбла «AI»: блик по верхней кромке
    # плашки и свет под литерами. Это свет внутри знака, а не текст и не
    # бордер: токена «белый 45%» в системе нет, и заводить его ради двух
    # значений внутри одного знака — врать про роль. Знак — артефакт, а не
    # интерфейс, собранный из токенов.
    ROOT / "design" / "parts" / "2-marks" / "wordmark.html",
}
RAW_VALUE_EXEMPT = DIRTY_DIRECTORIES

CARD_FIELDS = ["name", "slug", "status", "height", "why", "never", "tokens", "canon", "swift", "lineage"]
STATUSES = ["принят", "кандидат", "отвергнут"]

STYLE_BLOCK = re.compile(r"<style[^>]*>(.*?)</style>", re.DOTALL)
INLINE_STYLE = re.compile(r'style="([^"]*)"')
CARD_SCRIPT = re.compile(r'<script[^>]*id="card"[^>]*>(.*?)</script>', re.DOTALL)

RAW_HEX = re.compile(r"#[0-9a-fA-F]{3,8}(?![0-9a-zA-Z_-])")
RAW_UNIT = re.compile(r"(?<![\w.])(\d+(?:\.\d+)?)(px|pt)\b")
RAW_FUNCTION_COLOR = re.compile(r"\b(rgba?|hsla?)\s*\(")
ROOT_SELECTOR = re.compile(r":root\b")

# Значения, которым токен не нужен: ноль есть ноль, волосяная линейка бордера
# и «во всю ширину» — не решения дизайн-системы. 999px — radius.full в сыром виде.
ALLOWED_UNIT_VALUES = {"px": {"0", "1", "999"}, "pt": set()}


def relative(path):
    return path.relative_to(ROOT).as_posix()


def inside(path, directories):
    return any(directory in path.parents for directory in directories)


class Report:
    """Копилка нарушений: файл, строка, что нарушено."""

    def __init__(self):
        self.problems = []
        self.notes = []

    def add(self, path, line, message):
        self.problems.append((relative(path), line, message))

    def note(self, message):
        self.notes.append(message)

    def print_and_exit_code(self):
        for path, line, message in sorted(self.problems, key=lambda item: (item[0], item[1])):
            print("%s:%d — %s" % (path, line, message))
        for message in self.notes:
            print(message)
        return 1 if self.problems else 0


# --------------------------------------------------------------------------
# Разбор CSS без парсера CSS
# --------------------------------------------------------------------------

def blank_comments(css):
    """Гасит содержимое комментариев, сохраняя разбивку на строки:
    нумерация строк не должна поехать."""
    def replacer(match):
        return re.sub(r"[^\n]", " ", match.group(0))
    return re.sub(r"/\*.*?\*/", replacer, css, flags=re.DOTALL)


def line_of(text, position):
    return text.count("\n", 0, position) + 1


def css_fragments(path, text):
    """[(смещение_в_файле, css)] — то, что в файле является CSS."""
    if path.suffix == ".css":
        return [(0, text)]
    fragments = []
    for match in STYLE_BLOCK.finditer(text):
        fragments.append((match.start(1), match.group(1)))
    for match in INLINE_STYLE.finditer(text):
        fragments.append((match.start(1), match.group(1)))
    return fragments


def split_selectors(prelude):
    """Делит «a, b:is(c, d)» по запятым верхнего уровня."""
    parts = []
    depth = 0
    current = ""
    for character in prelude:
        if character in "([":
            depth += 1
        elif character in ")]":
            depth -= 1
        if character == "," and depth == 0:
            parts.append(current)
            current = ""
        else:
            current += character
    parts.append(current)
    return [part.strip() for part in parts if part.strip()]


def iterate_rules(css, base=0):
    """Отдаёт (смещение_прелюдии, прелюдия, смещение_тела, тело) для правил
    верхнего уровня фрагмента."""
    rules = []
    index = 0
    length = len(css)
    while index < length:
        brace = css.find("{", index)
        if brace == -1:
            break
        prelude = css[index:brace]
        depth = 1
        position = brace + 1
        while position < length and depth:
            if css[position] == "{":
                depth += 1
            elif css[position] == "}":
                depth -= 1
            position += 1
        body = css[brace + 1:position - 1]
        rules.append((base + index, prelude, base + brace + 1, body))
        index = position
    return rules


NESTING_AT_RULES = ("@media", "@supports", "@container", "@layer")


def check_selectors(report, path, text, css, offset, slug, blanked=False):
    """Каждый селектор части начинается с .p-<slug> — иначе части передерутся
    стилями в витрине (README, «Файл части»)."""
    # Комментарий перед правилом — не селектор. Гасим их до разбора: гашение
    # сохраняет длину и переводы строк, поэтому смещения остаются верными.
    if not blanked:
        css = blank_comments(css)
    for prelude_offset, prelude, body_offset, body in iterate_rules(css, offset):
        stripped = prelude.strip()
        if stripped.startswith("@"):
            keyword = stripped.split()[0].lower()
            if keyword in NESTING_AT_RULES:
                check_selectors(report, path, text, body, body_offset, slug, blanked=True)
            # @keyframes, @font-face — внутри не селекторы части
            continue
        for selector in split_selectors(prelude):
            if is_scoped(selector, slug):
                continue
            if ROOT_SELECTOR.match(selector):
                continue  # про :root уже сказано отдельной проверкой — не дублируем
            position = prelude.find(selector)
            report.add(path, line_of(text, prelude_offset + (position if position >= 0 else 0)),
                       "селектор «%s» не под .p-%s — часть будет драться стилями с соседями"
                       % (selector, slug))


def is_scoped(selector, slug):
    prefix = ".p-%s" % slug
    if not selector.startswith(prefix):
        return False
    rest = selector[len(prefix):]
    return not rest or not re.match(r"[\w-]", rest)


def check_raw_values(report, path, text, css, offset):
    """Сырых значений в частях не бывает — только var(--…)."""
    cleaned = blank_comments(css)
    for match in RAW_HEX.finditer(cleaned):
        report.add(path, line_of(text, offset + match.start()),
                   "сырой цвет «%s» — цвет берётся токеном, var(--…)" % match.group(0))
    for match in RAW_FUNCTION_COLOR.finditer(cleaned):
        report.add(path, line_of(text, offset + match.start()),
                   "сырой цвет «%s(…)» — цвет берётся токеном, var(--…)" % match.group(1))
    for match in RAW_UNIT.finditer(cleaned):
        number, unit = match.group(1), match.group(2)
        if number in ALLOWED_UNIT_VALUES[unit]:
            continue
        report.add(path, line_of(text, offset + match.start()),
                   "сырое значение «%s%s» — отступ, радиус и размер берутся токеном, var(--…)"
                   % (number, unit))


def check_root(report, path, text, css, offset):
    for match in ROOT_SELECTOR.finditer(blank_comments(css)):
        report.add(path, line_of(text, offset + match.start()),
                   ":root вне tokens.css — источник значений один, объявлять переменные тут нельзя")


# --------------------------------------------------------------------------
# Проверки карточки
# --------------------------------------------------------------------------

def card_line(text):
    match = CARD_SCRIPT.search(text)
    return line_of(text, match.start()) if match else 1


def check_card(report, path, text, tokens):
    """Карточка есть, разбирается, поля на месте, значения осмысленные.
    Возвращает карточку либо None."""
    line = card_line(text)
    match = CARD_SCRIPT.search(text)
    if not match:
        report.add(path, 1, 'нет карточки <script type="application/json" id="card"> — '
                            "часть без карточки в систему не принимается")
        return None
    try:
        card = json.loads(match.group(1))
    except json.JSONDecodeError as error:
        report.add(path, line, "карточка не разбирается как JSON: %s" % error)
        return None

    for field in CARD_FIELDS:
        if field not in card:
            report.add(path, line, "в карточке нет обязательного поля «%s»" % field)

    status = card.get("status")
    if status is not None and status not in STATUSES:
        report.add(path, line, "status «%s» — допустимы только: %s" % (status, ", ".join(STATUSES)))

    if "height" in card and not isinstance(card["height"], int):
        report.add(path, line, "height должен быть числом — витрине нужна честная высота образца")

    expected_slug = path.stem
    if card.get("slug") != expected_slug:
        report.add(path, line, "slug «%s» не совпадает с именем файла «%s»"
                   % (card.get("slug"), expected_slug))

    for token_path in card.get("tokens") or []:
        token = build.find_token(tokens, token_path)
        if token is None or not isinstance(token, dict) or "kind" not in token:
            report.add(path, line, "токена «%s» нет в tokens.json — сначала токен, потом использование"
                       % token_path)

    for chapter in card.get("canon") or []:
        if not (ROOT / "docs" / "design" / chapter).exists():
            report.add(path, line, "канон «%s» не существует — docs/design/%s не найден"
                       % (chapter, chapter))

    return card


# --------------------------------------------------------------------------
# Сгенерированное совпадает с источником
# --------------------------------------------------------------------------

def first_difference_line(current, expected):
    current_lines = current.splitlines()
    expected_lines = expected.splitlines()
    for index in range(max(len(current_lines), len(expected_lines))):
        left = current_lines[index] if index < len(current_lines) else None
        right = expected_lines[index] if index < len(expected_lines) else None
        if left != right:
            return index + 1
    return 1


def check_contrast_claims(report, tokens):
    """Поле «contrast» в источнике обязано совпадать с посчитанным.

    Числа в этом поле — утверждения, сделанные рукой, и живут они ровно до
    первой правки цвета. Когда 17.07 лестницу поверхностей сдвинули на
    #05030D, у text.* контрасты пересчитали, а у sem.* забыли — и три числа
    остались точными значениями на прежней рампе #07060B. Выглядели фактом,
    были археологией; поймала их не вычитка, а доска, которая считает сама.
    Отсюда проверка: рукописному числу рядом с вычислимым верить нельзя,
    его надо сверять — иначе оно снова разойдётся при следующем сдвиге.
    """
    for path, claimed, actual in build.contrast_drift(tokens):
        report.add(build.TOKENS_JSON, token_line(path),
                   "«%s»: заявлен контраст %.1f:1, на bg.base выходит %.2f:1 — "
                   "пересчитать поле contrast или поправить цвет"
                   % (path, claimed, actual))


def token_line(path):
    """Строка в tokens.json, где объявлен токен «группа.имя» — чтобы сообщение
    линта было кликабельным, а не заставляло искать глазами."""
    name = path.split(".")[-1]
    pattern = re.compile(r'^\s*"%s"\s*:' % re.escape(name))
    for number, line in enumerate(build.TOKENS_JSON.read_text(encoding="utf-8").splitlines(), 1):
        if pattern.match(line):
            return number
    return 1


def check_generated(report, tokens):
    try:
        outputs = build.build_all(tokens)
    except (ValueError, KeyError) as error:
        report.add(build.TOKENS_JSON, 1, "генерация не проходит: %s" % error)
        return

    for path, expected in outputs.items():
        if not path.exists():
            report.add(path, 1, "файл не сгенерирован — запустить python3 design/build.py")
            continue
        current = path.read_text(encoding="utf-8")
        if current == expected:
            continue
        line = first_difference_line(current, expected)
        if path == build.SHOWCASE:
            report.add(path, line, "витрина не совпадает со сборкой из частей — "
                                   "пересобрать: python3 design/build.py")
        else:
            report.add(path, line, "расходится с tokens.json — правлено руками или не пересобрано; "
                                   "значения правятся в tokens.json, потом python3 design/build.py")


# --------------------------------------------------------------------------
# Сборка проверок
# --------------------------------------------------------------------------

def part_files():
    files = []
    for folder, _title in build.CATEGORIES:
        directory = build.PARTS_DIR / folder
        if directory.is_dir():
            files.extend(sorted(directory.glob("*.html")))
    return files


def main():
    report = Report()
    tokens = build.load_tokens()

    check_generated(report, tokens)
    check_contrast_claims(report, tokens)

    parts = part_files()
    slugs = {}
    without_swift = []

    for path in parts:
        text = path.read_text(encoding="utf-8")
        card = check_card(report, path, text, tokens)

        if card is not None:
            slug = card.get("slug") or path.stem
            if slug in slugs:
                report.add(path, card_line(text),
                           "slug «%s» уже занят частью %s — slug уникален по системе"
                           % (slug, slugs[slug]))
            else:
                slugs[slug] = relative(path)
            if "swift" in card and card["swift"] is None:
                without_swift.append(relative(path))

        slug = (card or {}).get("slug") or path.stem
        for offset, css in css_fragments(path, text):
            check_root(report, path, text, css, offset)
            check_selectors(report, path, text, css, offset, slug)
            if not inside(path, RAW_VALUE_EXEMPT) and path not in RAW_VALUE_EXEMPT_FILES:
                check_raw_values(report, path, text, css, offset)

    # Общая сцена частей — не часть: селекторов .p-<slug> в ней нет по замыслу,
    # но сырых значений и :root не должно быть и в ней.
    specimen = build.PARTS_DIR / "specimen.css"
    if specimen.exists():
        text = specimen.read_text(encoding="utf-8")
        check_root(report, specimen, text, text, 0)
        check_raw_values(report, specimen, text, text, 0)

    report.note("")
    report.note("частей: %d; кандидатов пропущено (приёмная не линтуется): %d"
                % (len(parts), len(list(build.CANDIDATES_DIR.glob("*.html")))
                   if build.CANDIDATES_DIR.is_dir() else 0))
    if without_swift:
        report.note("без реализации в Swift (честный долг, не нарушение): %d — %s"
                    % (len(without_swift), ", ".join(without_swift)))
    if not report.problems:
        report.note("нарушений нет")

    return report.print_and_exit_code()


if __name__ == "__main__":
    sys.exit(main())
