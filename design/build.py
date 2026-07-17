#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Генератор значений дизайн-системы foundry-desktop.

Читает design/tokens/tokens.json — единственный источник значений — и
переписывает то, что из него выводится:

  design/tokens/tokens.css   — переменные для макетов и частей;
  design/tokens/Tokens.swift — константы для приложения;
  docs/design/13-tokens.md   — таблицы значений канона (только между маркерами,
                               проза главы не трогается);
  design/index.html          — витрину, собранную из частей.

Запуск из корня репозитория:  python3 design/build.py

Зависимостей нет — только стандартная библиотека Python 3.
"""

import html
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOKENS_JSON = ROOT / "design" / "tokens" / "tokens.json"
TOKENS_CSS = ROOT / "design" / "tokens" / "tokens.css"
TOKENS_SWIFT = ROOT / "design" / "tokens" / "Tokens.swift"
CANON = ROOT / "docs" / "design" / "13-tokens.md"
SHOWCASE = ROOT / "design" / "index.html"
PARTS_DIR = ROOT / "design" / "parts"
CANDIDATES_DIR = ROOT / "design" / "candidates"
REJECTED_DIR = ROOT / "design" / "rejected"

HEADER = "СГЕНЕРИРОВАНО design/build.py — не править руками"

# Порядок и русские имена категорий витрины. Границы категорий описаны
# в design/parts/README.md; здесь только подписи для панелей.
CATEGORIES = [
    ("1-foundation", "Основа"),
    ("2-marks", "Знаки"),
    ("3-elements", "Элементы"),
    ("4-blocks", "Блоки"),
    ("5-layers", "Слои"),
    ("6-views", "Экраны"),
    ("7-behaviour", "Поведение"),
]

# Веса шрифта: словарь имён SF Pro в числа CSS и в символы SwiftUI.
WEIGHT_CSS = {"Thin": 100, "Light": 300, "Regular": 400, "Medium": 500, "Semibold": 600, "Bold": 700}
WEIGHT_SWIFT = {"Thin": ".thin", "Light": ".light", "Regular": ".regular", "Medium": ".medium",
                "Semibold": ".semibold", "Bold": ".bold"}

# Кривые движения. «spring» в вебе честнее всего отдать этой кривой —
# CSS-пружины нет, а канон требует одного и того же ощущения в макете и в коде.
EASING_CSS = {"ease-out": "ease-out", "ease-in-out": "ease-in-out",
              "spring": "cubic-bezier(0.22, 1, 0.36, 1)"}
EASING_SWIFT = {"ease-out": ".easeOut", "ease-in-out": ".easeInOut",
                "spring": ".timingCurve(0.22, 1, 0.36, 1)"}

# Рецепт свечения из 06-color.md §5.6: внутренний ореол blur 10 @ 40%
# и внешний blur 36 @ 15% цвета токена.
GLOW_INNER_BLUR = 10
GLOW_INNER_ALPHA = 0.4
GLOW_OUTER_BLUR = 36
GLOW_OUTER_ALPHA = 0.15

# Однобуквенные ступени шкал — недопустимые имена в Swift и запрещённые
# доктриной сокращения. Разворачиваем в слова; значения не меняются.
SWIFT_STEP_NAMES = {"s": "small", "m": "medium", "l": "large", "xl": "extraLarge", "full": "full"}

# Ключевые слова Swift. Имя токена придумано не здесь и переименованию
# не подлежит (border.default — это border.default), поэтому такие имена
# экранируются обратными кавычками, а не подгоняются под язык.
SWIFT_KEYWORDS = {
    "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import",
    "init", "inout", "internal", "let", "open", "operator", "private", "protocol", "public",
    "rethrows", "static", "struct", "subscript", "typealias", "var", "break", "case", "continue",
    "default", "defer", "do", "else", "fallthrough", "for", "guard", "if", "in", "repeat",
    "return", "switch", "where", "while", "as", "catch", "false", "is", "nil", "super", "self",
    "throw", "throws", "true", "try", "any", "some",
}


# --------------------------------------------------------------------------
# Чтение и разрешение токенов
# --------------------------------------------------------------------------

def load_tokens():
    """Читает единственный источник значений."""
    with TOKENS_JSON.open(encoding="utf-8") as handle:
        return json.load(handle)


def is_documentation_key(key):
    """Ключи с подчёркиванием — документация, а не токен."""
    return key.startswith("_")


def is_group(node):
    """Группа — словарь без «kind»: внутри неё лежат токены."""
    return isinstance(node, dict) and "kind" not in node


def find_token(tokens, path):
    """Ищет токен по точечному пути вида «brand.ultramarine»."""
    node = tokens
    for step in path.split("."):
        if not isinstance(node, dict) or step not in node:
            return None
        node = node[step]
    return node


def iterate_tokens(tokens):
    """Отдаёт (путь, токен) по всем листьям в порядке файла."""
    for group_name, group in tokens.items():
        if is_documentation_key(group_name) or not isinstance(group, dict):
            continue
        for token_name, token in group.items():
            if is_documentation_key(token_name) or not isinstance(token, dict):
                continue
            yield "%s.%s" % (group_name, token_name), token


def variable_name(path):
    """brand.ultramarine → --brand-ultramarine; space.4 → --space-4."""
    return "--" + path.replace(".", "-")


def hex_to_rgb(hex_string):
    value = hex_string.lstrip("#")
    return tuple(int(value[index:index + 2], 16) for index in (0, 2, 4))


def resolve_rgb(tokens, token, path="?"):
    """Числовой цвет любого цветового токена: hex, base white/black или ref."""
    if "hex" in token:
        return hex_to_rgb(token["hex"])
    base = token.get("base")
    if base == "white":
        return (255, 255, 255)
    if base == "black":
        return (0, 0, 0)
    if "ref" in token:
        referenced = find_token(tokens, token["ref"])
        if referenced is None:
            raise ValueError("токен «%s» ссылается на несуществующий «%s»" % (path, token["ref"]))
        return resolve_rgb(tokens, referenced, token["ref"])
    raise ValueError("у цветового токена «%s» нет ни hex, ни base, ни ref" % path)


def resolve_hex(tokens, token, path="?"):
    """Цвет строкой «#RRGGBB» — с сохранением исходного написания, если оно есть."""
    if "hex" in token:
        return token["hex"]
    red, green, blue = resolve_rgb(tokens, token, path)
    return "#%02X%02X%02X" % (red, green, blue)


def format_alpha(alpha):
    """0.06 → «0.06»; 1.0 → «1». Без хвостовых нулей."""
    text = ("%.4f" % float(alpha)).rstrip("0").rstrip(".")
    return text if text else "0"


def format_percent(alpha):
    """0.06 → «6%» — вид, принятый в таблицах канона."""
    return "%d%%" % round(float(alpha) * 100)


def format_number(value):
    """16.0 → «16»; 0.5 → «0.5». Числа в px/pt без лишнего хвоста."""
    text = ("%.4f" % float(value)).rstrip("0").rstrip(".")
    return text if text else "0"


def rgba_text(rgb, alpha):
    return "rgba(%d,%d,%d,%s)" % (rgb[0], rgb[1], rgb[2], format_alpha(alpha))


def parse_tracking(tracking):
    """«+6%» → 0.06 (доля кегля)."""
    return float(tracking.strip().lstrip("+").rstrip("%")) / 100.0


# --------------------------------------------------------------------------
# (a) design/tokens/tokens.css
# --------------------------------------------------------------------------

def color_css_value(tokens, token, path):
    """Цвет в CSS. Ссылка без альфы остаётся ссылкой — источник один."""
    if "hex" in token:
        return token["hex"]
    if "base" in token:
        return rgba_text(resolve_rgb(tokens, token, path), token.get("alpha", 1.0))
    if "ref" in token:
        if "alpha" in token:
            return rgba_text(resolve_rgb(tokens, token, path), token["alpha"])
        return "var(%s)" % variable_name(token["ref"])
    raise ValueError("не понимаю цветовой токен «%s»" % path)


def gradient_css_value(tokens, token, path):
    stops = []
    for stop in token["stops"]:
        referenced = find_token(tokens, stop)
        if referenced is None:
            raise ValueError("градиент «%s» ссылается на несуществующий «%s»" % (path, stop))
        stops.append(resolve_hex(tokens, referenced, stop))
    interpolation = token.get("interpolation")
    prefix = "in %s, " % interpolation if interpolation else ""
    return "linear-gradient(%s%s)" % (prefix, ", ".join(stops))


def font_css_value(token):
    names = []
    for name in token["stack"]:
        names.append('"%s"' % name if " " in name else name)
    return ", ".join(names)


def glow_css_value(tokens, token, path):
    """Двухслойный рецепт свечения готовым значением box-shadow."""
    rgb = resolve_rgb(tokens, token, path)
    return "0 0 %dpx %s, 0 0 %dpx %s" % (
        GLOW_INNER_BLUR, rgba_text(rgb, GLOW_INNER_ALPHA),
        GLOW_OUTER_BLUR, rgba_text(rgb, GLOW_OUTER_ALPHA),
    )


def css_declarations(tokens, path, token):
    """Строки объявлений для одного токена. Пустой список — токен не имеет
    представления в CSS (об этом рядом пишется комментарий)."""
    kind = token.get("kind")
    role = token.get("role", "")
    suffix = "  /* %s */" % role if role else ""

    if kind == "color":
        return ["  %s: %s;%s" % (variable_name(path), color_css_value(tokens, token, path), suffix)]

    if kind == "gradient":
        return ["  %s: %s;%s" % (variable_name(path), gradient_css_value(tokens, token, path), suffix)]

    if kind in ("space", "radius", "size"):
        # pt макета ложится в px один к одному.
        return ["  %s: %spx;%s" % (variable_name(path), format_number(token["pt"]), suffix)]

    if kind == "font":
        return ["  %s: %s;%s" % (variable_name(path), font_css_value(token), suffix)]

    if kind == "type":
        lines = []
        if role:
            lines.append("  /* %s — %s */" % (path, role))
        lines.append("  %s-size: %spx;" % (variable_name(path), format_number(token["size"])))
        lines.append("  %s-leading: %spx;" % (variable_name(path), format_number(token["leading"])))
        lines.append("  %s-weight: %d;" % (variable_name(path), WEIGHT_CSS[token["weight"]]))
        lines.append("  %s-family: var(--font-%s);" % (variable_name(path), token["family"]))
        if token.get("caps"):
            lines.append("  %s-caps: uppercase;" % variable_name(path))
        if token.get("tracking"):
            lines.append("  %s-tracking: %sem;" % (variable_name(path),
                                                   format_number(parse_tracking(token["tracking"]))))
        return lines

    if kind == "motion":
        lines = []
        milliseconds = token.get("ms")
        easing = token.get("easing")
        if milliseconds is not None:
            lines.append("  %s-duration: %dms;%s" % (variable_name(path), milliseconds, suffix))
        if easing in EASING_CSS:
            lines.append("  %s-easing: %s;" % (variable_name(path), EASING_CSS[easing]))
        if milliseconds is None and easing not in EASING_CSS:
            # motion.live — непрерывное состояние, а не переход: у CSS нет
            # значения для «мягкая, непрерывная», врать нечем.
            lines.append("  /* %s: %s (%s) — не переход, а состояние; в CSS значения нет */"
                         % (path, easing, role))
        return lines

    if kind == "glow":
        referenced = find_token(tokens, token["ref"])
        if referenced is not None and referenced.get("kind") == "gradient":
            # Свечение градиентом не выражается тенью — это заливка орба.
            return ["  /* %s: %s — градиент, а не box-shadow (%s) */" % (path, token["ref"], role)]
        return ["  %s: %s;%s" % (variable_name(path), glow_css_value(tokens, token, path), suffix)]

    raise ValueError("неизвестный kind «%s» у токена «%s»" % (kind, path))


def generate_tokens_css(tokens):
    lines = ["/* %s */" % HEADER]
    root_note = tokens.get("_")
    if root_note:
        lines.append("/* %s */" % root_note)
    lines.append("")
    lines.append(":root {")

    for group_name, group in tokens.items():
        if is_documentation_key(group_name) or not isinstance(group, dict):
            continue
        lines.append("")
        role = group.get("_role")
        if role:
            lines.append("  /* %s — %s */" % (group_name, role))
        else:
            lines.append("  /* %s */" % group_name)
        for token_name, token in group.items():
            if is_documentation_key(token_name) or not isinstance(token, dict):
                continue
            lines.extend(css_declarations(tokens, "%s.%s" % (group_name, token_name), token))

    lines.append("}")
    lines.append("")
    return "\n".join(lines)


# --------------------------------------------------------------------------
# (b) design/tokens/Tokens.swift
# --------------------------------------------------------------------------

# Имена пространств Swift. «font» развёрнут в FontStack, чтобы не затенять
# SwiftUI.Font; «type» — в Typography по той же причине.
SWIFT_NAMESPACES = {
    "brand": "Brand", "bg": "Background", "border": "Border", "text": "Text",
    "sem": "Semantic", "diff": "Diff", "code": "Code", "space": "Space",
    "radius": "Radius", "type": "Typography", "font": "FontStack",
    "control": "Control", "icon": "Icon", "row": "Row", "motion": "Motion",
    "glow": "Glow",
}


def swift_member_name(group_name, token_name):
    """Имя токена → корректный идентификатор Swift без сокращений."""
    if group_name in ("space",):
        # space.4 → step4: цифрой идентификатор начинаться не может.
        name = "step%s" % token_name
    elif group_name in ("radius", "icon") and token_name in SWIFT_STEP_NAMES:
        name = SWIFT_STEP_NAMES[token_name]
    else:
        parts = token_name.split("-")
        expanded = [SWIFT_STEP_NAMES.get(parts[0], parts[0])]
        for part in parts[1:]:
            word = SWIFT_STEP_NAMES.get(part, part)
            expanded.append(word[:1].upper() + word[1:])
        name = "".join(expanded)
    return "`%s`" % name if name in SWIFT_KEYWORDS else name


def swift_color_expression(tokens, token, path):
    if "hex" in token:
        return "Color(hexValue: 0x%s)" % token["hex"].lstrip("#").upper()
    if "base" in token:
        white = 1.0 if token["base"] == "white" else 0.0
        return "Color(white: %s, opacity: %s)" % (format_alpha(white), format_alpha(token.get("alpha", 1.0)))
    if "ref" in token:
        reference = swift_reference(token["ref"])
        if "alpha" in token:
            return "%s.opacity(%s)" % (reference, format_alpha(token["alpha"]))
        return reference
    raise ValueError("не понимаю цветовой токен «%s»" % path)


def swift_reference(path):
    group_name, token_name = path.split(".", 1)
    return "Token.%s.%s" % (SWIFT_NAMESPACES[group_name], swift_member_name(group_name, token_name))


def swift_declaration(tokens, group_name, token_name, token):
    path = "%s.%s" % (group_name, token_name)
    member = swift_member_name(group_name, token_name)
    kind = token.get("kind")
    lines = []
    role = token.get("role")
    if role:
        lines.append("        /// %s" % role)

    if kind == "color":
        lines.append("        static let %s = %s" % (member, swift_color_expression(tokens, token, path)))
        return lines

    if kind == "gradient":
        stops = ", ".join(swift_reference(stop) for stop in token["stops"])
        lines.append("        /// Интерполяция канона — %s; SwiftUI смешивает в своём"
                     % token.get("interpolation", "sRGB"))
        lines.append("        /// пространстве, поэтому опорные точки заданы явно.")
        lines.append("        static let %s = LinearGradient(" % member)
        lines.append("            colors: [%s]," % stops)
        lines.append("            startPoint: .topLeading,")
        lines.append("            endPoint: .bottomTrailing")
        lines.append("        )")
        return lines

    if kind in ("space", "radius", "size"):
        lines.append("        static let %s: CGFloat = %s" % (member, format_number(token["pt"])))
        return lines

    if kind == "font":
        names = ", ".join('"%s"' % name for name in token["stack"])
        lines.append("        static let %s: [String] = [%s]" % (member, names))
        return lines

    if kind == "type":
        arguments = [
            "size: %s" % format_number(token["size"]),
            "leading: %s" % format_number(token["leading"]),
            "weight: %s" % WEIGHT_SWIFT[token["weight"]],
            "family: .%s" % token["family"],
        ]
        if token.get("caps"):
            arguments.append("isUppercased: true")
        if token.get("tracking"):
            arguments.append("tracking: %s" % format_number(parse_tracking(token["tracking"])))
        lines.append("        static let %s = TypeToken(%s)" % (member, ", ".join(arguments)))
        return lines

    if kind == "motion":
        milliseconds = token.get("ms")
        easing = token.get("easing")
        if milliseconds is None or easing not in EASING_SWIFT:
            # motion.live — непрерывное состояние, а не переход с длительностью.
            lines.append("        /// Непрерывное состояние, а не переход: длительности нет,")
            lines.append("        /// пульс задаёт сама сцена (%s)." % easing)
            lines.append("        static let %s = MotionToken(duration: nil, animation: nil)" % member)
            return lines
        duration = format_number(milliseconds / 1000.0)
        animation = EASING_SWIFT[easing]
        if easing == "spring":
            animation = ".timingCurve(0.22, 1, 0.36, 1, duration: %s)" % duration
        else:
            animation = "%s(duration: %s)" % (EASING_SWIFT[easing], duration)
        lines.append("        static let %s = MotionToken(duration: %s, animation: %s)"
                     % (member, duration, animation))
        return lines

    if kind == "glow":
        referenced = find_token(tokens, token["ref"])
        if referenced is not None and referenced.get("kind") == "gradient":
            lines.append("        /// Градиент, а не тень: заливка орба — %s." % token["ref"])
            lines.append("        /// Значения свечения здесь нет намеренно.")
            return lines
        lines.append("        static let %s = GlowToken(color: %s)" % (member, swift_reference(token["ref"])))
        return lines

    raise ValueError("неизвестный kind «%s» у токена «%s»" % (kind, path))


SWIFT_PREAMBLE = '''import SwiftUI

/// Семейство шрифта токена: интерфейсный текст или моноширинный.
enum TokenFontFamily {
    case text
    case mono
}

/// Типографский токен: кегль, интерлиньяж, вес, семейство.
struct TypeToken {
    let size: CGFloat
    let leading: CGFloat
    let weight: Font.Weight
    let family: TokenFontFamily
    /// Прописные (лейблы секций сайдбара).
    let isUppercased: Bool
    /// Трекинг долей кегля.
    let tracking: CGFloat

    init(size: CGFloat, leading: CGFloat, weight: Font.Weight, family: TokenFontFamily,
         isUppercased: Bool = false, tracking: CGFloat = 0) {
        self.size = size
        self.leading = leading
        self.weight = weight
        self.family = family
        self.isUppercased = isUppercased
        self.tracking = tracking
    }

    var font: Font {
        .system(size: size, weight: weight, design: family == .mono ? .monospaced : .default)
    }

    /// Насколько развести строки, чтобы получить интерлиньяж канона.
    var lineSpacing: CGFloat {
        max(0, leading - size)
    }
}

/// Токен движения. duration == nil — непрерывное состояние, а не переход.
struct MotionToken {
    let duration: TimeInterval?
    let animation: Animation?
}

/// Свечение — фирменная замена тени. Рецепт двухслойный: внутренний ореол
/// blur 10 @ 40% и внешний blur 36 @ 15% цвета токена (06-color.md §5.6).
struct GlowToken {
    let color: Color
    let innerRadius: CGFloat = 10
    let innerOpacity: Double = 0.4
    let outerRadius: CGFloat = 36
    let outerOpacity: Double = 0.15
}

extension Color {
    /// Цвет из целого 0xRRGGBB — тем же написанием, что и в tokens.json.
    init(hexValue: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hexValue >> 16) & 0xFF) / 255,
            green: Double((hexValue >> 8) & 0xFF) / 255,
            blue: Double(hexValue & 0xFF) / 255,
            opacity: opacity
        )
    }
}
'''


def generate_tokens_swift(tokens):
    lines = ["// %s" % HEADER]
    root_note = tokens.get("_")
    if root_note:
        lines.append("// %s" % root_note)
    lines.append("")
    lines.append(SWIFT_PREAMBLE)
    lines.append("enum Token {")

    first = True
    for group_name, group in tokens.items():
        if is_documentation_key(group_name) or not isinstance(group, dict):
            continue
        if not first:
            lines.append("")
        first = False
        role = group.get("_role")
        if role:
            lines.append("    /// %s" % role)
        lines.append("    enum %s {" % SWIFT_NAMESPACES[group_name])
        for token_name, token in group.items():
            if is_documentation_key(token_name) or not isinstance(token, dict):
                continue
            lines.extend(swift_declaration(tokens, group_name, token_name, token))
        lines.append("    }")

    lines.append("}")
    lines.append("")
    return "\n".join(lines)


# --------------------------------------------------------------------------
# (c) таблицы значений в docs/design/13-tokens.md
# --------------------------------------------------------------------------

MARKER_START = "<!-- tokens:начало сгенерированного: %s -->"
MARKER_END = "<!-- tokens:конец -->"


def code(text):
    return "`%s`" % text


def value_text(tokens, token, path):
    """Значение так, как его пишет канон: hex, «white @ 6%», ссылка, «2pt».

    Размерный токен допустим в любой группе: цветовая группа не обязана
    состоять из одних цветов (border.focus — цвет, border.focus-width — pt).
    """
    if token.get("kind") in ("space", "radius", "size"):
        return "%spt" % format_number(token["pt"])
    if "hex" in token:
        return code(token["hex"])
    if "base" in token:
        base = code("#000000") if token["base"] == "black" else "white"
        text = "%s @ %s" % (base, format_percent(token.get("alpha", 1.0)))
        if token.get("over") == "current":
            text += " поверх текущего уровня"
        return text
    if "ref" in token:
        if "alpha" in token:
            return "%s @ %s" % (code(token["ref"]), format_percent(token["alpha"]))
        return code(token["ref"])
    raise ValueError("не понимаю цветовой токен «%s»" % path)


def table(header, alignment_count, rows):
    lines = ["| " + " | ".join(header) + " |", "|" + "---|" * alignment_count]
    lines.extend(rows)
    return lines


def section_palette(tokens):
    rows = []
    for name, token in tokens["brand"].items():
        if is_documentation_key(name):
            continue
        path = "brand.%s" % name
        if token["kind"] == "gradient":
            stops = " → ".join(code(stop) for stop in token["stops"])
            role = token["role"]
            if token.get("interpolation"):
                role += "; интерполяция в %s" % token["interpolation"].upper()
            rows.append("| %s | %s | %s |" % (code(path), stops, role))
        else:
            rows.append("| %s | %s | %s |" % (code(path), code(token["hex"]), token["role"]))
    return table(["Токен", "HEX", "Роль"], 3, rows)


def section_surfaces(tokens):
    rows = []
    for name, token in tokens["bg"].items():
        if is_documentation_key(name):
            continue
        path = "bg.%s" % name
        rows.append("| %s | %s | %s |" % (code(path), value_text(tokens, token, path), token["role"]))
    return table(["Токен", "HEX", "Что лежит на этом уровне"], 3, rows)


def section_borders(tokens):
    rows = []
    for name, token in tokens["border"].items():
        if is_documentation_key(name):
            continue
        path = "border.%s" % name
        rows.append("| %s | %s | %s |" % (code(path), value_text(tokens, token, path), token["role"]))
    return table(["Токен", "Значение", "Где"], 3, rows)


def section_text(tokens):
    rows = []
    for name, token in tokens["text"].items():
        if is_documentation_key(name):
            continue
        path = "text.%s" % name
        rows.append("| %s | %s | %s | %s |" % (
            code(path), value_text(tokens, token, path), token["role"], token.get("contrast", "—")))
    return table(["Токен", "Значение", "Роль", "Контраст на `bg.base`"], 4, rows)


def section_semantic(tokens):
    rows = []
    group = tokens["sem"]
    for name, token in group.items():
        if is_documentation_key(name) or name.endswith("-fill") or name.endswith("-border"):
            continue
        path = "sem.%s" % name
        value = value_text(tokens, token, path)
        if token.get("contrast"):
            value += " (%s)" % token["contrast"]
        fill = group.get("%s-fill" % name)
        border = group.get("%s-border" % name)
        fill_text = "@ %s" % format_percent(fill["alpha"]) if fill else "—"
        border_text = "@ %s" % format_percent(border["alpha"]) if border else "—"
        rows.append("| %s | %s | %s | %s | %s |" % (code(path), value, fill_text, border_text, token["role"]))
    return table(["Токен", "HEX (текст/иконка)", "Заливка плашки", "Бордер (опционально)", "Смысл"], 5, rows)


def section_diff(tokens):
    rows = []
    for group_name in ("diff", "code"):
        for name, token in tokens[group_name].items():
            if is_documentation_key(name):
                continue
            path = "%s.%s" % (group_name, name)
            rows.append("| %s | %s — %s |" % (code(path), value_text(tokens, token, path), token["role"]))
    return table(["Токен", "Значение"], 2, rows)


def section_space(tokens):
    rows = []
    for name, token in tokens["space"].items():
        if is_documentation_key(name):
            continue
        rows.append("| %s | %s | %s |" % (code("space.%s" % name), format_number(token["pt"]), token["role"]))
    return table(["Токен", "pt", "Типовое применение"], 3, rows)


def section_radius(tokens):
    rows = []
    for name, token in tokens["radius"].items():
        if is_documentation_key(name):
            continue
        rows.append("| %s | %s | %s |" % (code("radius.%s" % name), format_number(token["pt"]), token["role"]))
    return table(["Токен", "pt", "Где"], 3, rows)


def section_typography(tokens):
    rows = []
    for name, token in tokens["type"].items():
        if is_documentation_key(name):
            continue
        size = "%s/%s" % (format_number(token["size"]), format_number(token["leading"]))
        weight = token["weight"]
        if token["family"] == "mono":
            weight += " (SF Mono)"
        if token.get("caps"):
            weight += ", caps"
        if token.get("tracking"):
            weight += ", трекинг %s" % token["tracking"]
        rows.append("| %s | %s | %s | %s |" % (code("type.%s" % name), size, weight, token["role"]))
    return table(["Токен", "Кегль/интерлиньяж", "Вес", "Роль"], 4, rows)


def section_sizes(tokens):
    rows = []
    for group_name in ("control", "icon", "row"):
        for name, token in tokens[group_name].items():
            if is_documentation_key(name):
                continue
            path = "%s.%s" % (group_name, name)
            rows.append("| %s | %spt (%s) |" % (code(path), format_number(token["pt"]), token["role"]))
    return table(["Токен", "Значение"], 2, rows)


def section_motion(tokens):
    rows = []
    for name, token in tokens["motion"].items():
        if is_documentation_key(name):
            continue
        if token.get("ms") is None:
            value = token["easing"]
        else:
            value = "%d мс, %s" % (token["ms"], token["easing"])
        rows.append("| %s | %s | %s |" % (code("motion.%s" % name), value, token["role"]))
    return table(["Токен", "Значение", "Где"], 3, rows)


def section_glow(tokens):
    rows = []
    for name, token in tokens["glow"].items():
        if is_documentation_key(name):
            continue
        value = code(token["ref"])
        if token.get("pulse"):
            value += ", пульс %s" % code(token["pulse"])
        rows.append("| %s | %s | %s |" % (code("glow.%s" % name), value, token["role"]))
    return table(["Токен", "Цвет", "Где"], 3, rows)


CANON_SECTIONS = {
    "палитра": section_palette,
    "поверхности": section_surfaces,
    "бордеры": section_borders,
    "текст": section_text,
    "семантика": section_semantic,
    "дифф": section_diff,
    "отступы": section_space,
    "радиусы": section_radius,
    "типографика": section_typography,
    "размеры": section_sizes,
    "движение": section_motion,
    "свечение": section_glow,
}


def generate_canon(tokens, current_text):
    """Переписывает только то, что между маркерами. Проза главы неприкосновенна."""
    result = current_text
    for key, builder in CANON_SECTIONS.items():
        start = MARKER_START % key
        if start not in result:
            raise ValueError("в %s нет маркера «%s» — вставить его вокруг таблицы один раз вручную"
                             % (CANON.name, start))
        head, rest = result.split(start, 1)
        if MARKER_END not in rest:
            raise ValueError("в %s у маркера «%s» нет закрывающего «%s»" % (CANON.name, key, MARKER_END))
        _, tail = rest.split(MARKER_END, 1)
        body = "\n".join(builder(tokens))
        result = head + start + "\n" + body + "\n" + MARKER_END + tail
    return result


# --------------------------------------------------------------------------
# (d) design/index.html — витрина
# --------------------------------------------------------------------------

CARD_PATTERN = re.compile(r'<script[^>]*id="card"[^>]*>(.*?)</script>', re.DOTALL)


def read_card(path):
    """Достаёт карточку части. None — карточки нет или она не разбирается:
    витрина не падает из-за одной части, об этом говорит линт."""
    text = path.read_text(encoding="utf-8")
    match = CARD_PATTERN.search(text)
    if not match:
        return None
    try:
        return json.loads(match.group(1))
    except json.JSONDecodeError:
        return None


def collect_parts():
    """Части по категориям: {категория: [(карточка, путь), ...]}."""
    collected = {}
    for folder, _title in CATEGORIES:
        directory = PARTS_DIR / folder
        found = []
        if directory.is_dir():
            for path in sorted(directory.glob("*.html")):
                card = read_card(path)
                if card:
                    found.append((card, path))
        collected[folder] = found
    return collected


def collect_candidates():
    found = []
    if CANDIDATES_DIR.is_dir():
        for path in sorted(CANDIDATES_DIR.glob("*.html")):
            card = read_card(path)
            if card:
                found.append((card, path))
    return found


def parse_front_matter(text):
    """Простой front-matter «ключ: значение» между строками «---».
    Своего парсера YAML в проекте нет и не будет — зависимостей ноль."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}, text
    fields = {}
    for index in range(1, len(lines)):
        if lines[index].strip() == "---":
            return fields, "\n".join(lines[index + 1:])
        if ":" in lines[index]:
            key, value = lines[index].split(":", 1)
            fields[key.strip()] = value.strip().strip('"').strip("'")
    return fields, text


REASON_HEADING = re.compile(r"^##\s+Почему отвергнуто\s*$", re.MULTILINE)


def plain_text(markdown):
    """Разметка в текст: витрине нужна фраза, а не звёздочки и ссылки."""
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", markdown)
    return text.replace("**", "").replace("`", "").strip()


def first_paragraph(text):
    """Первый содержательный абзац. Заголовки — граница; цитатные птички
    снимаем. Абзац, кончающийся двоеточием, обрывается на полуслове — причина
    продолжается цитатой ниже, поэтому забираем и её."""
    collected = []
    current = []
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("#"):
            if collected or current:
                break
            continue
        if not stripped:
            if current:
                collected.append(" ".join(current))
                current = []
                if not collected[-1].endswith(":"):
                    break
            continue
        current.append(stripped.lstrip("> ").strip())
    if current:
        collected.append(" ".join(current))
    return " ".join(collected)


def collect_rejected():
    """Кладбище: имя из front-matter, причина — из раздела «Почему отвергнуто».
    Причина здесь дороже имени: ради неё кладбище и существует."""
    found = []
    if not REJECTED_DIR.is_dir():
        return found
    for path in sorted(REJECTED_DIR.glob("*.md")):
        fields, body = parse_front_matter(path.read_text(encoding="utf-8"))
        name = fields.get("name") or fields.get("имя") or path.stem
        reason = fields.get("reason") or fields.get("причина") or fields.get("why")
        if not reason:
            heading = REASON_HEADING.search(body)
            reason = first_paragraph(body[heading.end():] if heading else body)
        found.append({
            "name": plain_text(name),
            "reason": plain_text(reason) or "причина не записана — запись кладбища без причины бесполезна",
            "file": path.name,
        })
    return found


SHOWCASE_STYLE = """
  * { box-sizing: border-box; }
  body {
    margin: 0;
    background: var(--bg-base);
    color: var(--text-primary);
    font-family: var(--font-text);
    font-size: var(--type-body-size);
    line-height: var(--type-body-leading);
  }
  a { color: var(--text-accent); }
  code { font-family: var(--font-mono); font-size: var(--type-mono-s-size); }

  header {
    padding: var(--space-8) var(--space-8) var(--space-5);
    border-bottom: 1px solid var(--border-subtle);
  }
  h1 {
    margin: 0 0 var(--space-2);
    font-size: var(--type-title-size);
    line-height: var(--type-title-leading);
    font-weight: var(--type-title-weight);
  }
  header p { margin: 0; color: var(--text-secondary); max-width: 640px; }

  nav {
    position: sticky;
    top: 0;
    z-index: 2;
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-1);
    padding: var(--space-3) var(--space-8);
    background: var(--bg-raised);
    border-bottom: 1px solid var(--border-subtle);
  }
  nav a {
    padding: var(--space-1) var(--space-3);
    border-radius: var(--radius-m);
    color: var(--text-secondary);
    text-decoration: none;
  }
  nav a:hover { background: var(--bg-hover); color: var(--text-primary); }
  nav .count { color: var(--text-tertiary); }

  main { padding: var(--space-6) var(--space-8) var(--space-10); }
  section { margin-bottom: var(--space-10); }
  section > h2 {
    margin: 0 0 var(--space-1);
    font-size: var(--type-heading-size);
    line-height: var(--type-heading-leading);
    font-weight: var(--type-heading-weight);
  }
  section > p.note { margin: 0 0 var(--space-5); color: var(--text-secondary); max-width: 720px; }

  .band {
    padding: var(--space-5);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-xl);
    background: var(--bg-surface);
  }
  .band.candidates { border-color: var(--sem-warning-border); }

  .grid { display: grid; gap: var(--space-5); grid-template-columns: 1fr; }
  @media (min-width: 1100px) { .grid { grid-template-columns: 1fr 1fr; } }

  .card {
    border: 1px solid var(--border-default);
    border-radius: var(--radius-l);
    background: var(--bg-surface);
    overflow: hidden;
  }
  .card-head {
    display: flex;
    align-items: baseline;
    gap: var(--space-2);
    padding: var(--space-4);
  }
  .card-head h3 {
    margin: 0;
    font-size: var(--type-heading-size);
    line-height: var(--type-heading-leading);
    font-weight: var(--type-heading-weight);
  }
  .card-head .slug { color: var(--text-tertiary); font-family: var(--font-mono); }

  .chip {
    padding: 0 var(--space-2);
    border-radius: var(--radius-s);
    font-size: var(--type-caption-size);
    line-height: var(--type-caption-leading);
    white-space: nowrap;
  }
  .chip-accepted { background: var(--sem-success-fill); color: var(--sem-success); }
  .chip-candidate { background: var(--sem-warning-fill); color: var(--sem-warning); }
  .chip-rejected { background: var(--sem-error-fill); color: var(--sem-error); }

  .stage { background: var(--bg-base); border-top: 1px solid var(--border-subtle); }
  .stage iframe { display: block; width: 100%; border: 0; }

  dl { margin: 0; padding: var(--space-4); border-top: 1px solid var(--border-subtle); }
  dt {
    margin-bottom: var(--space-1);
    color: var(--text-tertiary);
    font-size: var(--type-label-size);
    line-height: var(--type-label-leading);
    font-weight: var(--type-label-weight);
    text-transform: var(--type-label-caps);
    letter-spacing: var(--type-label-tracking);
  }
  dd { margin: 0 0 var(--space-3); color: var(--text-secondary); }
  dd:last-child { margin-bottom: 0; }
  dd.never { color: var(--text-primary); }
  dd.debt { color: var(--sem-warning); }

  .tokens { display: flex; flex-wrap: wrap; gap: var(--space-1); }
  .tokens span {
    padding: 0 var(--space-1);
    border: 1px solid var(--border-subtle);
    border-radius: var(--radius-s);
    font-family: var(--font-mono);
    font-size: var(--type-mono-s-size);
    color: var(--text-secondary);
  }

  .empty {
    padding: var(--space-6);
    border: 1px solid var(--border-subtle);
    border-radius: var(--radius-l);
    color: var(--text-tertiary);
    text-align: center;
  }

  table.rejected { width: 100%; border-collapse: collapse; }
  table.rejected th, table.rejected td {
    padding: var(--space-2) var(--space-3);
    border-bottom: 1px solid var(--border-subtle);
    text-align: left;
    vertical-align: top;
  }
  table.rejected th {
    color: var(--text-tertiary);
    font-size: var(--type-caption-size);
    font-weight: var(--type-caption-weight);
  }
  table.rejected td { color: var(--text-secondary); }
"""

STATUS_CHIP = {"принят": "chip-accepted", "кандидат": "chip-candidate", "отвергнут": "chip-rejected"}


def escape(value):
    return html.escape(str(value), quote=True)


def render_card(card, path):
    """Одна часть: карточка + образец в iframe. iframe — чтобы части
    не передрались стилями (README, «Файл части»)."""
    source = path.relative_to(ROOT / "design").as_posix()
    status = card.get("status", "?")
    chip_class = STATUS_CHIP.get(status, "chip-candidate")
    height = card.get("height", 200)

    lines = ['<article class="card">']
    lines.append('  <div class="card-head">')
    lines.append("    <h3>%s</h3>" % escape(card.get("name", path.stem)))
    lines.append('    <span class="slug">%s</span>' % escape(card.get("slug", path.stem)))
    lines.append('    <span class="chip %s">%s</span>' % (chip_class, escape(status)))
    lines.append("  </div>")

    lines.append('  <div class="stage">')
    lines.append('    <iframe src="%s" height="%s" loading="lazy" title="%s"></iframe>'
                 % (escape(source), escape(height), escape(card.get("name", ""))))
    lines.append("  </div>")

    lines.append("  <dl>")
    lines.append("    <dt>Зачем</dt><dd>%s</dd>" % escape(card.get("why", "—")))
    lines.append('    <dt>Никогда</dt><dd class="never">%s</dd>' % escape(card.get("never", "—")))

    tokens_used = card.get("tokens") or []
    tokens_html = "".join("<span>%s</span>" % escape(token) for token in tokens_used) or "—"
    lines.append('    <dt>Ест токены</dt><dd class="tokens">%s</dd>' % tokens_html)

    canon_links = card.get("canon") or []
    links = ", ".join('<a href="../docs/design/%s">%s</a>' % (escape(chapter), escape(chapter))
                      for chapter in canon_links) or "—"
    lines.append("    <dt>Канон</dt><dd>%s</dd>" % links)

    swift_symbol = card.get("swift")
    if swift_symbol:
        lines.append("    <dt>Реализация</dt><dd><code>%s</code></dd>" % escape(swift_symbol))
    else:
        lines.append('    <dt>Реализация</dt><dd class="debt">реализации нет</dd>')

    lines.append("    <dt>Родословная</dt><dd>%s</dd>" % escape(card.get("lineage", "—")))
    lines.append("  </dl>")
    lines.append("</article>")
    return lines


def generate_showcase(tokens):
    parts = collect_parts()
    candidates = collect_candidates()
    rejected = collect_rejected()

    lines = ["<!doctype html>", "<html lang=\"ru\">", "<head>", '<meta charset="utf-8">',
             "<!-- %s -->" % HEADER,
             "<title>Витрина дизайн-системы — foundry-desktop</title>",
             '<link rel="stylesheet" href="tokens/tokens.css">',
             "<style>%s</style>" % SHOWCASE_STYLE,
             "</head>", "<body>"]

    lines.append("<header>")
    lines.append("  <h1>Витрина дизайн-системы</h1>")
    lines.append("  <p>Собрана из частей скриптом <code>design/build.py</code>. Своего содержимого "
                 "не имеет: правка руками теряется при следующей сборке. Договор о формате части — "
                 '<a href="parts/README.md">design/parts/README.md</a>, значения — '
                 '<a href="tokens/tokens.json">tokens.json</a>.</p>')
    lines.append("</header>")

    lines.append("<nav>")
    if candidates:
        lines.append('  <a href="#candidates">Кандидаты <span class="count">%d</span></a>' % len(candidates))
    for folder, title in CATEGORIES:
        lines.append('  <a href="#%s">%s <span class="count">%d</span></a>'
                     % (folder, escape(title), len(parts[folder])))
    if rejected:
        lines.append('  <a href="#rejected">Отвергнуто <span class="count">%d</span></a>' % len(rejected))
    lines.append("</nav>")

    lines.append("<main>")

    if candidates:
        lines.append('<section id="candidates">')
        lines.append("  <h2>Кандидаты — не закон</h2>")
        lines.append('  <p class="note">Приехали из сессий, приёмку не проходили. Ссылаться на них '
                     "как на решённое нельзя. Проходят приёмку — переезжают в свою категорию; "
                     "не проходят — на кладбище с причиной.</p>")
        lines.append('  <div class="band candidates"><div class="grid">')
        for card, path in candidates:
            lines.extend("    " + line for line in render_card(card, path))
        lines.append("  </div></div>")
        lines.append("</section>")

    for folder, title in CATEGORIES:
        lines.append('<section id="%s">' % folder)
        lines.append("  <h2>%s</h2>" % escape(title))
        if not parts[folder]:
            lines.append('  <div class="empty">Частей пока нет.</div>')
        else:
            lines.append('  <div class="grid">')
            for card, path in parts[folder]:
                lines.extend("    " + line for line in render_card(card, path))
            lines.append("  </div>")
        lines.append("</section>")

    if rejected:
        lines.append('<section id="rejected">')
        lines.append("  <h2>Отвергнуто</h2>")
        lines.append('  <p class="note">Кладбище — полноправный житель системы и стоит дороже '
                     "принятого: принятое видно на экране, отвергнутое не видно нигде и потому "
                     "предлагается заново каждой следующей сессией.</p>")
        lines.append('  <table class="rejected">')
        lines.append("    <tr><th>Что</th><th>Почему отвергнуто</th><th>Файл</th></tr>")
        for item in rejected:
            lines.append('    <tr><td>%s</td><td>%s</td><td><a href="rejected/%s"><code>%s</code></a></td></tr>'
                         % (escape(item["name"]), escape(item["reason"]),
                            escape(item["file"]), escape(item["file"])))
        lines.append("  </table>")
        lines.append("</section>")

    lines.append("</main>")
    lines.append("</body>")
    lines.append("</html>")
    lines.append("")
    return "\n".join(lines)


# --------------------------------------------------------------------------
# Сборка
# --------------------------------------------------------------------------

def write_if_changed(path, content):
    """Возвращает True, если файл поменялся."""
    if path.exists() and path.read_text(encoding="utf-8") == content:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    return True


def build_all(tokens):
    """Готовит содержимое всех генерируемых файлов: {путь: текст}.
    Тем же кодом пользуется линт, чтобы поймать правку руками."""
    outputs = {
        TOKENS_CSS: generate_tokens_css(tokens),
        TOKENS_SWIFT: generate_tokens_swift(tokens),
        SHOWCASE: generate_showcase(tokens),
    }
    if CANON.exists():
        outputs[CANON] = generate_canon(tokens, CANON.read_text(encoding="utf-8"))
    return outputs


def main():
    try:
        tokens = load_tokens()
        outputs = build_all(tokens)
    except (ValueError, KeyError) as error:
        print("сборка не удалась: %s" % error)
        return 1

    for path, content in outputs.items():
        relative = path.relative_to(ROOT)
        if write_if_changed(path, content):
            print("переписано  %s" % relative)
        else:
            print("без изменений %s" % relative)
    return 0


if __name__ == "__main__":
    sys.exit(main())
