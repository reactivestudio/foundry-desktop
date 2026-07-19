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
import math
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
# Колориметрия: OKLCH и контраст
#
# Канон объявляет о себе проверяемые вещи: «равные шаги ΔL ≈ 0.03 в OKLCH»,
# «hue удержан в 294±1», «янтарь всего в 9° от sem.warning», «ультрамарин
# даёт 4.0:1 и не проходит». Заявление, которое некому проверить, — не
# правило, а намерение (доктрина: правило, которое не проверяется, не
# существует). Поэтому числа считаются здесь из hex, а не переписываются
# из главы: если кто-то подвинет цвет, витрина покажет новую правду сама.
# --------------------------------------------------------------------------

def srgb_to_linear(channel):
    """0–255 → линейный sRGB 0–1."""
    value = channel / 255.0
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


def oklch(rgb):
    """(r,g,b) 0–255 → (L, C, H): светлота 0–1, хрома, тон в градусах.
    Матрицы — Björn Ottosson, OKLab."""
    red, green, blue = (srgb_to_linear(channel) for channel in rgb)
    long_ = 0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue
    medium = 0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue
    short = 0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue
    long_, medium, short = (cube_root(value) for value in (long_, medium, short))
    lightness = 0.2104542553 * long_ + 0.7936177850 * medium - 0.0040720468 * short
    green_red = 1.9779984951 * long_ - 2.4285922050 * medium + 0.4505937099 * short
    blue_yellow = 0.0259040371 * long_ + 0.7827717662 * medium - 0.8086757660 * short
    chroma = math.hypot(green_red, blue_yellow)
    hue = math.degrees(math.atan2(blue_yellow, green_red)) % 360.0
    return lightness, chroma, hue


def cube_root(value):
    return value ** (1.0 / 3.0) if value >= 0 else -((-value) ** (1.0 / 3.0))


def relative_luminance(rgb):
    """WCAG 2.x: яркость цвета."""
    red, green, blue = (srgb_to_linear(channel) for channel in rgb)
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue


def composite(rgb, alpha, over):
    """Альфа-белый — это не цвет, а рецепт: пока он не лёг на фон, контраст
    у него посчитать нельзя. Браузер смешивает в sRGB — здесь так же."""
    return tuple(alpha * rgb[index] + (1.0 - alpha) * over[index] for index in range(3))


def contrast_ratio(first, second):
    bright, dark = sorted((relative_luminance(first), relative_luminance(second)), reverse=True)
    return (bright + 0.05) / (dark + 0.05)


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

CANDIDATE_STATUS = "кандидат"

# Сайдкар высоту образца не обязан знать: он описывает чужой крупный файл,
# а не свой. Показываем столько и честно говорим в карточке, что это догадка.
DEFAULT_SIDECAR_HEIGHT = 720


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


def make_record(card, specimen, category):
    """Единая запись витрины: карточка + чем показывать образец. Часть и
    сайдкар приёмной различаются только этим, поэтому дальше — один код."""
    height = card.get("height")
    guessed = not isinstance(height, int)
    return {
        "card": card,
        "specimen": specimen.relative_to(ROOT / "design").as_posix() if specimen else None,
        "height": DEFAULT_SIDECAR_HEIGHT if guessed else height,
        "height_guessed": guessed,
        "category": category,
        "slug": card.get("slug") or (specimen.stem if specimen else "?"),
    }


def collect_parts():
    """Части категорий записями. Раскладку по зрелости делает не эта функция:
    папка говорит только о категории (README, «Три статуса»)."""
    records = []
    for folder, _title in CATEGORIES:
        directory = PARTS_DIR / folder
        if not directory.is_dir():
            continue
        for path in sorted(directory.glob("*.html")):
            card = read_card(path)
            if card:
                records.append(make_record(card, path, folder))
    return records


def collect_sidecars():
    """Приёмная: сайдкар .md описывает крупный неразобранный кусок, образец —
    соседний .html. Карточки #card внутри таких файлов нет и не будет — они
    приехали до контракта, и требовать от них порядка значило бы не пускать
    находки в систему вообще."""
    records = []
    if not CANDIDATES_DIR.is_dir():
        return records
    for path in sorted(CANDIDATES_DIR.glob("*.md")):
        fields, _body = parse_front_matter(path.read_text(encoding="utf-8"))
        if not fields:
            continue
        specimen = path.with_suffix(".html")
        records.append(make_record(fields, specimen if specimen.exists() else None, None))
    return records


def unquote(value):
    """Снимает парные кавычки и приводит голое целое к числу — как это делает
    настоящий YAML: «height: 240» там число, а не строка. Без этого карточка
    с честной высотой читалась как «высоты нет», и витрина показывала образец
    в 720px, уверяя, что высота не указана.
    YAML-библиотеки в проекте нет и не будет."""
    value = value.strip()
    for quote in ('"', "'"):
        if len(value) >= 2 and value.startswith(quote) and value.endswith(quote):
            return value[1:-1].replace(quote * 2, quote)
    if re.fullmatch(r"-?\d+", value):
        return int(value)
    return value


def parse_front_matter(text):
    """Front-matter между строками «---»: «ключ: значение» и списки «- пункт».
    Это не YAML целиком, а ровно та его подмножественная форма, которой
    пользуются сайдкары приёмной — зависимостей у проекта ноль."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}, text
    fields = {}
    key = None
    for index in range(1, len(lines)):
        line = lines[index]
        if line.strip() == "---":
            return fields, "\n".join(lines[index + 1:])
        stripped = line.strip()
        if not stripped:
            continue
        # Пункт списка: продолжает ключ, объявленный выше пустым значением.
        if stripped.startswith("- ") and key is not None and isinstance(fields.get(key), list):
            fields[key].append(unquote(stripped[2:]))
            continue
        if ":" in stripped:
            name, value = stripped.split(":", 1)
            key = name.strip()
            # Пустое значение — дальше либо список, либо ничего.
            fields[key] = unquote(value) if value.strip() else []
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


# Макет девятнадцати экранов: единственное место, где систему видно в работе.
MOCKUPS = "../docs/design/mockups/foundry-mockups.html"

# Образцы лестницы кеглей — реальные строки продукта. Lorem прячет ровно то,
# ради чего лестницу и смотрят (02 §13, дизайн от данных): длину, цифры,
# кириллицу и то, как «Вернуть на доработку» ведёт себя в 13 pt.
TYPE_SPECIMEN = {
    "hero": "Foundry AI",
    "display": "142",
    "title": "Ревью артефактов",
    "heading": "Ждёт твоего ревью",
    "body": "Questions · Research · Design · Structure · Plan · Worktree · Implement · PR",
    "body-em": "Вернуть на доработку",
    "caption": "backlog · in-progress · done · declined",
    "caption2": "0 4 8 12 16 итераций",
    "label": "Проекты",
    "mono": "git worktree add ../crispy-42a1f stage/implement",
    "mono-s": "42a1f · 1284 строки",
}

# Закреплённый словарь доменных метафор — канон 12 §3. Одно понятие — один
# символ, везде: синонимия иконок убивает выученность. Источник — проза главы;
# SF Symbols браузер не рисует (это продолжение шрифта San Francisco, а не
# картинки), поэтому доска показывает КАРТУ понятие→символ, а глиф живёт
# в приложении. Меняется метафора в каноне — меняется здесь.
ICON_METAPHORS = [
    ("Проект", "folder / folder.fill", "контейнер работ; узнаётся мгновенно, не спорит с доменными"),
    ("Change", "arrow.triangle.branch", "ветвление — единица изменения с git-природой"),
    ("Стадия", "circle.dotted → circle.lefthalf.filled → checkmark.circle.fill", "узел пайплайна; заполненность = прогресс"),
    ("Артефакт", "doc.text", "документ стадии — markdown и есть документ"),
    ("Снапшот / diff", "plus.forwardslash.minus", "+/- — интернациональный знак диффа (GitHub-школа)"),
    ("Ревью", "text.magnifyingglass", "читать пристально; лупа с текстом = разбор текста"),
    ("Комментарий", "text.bubble", "пузырь — вошедшая метафора; счётчик цифрой рядом, не в иконке"),
    ("Live-лог", "terminal", "моношрифт-консоль — донорская метафора Xcode/Terminal"),
    ("Стрим токенов", "waveform", "живой поток; держит variable-color-анимацию"),
    ("Луп / итерация", "arrow.2.circlepath", "круговые стрелки = повторение; счётчик рядом, не внутри"),
    ("Аналитика", "chart.xyaxis.line", "линия на осях = графики лупов"),
    ("Инбокс", "tray / tray.full", "системная метафора macOS Mail; пара empty/full — состояние формой"),
    ("Claude / агент", "орб (кастом)", "фирменный элемент; SF-фолбэк не брать, орб рисуем сами"),
]

# Статусы стадии — канон 12 §6. Форма ДУБЛИРУЕТ цвет (обязательный императив:
# 8% мужчин плохо различают красный/зелёный). Каждому статусу — свой глиф И
# свой цвет-токен; глиф-имя несёт форму, токен несёт цвет.
ICON_STATUSES = [
    ("Не начата", "circle.dotted", "text.disabled"),
    ("В работе", "circle.lefthalf.filled + пульс", "sem.info"),
    ("Ждёт ревью", "circle.fill + точка-бейдж", "brand.ultramarine"),
    ("Принята", "checkmark.circle.fill", "sem.success"),
    ("На доработке", "arrow.uturn.backward.circle.fill", "sem.warning"),
    ("Ошибка / блок", "exclamationmark.triangle.fill", "sem.error"),
]

# Ступени, которые складываются в лестницу светлоты. Остальные bg.* —
# накладки поверх текущего уровня, у них нет своей ступени (bg._role).
RAMP_GROUPS = [
    ("bg", ["base", "surface", "raised", "overlay"]),
]

# Порог WCAG для обычного текста. Недоступное WCAG 1.4.3 не нормирует —
# требовать от него контраста значило бы поднять ложную тревогу на доске.
CONTRAST_THRESHOLD = 4.5
CONTRAST_EXEMPT = {"text.disabled"}

# Ультрамарин в матрице текста стоит не по ошибке: text._role объявляет, что
# текстом он не бывает, и доска обязана показать, ПОЧЕМУ — 4.0:1 на bg.base.
# Правило, которое видно проваливающимся, не нуждается в заучивании.
CONTRAST_EXTRA_INKS = ["brand.ultramarine"]

# text.on-accent — тот же белый 100%, что и text.primary, и работа у него
# не на поверхностях, а на заливках. В матрице поверхностей он был бы вторым
# рисунком того же числа (11 §1.1): те же чернила, тот же ответ.
CONTRAST_SKIP_INKS = {"text.on-accent"}

# Заявленный контраст пишется в источнике с одним знаком после запятой,
# поэтому честная ошибка округления — до 0.05. Всё, что разъехалось сильнее,
# разъехалось не округлением.
CONTRAST_CLAIM_TOLERANCE = 0.055

STATUS_CHIP = {"принят": "chip-accepted", "кандидат": "chip-candidate", "отвергнут": "chip-rejected"}

# Разбиение прозы на фразы. Точка с пробелом и заглавной дальше — граница;
# «13-tokens.md», «§4.2» и «0.03» точками не режутся.
SENTENCE = re.compile(r"(?<=[.!?])\s+(?=[А-ЯЁA-Z«])")

# Метки запрета в прозе токенов. Список закрытый и короткий намеренно: он
# ловит то, что автор токена выделил САМ (капсом или прямым «не …»), и не
# пытается понять русский язык. Не поймал — значит, автор не выделил.
PROHIBITION = re.compile(
    r"НИКОГДА|ЗАПРЕЩ|ЖЁСТКОЕ ПРАВИЛО|отвергнут|"
    r"не возвращать|не применя|не используется|не хардкод|не перепрыгивает|"
    r"не смешив|не больше|не как |не бывает|"
    r"промежуточных значений нет|дублируется формой"
)

def escape(value):
    return html.escape(str(value), quote=True)


# Микротипографика по Бирману. Перенос строки не должен оставлять висеть предлог
# или уводить тире в начало следующей строки — там, где это грозит, ставим
# неразрывный пробел U+00A0. Функция вставляет ТОЛЬКО пробелы и потому безопасна
# для уже собранной разметки (<code>, <b>, <a>): пробелов внутри тегов нет,
# ломать нечего. Применяется к бегущей прозе доски, не к моно-идентификаторам.
NBSP = "\u00A0"
# Короткие слова, которым нельзя заканчивать строку: одно-, двух- и
# трёхбуквенные предлоги, союзы, частицы. Пробел после — неразрывный (слово
# уезжает на следующую строку вместе со своим существительным).
_HANG_WORDS = ("а в и к о с у я во да до же за из ко ли на не ни но ну об от по со то "
               "без для над под при про или что как чем")
_HANG = re.compile(r"(?<![^\s(«>—])(%s) " % "|".join(_HANG_WORDS.split()), re.IGNORECASE)
# Пробел перед тире — неразрывный (тире не начинает строку).
_DASH = re.compile(r"(\S)[ \t]+—")
# Число и следующее за ним слово/единица держатся вместе: «45 знаков», «13 pt».
_NUM = re.compile(r"(\d)[ \t]+(?=[А-Яа-яёA-Za-z])")


def typo(text):
    """Бегущая проза → та же проза с неразрывными пробелами Бирмана."""
    if not text:
        return text
    result = str(text)
    result = _DASH.sub(r"\1" + NBSP + "—", result)
    result = _NUM.sub(r"\1" + NBSP, result)
    # Два прохода: соседние короткие слова («и в поле») делят пробелы-границы,
    # и один re.sub оставил бы второе слово необработанным.
    for _ in range(2):
        result = _HANG.sub(lambda match: match.group(1) + NBSP, result)
    return result


def block_head(title, hint=""):
    """Заголовок блока и подпись-кикер. Подпись — проза, идёт через typo();
    так микротипографика Бирмана достаётся всем блокам из одного места, а не
    двенадцати россыпью. Заголовок и подпись экранируются на стороне вызова
    (одни литералы без спецсимволов, другие — уже escape-нутые значения)."""
    span = '<span class="hint">%s</span>' % typo(hint) if hint else ""
    return '  <div class="block-head"><h3>%s</h3>%s</div>' % (title, span)


def sentences(text):
    return [part.strip() for part in SENTENCE.split((text or "").strip()) if part.strip()]


def first_sentence(text):
    parts = sentences(text)
    return parts[0] if parts else ""


def rest_sentences(text):
    return sentences(text)[1:]


def prohibitions(text):
    """Фразы прозы, помеченные автором как запрет."""
    return [phrase for phrase in sentences(text) if PROHIBITION.search(phrase)]


# --------------------------------------------------------------------------
# Обложка
# --------------------------------------------------------------------------

def count_tokens(tokens):
    return sum(1 for _path, _token in iterate_tokens(tokens))


def board_cover(tokens, law_parts, candidate_parts, sidecars, rejected):
    """Единственная задача обложки — показать, что это спроектированная вещь.
    Цифры на ней не украшение: это состояние системы на момент сборки."""
    facts = [
        (count_tokens(tokens), "дизайн-токенов в источнике"),
        (len(law_parts), "принятых компонентов"),
        (len(candidate_parts), "на утверждении"),
        (len(sidecars), "в приёмной"),
        (len(rejected), "отклонено, с причиной"),
    ]
    lines = ['<section class="cover">']
    lines.append('  <p class="cover-mark">Foundry</p>')
    lines.append("  <h1>Design System</h1>")
    lines.append('  <p class="lede">%s</p>' % typo(
        "Не описание системы, а сама система, собранная в одном месте: "
        "каждая ступень цвета, кегль и отступ ниже — <b>не картинка решения, а решение</b>. "
        "Все значения — цвета, кегли, отступы, радиусы — приезжают из "
        "<code>tokens.json</code> при сборке (это и есть дизайн-токены); поменяется "
        "значение в источнике — поменяется эта страница."))
    lines.append('  <div class="cover-facts">')
    for number, caption in facts:
        lines.append('    <div class="cover-fact"><b>%d</b><span>%s</span></div>' % (number, escape(caption)))
    lines.append("  </div>")
    lines.append("</section>")
    return lines


# --------------------------------------------------------------------------
# 01 · Основа — секция, ради которой доска существует
# --------------------------------------------------------------------------

def ink_on(tokens, path):
    """Цвет подписи на цветной ступени витрина не выбирает вкусом, а считает:
    что контрастнее — белый или bg.base. Ровно там, где выбор переворачивается,
    и проходит граница text.on-accent («на пурпуре, мадженте и янтаре белый
    ЗАПРЕЩЁН»)."""
    token = find_token(tokens, path)
    rgb = resolve_rgb(tokens, token, path)
    base = resolve_rgb(tokens, find_token(tokens, "bg.base"), "bg.base")
    return "on-dark" if contrast_ratio((255, 255, 255), rgb) < contrast_ratio(base, rgb) else ""


def ramp_block(tokens, group_name, names, title, hint, prove_steps, block_id=None):
    """Лестница вместо сетки свотчей.

    Сетка свотчей показывает N цветов; лестница показывает N решений. Ступень
    видна только рядом с соседней — поэтому полоса непрерывна, и поэтому под
    ней стоит столбик длиной ∝ ΔL: правило «равные шаги ΔL ≈ 0.03» доска
    ОБЯЗАНА показать глазу, а не пересказать словами.
    """
    steps = []
    previous = None
    for name in names:
        path = "%s.%s" % (group_name, name)
        token = find_token(tokens, path)
        rgb = resolve_rgb(tokens, token, path)
        lightness, chroma, hue = oklch(rgb)
        steps.append({
            "path": path,
            "hex": resolve_hex(tokens, token, path),
            "L": lightness,
            "C": chroma,
            "H": hue,
            "delta": None if previous is None else lightness - previous,
            "role": token.get("role", ""),
            "ink": ink_on(tokens, path),
        })
        previous = lightness

    columns = "repeat(%d, 1fr)" % len(steps)
    lines = ['<div class="block" id="ramp-%s">' % escape(block_id or group_name)]
    lines.append(block_head(title, hint))
    lines.append('  <div class="ramp-band" style="grid-template-columns: %s">' % columns)
    for step in steps:
        lines.append('    <div class="ramp-cell %s" style="background: %s" data-token="%s" data-hex="%s">'
                     % (step["ink"], "var(%s)" % variable_name(step["path"]),
                        escape(step["path"]), escape(step["hex"])))
        lines.append("      <b>%s</b>" % escape(step["path"]))
        lines.append('      <span class="v">%s</span>' % escape(step["hex"]))
        lines.append('      <span class="v">L %.3f · C %.3f · H %.1f°</span>'
                     % (step["L"], step["C"], step["H"]))
        lines.append("    </div>")
    lines.append("  </div>")

    if prove_steps:
        lines.append('  <div class="ramp-deltas" style="grid-template-columns: %s">' % columns)
        for index, step in enumerate(steps):
            if step["delta"] is None:
                continue
            # Столбик длиной ∝ ΔL, посаженный на стык ступеней. Множитель —
            # данные; единица длины — токен, чтобы и здесь не было сырых px.
            width = "calc(var(--space-10) * %s)" % format_number(abs(step["delta"]) * 31.25)
            lines.append('    <span class="ramp-delta" style="grid-column: %d">' % (index + 1))
            lines.append('      <i style="width: %s"></i>' % width)
            lines.append("      <span>ΔL %+.3f</span>" % step["delta"])
            lines.append("    </span>")
        lines.append("  </div>")

    lines.append('  <ul class="roles">')
    for step in steps:
        lines.append('    <li><i class="swatch" style="background: %s"></i>'
                     '<span class="t">%s</span><span class="r">%s</span></li>'
                     % ("var(%s)" % variable_name(step["path"]), escape(step["path"]),
                        escape(step["role"])))
    lines.append("  </ul>")
    lines.append("</div>")
    return lines


def states_block(tokens):
    """Статичная доска умеет нарисовать только картинку ховера. Эта — ховерится."""
    lines = ['<div class="block" id="ramp-states">']
    lines.append(block_head("Состояния поверхности",
                            "наведи и нажми — это не картинка состояния, а состояние"))
    lines.append('  <div class="states">')
    rows = [
        ("bg.hover", "Вернуть спеку на доработку", "покой → наведи"),
        ("bg.pressed", "Собрать PR из ветки stage/implement", "наведи → нажми"),
        ("bg.selected", "Дифф спеки: блоками и словами", "выбранная строка"),
    ]
    for path, text, hint in rows:
        token = find_token(tokens, path)
        selected = " selected" if path == "bg.selected" else ""
        lines.append('    <div class="row%s" data-token="%s"><span class="t">%s</span>'
                     '<span class="m">%s · %s</span></div>'
                     % (selected, escape(path), escape(text), escape(path), escape(hint)))
    lines.append("  </div>")
    lines.append('  <ul class="roles">')
    for path, _text, _hint in rows:
        token = find_token(tokens, path)
        lines.append('    <li><i class="swatch" style="background: %s"></i>'
                     '<span class="t">%s</span><span class="r">%s</span></li>'
                     % ("var(%s)" % variable_name(path), escape(path), escape(token.get("role", ""))))
    lines.append("  </ul>")
    lines.append("</div>")
    return lines


def contrast_payload(tokens):
    """Данные для счёта контраста в браузере. Считает страница, а не автор:
    таблица чисел в главе — это утверждение, а посчитанное при читателе —
    доказательство. Разница между дизайн-системой и стайлгайдом ровно тут."""
    surfaces = []
    for name in ["base", "surface", "raised", "overlay"]:
        path = "bg.%s" % name
        surfaces.append({"path": path, "rgb": resolve_rgb(tokens, find_token(tokens, path), path)})

    inks = []
    for name, token in tokens["text"].items():
        if is_documentation_key(name):
            continue
        path = "text.%s" % name
        if path in CONTRAST_SKIP_INKS:
            continue
        inks.append({
            "path": path,
            "rgb": resolve_rgb(tokens, token, path),
            "alpha": token.get("alpha", 1.0),
            "role": token.get("role", ""),
            "exempt": path in CONTRAST_EXEMPT,
        })
    for name, token in tokens["sem"].items():
        if is_documentation_key(name) or name.endswith("-fill") or name.endswith("-border"):
            continue
        path = "sem.%s" % name
        inks.append({"path": path, "rgb": resolve_rgb(tokens, token, path),
                     "alpha": token.get("alpha", 1.0), "role": token.get("role", ""), "exempt": False})
    for path in CONTRAST_EXTRA_INKS:
        token = find_token(tokens, path)
        inks.append({"path": path, "rgb": resolve_rgb(tokens, token, path),
                     "alpha": 1.0, "role": token.get("role", ""), "exempt": False})

    accents = []
    for name, token in tokens["brand"].items():
        if is_documentation_key(name) or token.get("kind") != "color":
            continue
        path = "brand.%s" % name
        accents.append({"path": path, "rgb": resolve_rgb(tokens, token, path)})

    on_accent = find_token(tokens, "text.on-accent")
    return {
        "surfaces": surfaces,
        "inks": inks,
        "accents": accents,
        "onAccent": {"path": "text.on-accent",
                     "rgb": resolve_rgb(tokens, on_accent, "text.on-accent"),
                     "alpha": on_accent.get("alpha", 1.0)},
        "threshold": CONTRAST_THRESHOLD,
        # Чем красить подпись в клетке: красным провала и почти-чёрным —
        # оба берутся из источника, а не придумываются в скрипте.
        "error": resolve_rgb(tokens, find_token(tokens, "sem.error"), "sem.error"),
        "base": resolve_rgb(tokens, find_token(tokens, "bg.base"), "bg.base"),
    }


def contrast_drift(tokens):
    """Токены, у которых заявленный контраст разошёлся с посчитанным.

    Поле «contrast» в источнике — это утверждение, сделанное когда-то рукой.
    Утверждение живёт ровно до первой правки цвета: подвинули лестницу —
    и число в поле стало археологией, а выглядит как факт. Доска считает
    контраст сама, а значит — обязана сказать, где источник врёт. Это и есть
    разница между «система заявляет о себе» и «система знает о себе»:
    заявление проверить некому, а посчитанное расходится вслух.
    """
    base = resolve_rgb(tokens, find_token(tokens, "bg.base"), "bg.base")
    drifted = []
    for path, token in iterate_tokens(tokens):
        claim = token.get("contrast")
        if not claim:
            continue
        try:
            claimed = float(str(claim).split(":")[0])
        except ValueError:
            continue
        rgb = resolve_rgb(tokens, token, path)
        actual = contrast_ratio(composite(rgb, token.get("alpha", 1.0), base), base)
        if abs(actual - claimed) > CONTRAST_CLAIM_TOLERANCE:
            drifted.append((path, claimed, actual))
    return drifted


def contrast_block(tokens):
    ultramarine = resolve_rgb(tokens, find_token(tokens, "brand.ultramarine"), "brand.ultramarine")
    base = resolve_rgb(tokens, find_token(tokens, "bg.base"), "bg.base")
    failure = contrast_ratio(ultramarine, base)
    drifted = contrast_drift(tokens)

    lines = ['<div class="block" id="contrast">']
    lines.append(block_head("Контраст",
                            "посчитан браузером сейчас, при открытии страницы: "
                            "альфа-белый сперва кладётся на фон, потом берётся WCAG — "
                            "иначе цифра врёт"))
    lines.append('  <div class="grid">')

    lines.append('    <div class="col-8">')
    lines.append('      <table class="matrix" id="matrix-inks">')
    lines.append("        <thead><tr><th>Чернила</th></tr></thead>")
    lines.append("        <tbody></tbody>")
    lines.append("      </table>")
    lines.append('      <p class="matrix-note">%s — WCAG 1.4.3 недоступное не нормирует: '
                 "порог %s к нему не применяется, и провалом это не помечено.</p>"
                 % (", ".join("<code>%s</code>" % escape(path) for path in sorted(CONTRAST_EXEMPT)),
                    format_number(CONTRAST_THRESHOLD)))
    lines.append('      <p class="verdict-note">Ультрамарин <code>brand.ultramarine</code> даёт '
                 "<b>%.1f:1</b> на <code>bg.base</code> — порог 4.5 не взят, и это видно "
                 "в таблице, а не в примечании. Поэтому текстом всегда "
                 "<code>text.accent</code>. Правило, которое видно проваливающимся, "
                 "не нужно заучивать.</p>" % failure)
    lines.append("    </div>")

    lines.append('    <div class="col-4">')
    lines.append('      <table class="matrix" id="matrix-accents">')
    lines.append("        <thead><tr><th>Заливка</th></tr></thead>")
    lines.append("        <tbody></tbody>")
    lines.append("      </table>")
    lines.append('      <p class="verdict-note">%s</p>'
                 % escape(find_token(tokens, "text.on-accent").get("role", "")))
    lines.append("    </div>")
    lines.append("  </div>")

    if drifted:
        lines.append('  <div class="finding">')
        lines.append("    <p><b>Источник разошёлся сам с собой.</b> У этих дизайн-токенов поле "
                     "<code>contrast</code> в <code>tokens.json</code> не совпало с тем, "
                     "что доска только что посчитала:</p>")
        lines.append('    <ul class="roles">')
        for path, claimed, actual in drifted:
            lines.append('      <li><i class="swatch" style="background: %s"></i>'
                         '<span class="t">%s</span><span class="r">заявлено %.1f:1 — '
                         "на деле <b>%.2f:1</b></span></li>"
                         % ("var(%s)" % variable_name(path), escape(path), claimed, actual))
        lines.append("    </ul>")
        lines.append("    <p>Числа не выдуманы: заявленные совпадают с прежней лестницей "
                     "поверхностей, снятой 2026-07-17. У <code>text.*</code> их тогда "
                     "пересчитали, у этих — забыли, и <code>bg._role</code> до сих пор "
                     "уверяет, что «все контрасты пересчитаны». Поле <code>contrast</code> "
                     "руками не поддерживается: расхождение видно только тому, кто считает, "
                     "а не переписывает.</p>")
        lines.append("  </div>")
    lines.append("</div>")
    return lines


def typography_block(tokens):
    """Лестница в натуральную величину. Таблица чисел не показывает кегль —
    она о нём рассказывает; 13 pt узнаётся только тем, что он 13 pt."""
    # Без block-head: секция «Типографика» уже представлена заголовком и лидом
    # секции; повтор имени над единственным блоком — дубль, который Горбунов
    # режет первым (лид несёт ту же мысль). Лестница начинается сразу.
    lines = ['<div class="block" id="type">']
    lines.append('  <div class="ladder">')
    for name, token in tokens["type"].items():
        if is_documentation_key(name):
            continue
        path = "type.%s" % name
        variable = variable_name(path)
        style = ("font-family: var(%s-family); font-size: var(%s-size); "
                 "line-height: var(%s-leading); font-weight: var(%s-weight)"
                 % (variable, variable, variable, variable))
        if token.get("caps"):
            style += "; text-transform: var(%s-caps)" % variable
        if token.get("tracking"):
            style += "; letter-spacing: var(%s-tracking)" % variable
        measures = "%s/%s · %s" % (format_number(token["size"]), format_number(token["leading"]),
                                   token["weight"])
        if token.get("tracking"):
            measures += " · %s" % token["tracking"]
        lines.append('    <div class="ladder-rung">')
        lines.append('      <div class="ladder-meta">')
        lines.append('        <span class="t" data-token="%s">%s</span>' % (escape(path), escape(path)))
        lines.append('        <span class="d">%s</span>' % escape(measures))
        lines.append('        <span class="j">%s</span>' % escape(token.get("role", "")))
        lines.append("      </div>")
        # Запасного варианта здесь нет намеренно. Раньше строка бралась из
        # token["role"] — и лестница молча набирала кеглем 34 описание кегля 34:
        # образцом становилась документация об образце, ровно та болезнь, от
        # которой доска и лечит. Забыл строку — сборка не соберётся.
        if name not in TYPE_SPECIMEN:
            raise ValueError(
                "«type.%s» нечем показать: добавь реальную строку продукта в "
                "TYPE_SPECIMEN (design/build.py). Не роль токена и не lorem — "
                "строку, которая правда стоит на экране этим кеглем." % name)
        lines.append('      <div class="ladder-sample" style="%s">%s</div>'
                     % (style, escape(TYPE_SPECIMEN[name])))
        lines.append("    </div>")
    lines.append("  </div>")

    # Кража у Geist: имя даёт работа, а не размер. У нас это уже так —
    # и это единственное место, где видно, что так.
    body = tokens["type"]["body"]
    body_em = tokens["type"]["body-em"]
    if body["size"] == body_em["size"]:
        lines.append('  <div class="twin">')
        for name, token in (("body", body), ("body-em", body_em)):
            variable = variable_name("type.%s" % name)
            lines.append("    <div>")
            lines.append('      <span class="label">type.%s · %s/%s %s</span>'
                         % (escape(name), format_number(token["size"]),
                            format_number(token["leading"]), escape(token["weight"])))
            lines.append('      <span style="font-family: var(%s-family); font-size: var(%s-size); '
                         'line-height: var(%s-leading); font-weight: var(%s-weight)">%s</span>'
                         % (variable, variable, variable, variable,
                            escape(TYPE_SPECIMEN.get(name, ""))))
            lines.append('      <span class="hint">%s</span>' % escape(token.get("role", "")))
            lines.append("    </div>")
        lines.append("  </div>")
        lines.append('  <p class="section-lede" style="margin-top: var(--space-3)">%s</p>' % typo(
            "Один кегль — два токена. Имя в шкале даёт работа, а не размер: "
            "<code>type.body</code> и <code>type.body-em</code> оба %s pt, и это не дубль, "
            "а два разных решения." % format_number(body["size"])))
    lines.append("</div>")
    return lines


def spacing_block(tokens):
    """Шкала, измеряющая сама себя: столбик длиной ровно в свой токен.
    Таблица чисел этого не умеет — 24 pt узнаются только тем, что они 24 pt."""
    base_pt = min(token["pt"] for name, token in tokens["space"].items()
                  if not is_documentation_key(name))
    # Без block-head — см. типографику: единственный блок секции не повторяет
    # её имя. Линейка отступов начинается сразу под лидом.
    lines = ['<div class="block" id="space">']
    lines.append('  <div class="grid">')

    lines.append('    <div class="col-6">')
    lines.append('      <div class="bars">')
    for name, token in tokens["space"].items():
        if is_documentation_key(name):
            continue
        path = "space.%s" % name
        pt = token["pt"]
        # Рабочая единица 8pt светится, промежуточные 4pt-ступени приглушены:
        # разница между базой и рабочей единицей — это решение, а не пояснение.
        off = "" if pt % 8 == 0 else " off"
        lines.append('        <div class="bar-row%s" data-token="%s" title="%s">' % (off, escape(path), escape(token.get("role", ""))))
        lines.append('          <span class="t">%s</span>' % escape(path))
        lines.append('          <span class="n">%s pt</span>' % format_number(pt))
        lines.append('          <span class="x">×%s</span>' % format_number(pt / base_pt))
        lines.append('          <i style="width: var(%s)"></i>' % variable_name(path))
        lines.append("        </div>")
    lines.append("      </div>")
    lines.append('      <p class="hint" style="margin-top: var(--space-4); color: var(--text-tertiary)">'
                 "База %s pt; рабочая единица 8 pt — яркие столбики. Приглушённые — "
                 "4pt-ступени между ними.</p>" % format_number(base_pt))
    lines.append("    </div>")

    # Инвариант Бирмана из space._role, нарисованный. Правило про внутреннее
    # и внешнее словами не показывается: его видно или не видно.
    lines.append('    <div class="col-6">')
    lines.append('      <div class="inout">')
    cases = [
        ("good", "✓", "Внутри группы space.2, между группами space.5 — две группы, "
                      "и это видно без единой линейки."),
        ("bad", "×", "Внутри и между — одинаковый space.3. Групп нет: шесть строк "
                     "равномерной каши."),
    ]
    for kind, mark, text in cases:
        lines.append('        <div class="inout-case %s">' % kind)
        lines.append('          <div class="inout-groups">')
        for _group in range(2):
            lines.append('            <div class="inout-group">'
                         '<i class="line"></i><i class="line"></i><i class="line"></i></div>')
        lines.append("          </div>")
        lines.append('          <p><span class="verdict-mark">%s</span> %s</p>' % (mark, typo(escape(text))))
        lines.append("        </div>")
    lines.append("      </div>")
    lines.append("    </div>")
    lines.append("  </div>")
    lines.append("</div>")
    return lines


def radius_block(tokens):
    """Концентрика, нарисованная. И заодно — проверка: шкала радиусов
    воспроизводит сама себя шагом в один space.1, или уже нет."""
    radius = tokens["radius"]
    space_1 = tokens["space"]["1"]["pt"]
    chain = []
    for outer, inner in (("xl", "l"), ("l", "m")):
        expected = radius[outer]["pt"] - space_1
        chain.append({
            "outer": outer, "inner": inner,
            "outer_pt": radius[outer]["pt"], "inner_pt": radius[inner]["pt"],
            "expected": expected, "holds": expected == radius[inner]["pt"],
        })

    # Без block-head — см. типографику. Концентрика начинается сразу под лидом.
    lines = ['<div class="block" id="radius">']
    lines.append('  <div class="grid">')
    lines.append('    <div class="col-6">')
    lines.append('      <div class="nest nest-l1" data-token="radius.xl">')
    lines.append('        <div class="nest-l2" data-token="radius.l">')
    lines.append('          <div class="nest-l3" data-token="radius.m">Принять</div>')
    lines.append("        </div>")
    lines.append("      </div>")
    lines.append("    </div>")
    lines.append('    <div class="col-6">')
    lines.append('      <ul class="nest-legend">')
    for link in chain:
        mark = "<b>сходится</b>" if link["holds"] else "НЕ сходится: в шкале %s pt" % format_number(link["inner_pt"])
        lines.append("        <li>radius.%s %s − space.1 %s = %s → radius.%s · %s</li>"
                     % (escape(link["outer"]), format_number(link["outer_pt"]),
                        format_number(space_1), format_number(link["expected"]),
                        escape(link["inner"]), mark))
    lines.append("      </ul>")
    if all(link["holds"] for link in chain):
        lines.append('      <p class="hint" style="color: var(--text-secondary); '
                     'margin-top: var(--space-3)">Шкала радиусов построена так, что '
                     "концентрическое правило шагом в один <code>space.1</code> "
                     "попадает ровно в следующий токен: %s. Это не совпадение "
                     "и не украшение — это и есть система." %
                     escape(" → ".join(["%s" % format_number(chain[0]["outer_pt"])]
                                       + [format_number(link["inner_pt"]) for link in chain])))
        lines.append("      </p>")
    lines.append("    </div>")
    lines.append("  </div>")
    lines.append("</div>")
    return lines


def layout_block(tokens):
    """Модульная сетка, показанная собой, а не пересказанная.

    Три уровня из канона 02: макро — панели окна в натуральную величину
    (pt→px один к одному, как везде на доске); микро — 12 колонок с гаттером
    в тот самый space-токен; мера — колонка чтения ровно в 66 знаков, то самое
    правило, которому обязана подчиняться и эта страница. Значения панелей
    приезжают из `_layout` в tokens.json (док-ключ: панель окна — забота
    приложения, не документа), гаттер и поля — из space-токенов."""
    layout = tokens["_layout"]
    panels = layout["_panels"]
    measure = layout["_measure"]
    columns = layout["_columns"]

    lines = ['<div class="block" id="layout-macro">']
    lines.append(block_head("Панели окна — макросетка",
                            "ширины в натуральную величину, pt→px 1:1: "
                            "панель — это «колонка» приложения (02 §8)"))
    # Окно в масштабе: сайдбар и инспектор — фиксированной ширины своим pt,
    # контент забирает остаток (min 480). Это не картинка окна, а окно в меру.
    lines.append('  <div class="win">')
    for panel in panels:
        default = panel["default"]
        if default is None:
            # Контент/деталь: ∞, тянется и сжимается до остатка. min-width:0 —
            # иначе минимум 480 распирает окно шире колонки доски и режет инспектор;
            # честную ширину «мин 480pt» несёт подпись и легенда, а не распор.
            style = "flex: 1 1 auto; min-width: 0"
            width_label = "мин %dpt · ∞" % panel["min"]
        else:
            style = "flex: 0 0 %dpx" % default
            width_label = "%dpt" % default
        lines.append('    <div class="win-panel" style="%s">' % style)
        lines.append('      <b>%s</b>' % escape(panel["name"]))
        lines.append('      <span class="role">%s</span>' % escape(panel["role"]))
        lines.append('      <span class="w">%s</span>' % escape(width_label))
        lines.append("    </div>")
    lines.append("  </div>")
    # Легенда: мин / по умолчанию / макс и поведение при ресайзе — данные панели.
    lines.append('  <ul class="panels">')
    for panel in panels:
        default = "—" if panel["default"] is None else "%d" % panel["default"]
        maximum = "∞" if panel["max"] is None else "%d" % panel["max"]
        lines.append('    <li><span class="t">%s</span>'
                     '<span class="n">%d / %s / %s pt</span>'
                     '<span class="g">%s</span></li>'
                     % (escape(panel["name"]), panel["min"], default, maximum,
                        escape(panel["grow"])))
    lines.append("  </ul>")
    lines.append("</div>")

    lines.append('<div class="block" id="layout-micro">')
    lines.append(block_head("Микросетка и мера",
                            "%d колонок, единый гаттер space.4; колонка чтения держит "
                            "меру %d–%d знаков" % (columns, measure["min"], measure["max"])))
    lines.append('  <div class="grid">')
    # Микро: 12 колонок с гаттером в space.4. Элемент занимает целое число колонок.
    lines.append('    <div class="col-6">')
    lines.append('      <div class="cols">')
    for _index in range(columns):
        lines.append('        <i></i>')
    lines.append("      </div>")
    lines.append('      <p class="hint" style="margin-top: var(--space-3); color: var(--text-tertiary)">'
                 "%d колонок, гаттер <code>space.4</code> (16pt), в плотных местах "
                 "<code>space.3</code> (12pt). Элемент занимает целое число колонок — "
                 "между колонками ничего не висит.</p>" % columns)
    lines.append("    </div>")
    # Мера чтения: колонка ровно в 66 знаков. Правило, которому подчинена и доска.
    lines.append('    <div class="col-6">')
    lines.append('      <div class="measure">')
    lines.append('        <div class="measure-col">Колонка чтения держит меру: глаз '
                 "не теряет строку на обратном пути и не спотыкается о частокол "
                 "переносов. На широком окне контент не растягивается во всю ширь, "
                 "а держит эти знаки — остальное уходит в поля.</div>")
    lines.append('        <span class="measure-mark">%d знаков · оптимум ~%d · '
                 "«широкое окно → поля, не длина строки»</span>" % (measure["max"], measure["opt"]))
    lines.append("      </div>")
    lines.append("    </div>")
    lines.append("  </div>")
    lines.append("</div>")
    return lines


def motion_block(tokens):
    """Движение честно показывается только движением. Переход запускается
    по интервалу, потому что переход — это переход, а не цикл: гонять его
    туда-обратно значило бы соврать про кривую (обратный ход ease-out —
    это ease-in)."""
    lines = ['<div class="block" id="motion">']
    lines.append(block_head("Движение",
                            "живьём, теми самыми токенами; при "
                            "<code>prefers-reduced-motion</code> — молчит"))
    for name, token in tokens["motion"].items():
        if is_documentation_key(name):
            continue
        path = "motion.%s" % name
        milliseconds = token.get("ms")
        if milliseconds is None:
            value = "нет длительности · %s" % token["easing"]
        else:
            value = "%d мс · %s" % (milliseconds, token["easing"])
        lines.append('  <div class="motion-row">')
        lines.append('    <span class="t" data-token="%s">%s</span>' % (escape(path), escape(path)))
        lines.append('    <span class="d">%s</span>' % escape(value))
        lines.append('    <span class="motion-track"><i class="motion-dot %s"></i></span>' % escape(name))
        lines.append("  </div>")
        lines.append('  <p class="hint" style="padding-bottom: var(--space-3); '
                     'color: var(--text-tertiary)">%s</p>' % escape(token.get("role", "")))
    lines.append('  <p class="verdict-note" style="border-left-color: var(--sem-warning); '
                 'background: var(--sem-warning-fill)"><code>motion.live</code> — состояние, '
                 "а не переход: длительности у него в источнике нет, и доска её "
                 "не выдумывает. Пульс выше показан, но его период — не дизайн-токен. "
                 "Видимый долг, а не решение.</p>")
    lines.append("</div>")
    return lines


def glow_block(tokens):
    """Рецепт разобран на слои и собран обратно — на том, ради чего он есть.

    И заодно вскрывается дыра: слои живут константами в build.py, а не
    в tokens.json. Доска показывает её, а не заминает: система, которая
    не умеет назвать свои дыры, — стайлгайд."""
    accent = find_token(tokens, "glow.accent")
    rgb = resolve_rgb(tokens, accent, "glow.accent")
    inner = "0 0 %dpx %s" % (GLOW_INNER_BLUR, rgba_text(rgb, GLOW_INNER_ALPHA))
    outer = "0 0 %dpx %s" % (GLOW_OUTER_BLUR, rgba_text(rgb, GLOW_OUTER_ALPHA))

    lines = ['<div class="block" id="glow">']
    lines.append(block_head("Свечение",
                            "фирменная замена тени: свет в темноте, а не тень под предметом"))
    lines.append('  <div class="glow-lab">')
    cases = [
        ("покой", "", "заливка без свечения"),
        ("слой 1 · внутренний ореол", "box-shadow: %s" % inner,
         "blur %d @ %d%%" % (GLOW_INNER_BLUR, GLOW_INNER_ALPHA * 100)),
        ("слой 2 · внешний", "box-shadow: %s" % outer,
         "blur %d @ %d%%" % (GLOW_OUTER_BLUR, GLOW_OUTER_ALPHA * 100)),
        ("glow.accent · слой 1 + слой 2", "box-shadow: var(--glow-accent)", "токен целиком"),
    ]
    for title, style, hint in cases:
        lines.append('    <div class="glow-case">')
        lines.append('      <span class="glow-btn" style="%s">Принять</span>' % style)
        lines.append('      <span class="label">%s</span>' % escape(title))
        lines.append('      <span class="hint" style="color: var(--text-tertiary)">%s</span>' % escape(hint))
        lines.append("    </div>")
    lines.append('    <div class="glow-case">')
    lines.append('      <span class="glow-btn hoverable">Принять</span>')
    lines.append('      <span class="label">живьём · наведи</span>')
    lines.append('      <span class="hint" style="color: var(--text-tertiary)">'
                 "hover primary — единственное место, где свечение вообще бывает</span>")
    lines.append("    </div>")
    lines.append("  </div>")
    lines.append('  <p class="verdict-note" style="border-left-color: var(--sem-warning); '
                 'background: var(--sem-warning-fill)">Слои рецепта — blur %d @ %d%% и '
                 "blur %d @ %d%% — живут константами в <code>design/build.py</code>, "
                 "а не в <code>tokens.json</code>. Токенов у них нет: цвет свечения "
                 "система назвать умеет, а его геометрию — нет. Дыра нашлась ровно "
                 "потому, что доску пришлось собрать из источника."
                 % (GLOW_INNER_BLUR, GLOW_INNER_ALPHA * 100, GLOW_OUTER_BLUR, GLOW_OUTER_ALPHA * 100))
    lines.append("</div>")
    return lines


def foundation_verdict(tokens, groups):
    """«Можно / Нельзя» токеновой секции собирается из прозы самих токенов:
    первая фраза роли группы — правило, фразы с метками запрета — запрет. Ни
    одной строки тут не написано руками, и это принципиально: суждение,
    переписанное в доску вручную, немедленно разъезжается с источником.

    Суждение сужено до групп, которые именно ЭТА секция показала: «Можно»
    закрывает ровно то, что читатель только что видел доказанным. Прежде
    основа была одной секцией и брала все группы разом; теперь цвет,
    типографика, отступы и анимации — разные секции, и каждая отвечает за
    свои группы. Запрет при этом не теряется: группы секций разбивают
    источник без остатка (проверено — вся проза запретов лежит в этих
    группах), так что каждый «Нельзя» появляется ровно один раз, там, где
    показана его группа."""
    can = []
    cant = []
    for group_name in groups:
        group = tokens.get(group_name)
        if not isinstance(group, dict):
            continue
        role = group.get("_role")
        if role:
            can.append((group_name, first_sentence(role)))
            for phrase in prohibitions(" ".join(rest_sentences(role))):
                cant.append((group_name, phrase))
        for token_name, token in group.items():
            if is_documentation_key(token_name) or not isinstance(token, dict):
                continue
            for phrase in prohibitions(token.get("role", "")):
                cant.append(("%s.%s" % (group_name, token_name), phrase))
    return can, cant


def render_verdict(can, cant, can_title, cant_title):
    lines = ['<div class="verdict">']
    for kind, title, items in (("can", can_title, can), ("cant", cant_title, cant)):
        lines.append('  <div class="%s">' % kind)
        lines.append("    <h3>%s</h3>" % escape(title))
        lines.append("    <ul>")
        for item in items:
            # Ровно один элемент внутри li: маркер рисует ::before и он же
            # занимает первую колонку сетки. Второй пустой span сделал бы
            # ссылку, текст и раскрытие тремя отдельными ячейками — и строка
            # рассыпалась бы по слову на строку.
            lines.append("      <li><span>%s</span></li>" % typo(item))
        lines.append("    </ul>")
        lines.append("  </div>")
    lines.append("</div>")
    return lines


# Ленты токеновых секций. Блоки те же, что рисовали единую «Основу», —
# просто разложены по концретным категориям доски. Значения по-прежнему
# приезжают из tokens.json: секция «Цвета» собирается из тех же ramp_block
# и contrast_block, а не из нового кода.
def colors_blocks(tokens):
    lines = []
    lines.extend(ramp_block(
        tokens, "bg", ["base", "surface", "raised", "overlay"],
        "Поверхности — лестница светлоты",
        "четыре ступени, а не четыре цвета: у каждой своя работа, "
        "и шаг между ними обязан быть равным", True))
    lines.extend(states_block(tokens))
    lines.extend(ramp_block(
        tokens, "brand", ["ultramarine", "purple", "magenta"],
        "Фирменная гамма",
        "аналоговая гамма — по смежным тонам (OKLCH hue 266 → 293 → 316); "
        "где подпись темнеет, там граница text.on-accent", False))
    lines.extend(ramp_block(
        tokens, "brand", ["amber"],
        "Янтарь — только знак",
        "в гамму не входит и НИКОГДА не статус: только логотип «Foundry AI». "
        "От sem.warning всего 9° по тону — глаз не различит, роли разводит "
        "дисциплина, а не глаз", False, block_id="brand-amber"))
    lines.extend(ramp_block(
        tokens, "sem", ["success", "warning", "error", "info"],
        "Семантика",
        "смысл, а не украшение: цвет всегда дублируется формой", False))
    lines.extend(contrast_block(tokens))
    return lines


def typography_blocks(tokens):
    return typography_block(tokens)


def layout_blocks(tokens):
    return layout_block(tokens)


def spacing_blocks(tokens):
    return spacing_block(tokens)


def radius_blocks(tokens):
    return radius_block(tokens)


def animation_blocks(tokens):
    return motion_block(tokens) + glow_block(tokens)


def board_foundation(tokens, section):
    """Токеновая секция: её блоки, затем «Можно / Нельзя» по её же группам."""
    lines = list(section["blocks"](tokens))
    can, cant = foundation_verdict(tokens, section["groups"])
    # Ведущее подчёркивание — служебная метка док-группы (_layout): читателю
    # вердикта она ни к чему, а «layout — …» читается как имя категории.
    can_items = ["<code>%s</code> — %s" % (escape(path.lstrip("_")), escape(text)) for path, text in can]
    cant_items = ["<code>%s</code> — %s" % (escape(path.lstrip("_")), escape(text)) for path, text in cant]
    lines.extend(render_verdict(can_items, cant_items,
                                "Можно — правило группы",
                                "Нельзя — запреты, которыми дизайн-токены помечены сами"))
    return lines


# --------------------------------------------------------------------------
# Части
# --------------------------------------------------------------------------

def render_part(record):
    """Часть на доске — это её образец.

    Образец занимает всё; имя, слаг и статус — подпись под ним. Прозы тут
    нет ни строки: «зачем» и «никогда» уехали в суждение, закрывающее
    секцию. Причина не в экономии места, а в потолке: текста на доске
    читается заголовок и две строки — всё, что длиннее, не читает никто,
    и пятнадцать строк прозы в карточке просто прячут образец.
    """
    card = record["card"]
    status = card.get("status", "?")
    chip_class = STATUS_CHIP.get(status, "chip-candidate")

    lines = ['<article class="part" id="part-%s">' % escape(record["slug"])]
    lines.append('  <div class="part-stage">')
    if record["specimen"]:
        lines.append('    <iframe src="%s" height="%d" loading="lazy" title="%s"></iframe>'
                     % (escape(record["specimen"]), record["height"], escape(card.get("name", ""))))
    else:
        lines.append('    <p class="stage-note">образца нет — файла рядом с карточкой не нашлось</p>')
    lines.append("  </div>")
    if record["specimen"] and record["height_guessed"]:
        lines.append('  <p class="stage-note">высота образца в карточке не указана — '
                     "доска показывает %dpx и может врать</p>" % DEFAULT_SIDECAR_HEIGHT)

    lines.append('  <div class="part-meta">')
    lines.append("    <h4>%s</h4>" % escape(card.get("name", record["slug"])))
    lines.append('    <span class="slug">%s</span>' % escape(record["slug"]))
    lines.append('    <span class="chip %s">%s</span>' % (chip_class, escape(status)))
    lines.append('    <span class="spacer"></span>')
    refs = []
    for chapter in card.get("canon") or []:
        refs.append('<a href="../docs/design/%s">%s</a>' % (escape(chapter), escape(chapter)))
    if "swift" in card:
        refs.append("<code>%s</code>" % escape(card["swift"]) if card["swift"] else "реализации нет")
    if refs:
        lines.append('    <span class="refs">%s</span>' % " · ".join(refs))
    lines.append("  </div>")

    if card.get("tokens"):
        lines.append('  <div class="part-tokens">')
        for token in card["tokens"]:
            lines.append('    <span data-token="%s">%s</span>' % (escape(token), escape(token)))
        lines.append("  </div>")

    # Долг и родословная — за раскрытием. Оба честные и оба нужны, но оба
    # прозой в абзац: у сайдкаров приёмной долг бывает и на пять строк.
    # Абзац в карточке прячет образец, а статус-чип уже сказал главное —
    # «кандидат, законом не является». Текст остаётся в DOM: ⌘F найдёт.
    if card.get("debt"):
        lines.append('  <details class="debt">')
        lines.append("    <summary>долг</summary>")
        lines.append("    <p>%s</p>" % escape(card["debt"]))
        lines.append("  </details>")

    lines.append("  <details>")
    lines.append("    <summary>родословная</summary>")
    lines.append("    <p>%s</p>" % escape(card.get("lineage", "—")))
    lines.append("  </details>")
    lines.append("</article>")
    return lines


def compress(text):
    """Первая фраза видна, остальное — за раскрытием «+N».

    Единственный приём сжатия на доске, и он один на всё: суждение о части,
    причина отказа, роль токена. Первая фраза — не произвол: автор кладёт
    главное первым, и поле «никогда» тем и дорого, что читается без клика.
    Хвост остаётся в DOM — ⌘F по доске находит и его, то есть ничего
    не потеряно, только убрано с глаз.
    """
    head = first_sentence(text)
    tail = rest_sentences(text)
    if not tail:
        return escape(head)
    return '%s<details class="more"><summary>+%d</summary><p>%s</p></details>' % (
        escape(head), len(tail), escape(" ".join(tail)))


def part_verdict_line(record, field):
    """Строка суждения: часть, сжатая до первой фразы."""
    card = record["card"]
    return '<a href="#part-%s">%s</a>%s— %s' % (escape(record["slug"]),
                                                escape(card.get("name", record["slug"])),
                                                NBSP,
                                                typo(compress(card.get(field) or "—")))


def board_parts(records):
    lines = []
    if not records:
        return lines
    lines.append('<div class="grid">')
    for record in records:
        lines.append('  <div class="col-12">')
        lines.extend("    " + line for line in render_part(record))
        lines.append("  </div>")
    lines.append("</div>")
    return lines


# --------------------------------------------------------------------------
# 06 · Экраны — система в работе
# --------------------------------------------------------------------------

# Экраны — по поверхностям продукта, а не одним листом. Каждая подкатегория
# показывает СВОЙ артефакт (эскиз-кандидат, фон установщика, лист макетов);
# чего ещё нет — честно пусто, не выдумано. Пути — относительно design/index.html.
# Порядок фиксирован (пространственная память, 02 §8.4).
SCREEN_GROUPS = [
    {
        "anchor": "screen-onboarding", "title": "Онбординг", "kind": "iframe",
        "src": "candidates/onboarding.html", "height": 14,
        "status": "кандидат · экран 0 принят эталоном",
        "blurb": "Первый запуск: шесть решений на рое и разлёт в главное окно. "
                 "Экран приветствия принят целиком как эталон — источник правды "
                 "по кнопке, вордмарку, рою и завесе.",
    },
    {
        "anchor": "screen-main", "title": "Главный экран", "kind": "iframe",
        "src": "candidates/main-screen-sketch.html", "height": 15,
        "status": "кандидат · эскиз на утверждение",
        "blurb": "Рейл, сайдбар и плавающие панели: границу держит зазор, "
                 "а не линейка. Эскиз доводит §1 макета до того, что его "
                 "собственная подпись уже обещает.",
    },
    {
        "anchor": "screen-notch", "title": "Нотч-хелпер", "kind": "iframe",
        "src": "candidates/notch-helper-board.html", "height": 14,
        "status": "кандидат · этап 1 принят рабоче",
        "blurb": "Чёлка макбука как амбиентный пульт пайплайна CRISPY. "
                 "Этап 1 (свёрнутая чёлка · ховер · раскрытие) принят рабоче; "
                 "композер, полка и приоритеты — следующие этапы.",
    },
    {
        "anchor": "screen-dmg", "title": "DMG — установщик", "kind": "image",
        "src": "dmg/mockup.png",
        "status": "принят · собирается appdmg",
        "blurb": "Окно установки: перетащить .app в Applications. Градиент "
                 "на тёмной гамме проекта, дизеринг против лесенок — эскиз "
                 "утверждён и собирается из design/dmg.",
    },
    {
        "anchor": "screen-all", "title": "Все экраны разом", "kind": "iframe",
        "src": MOCKUPS, "height": 15, "external": True,
        "status": "лист макетов",
        "blurb": "Вся система, собранная обратно в экраны: ревью, канбан, лог, "
                 "аналитика, настройки. Панель скроллится сама, и ⌘F доски "
                 "по ней не пройдёт.",
    },
]

# Файлы-образцы, которые Экраны показывают сами: их сайдкары в приёмной не
# дублируются (двойной тяжёлый iframe — два якоря на одно, 11 §1.1).
SCREEN_SIDECAR_FILES = {
    group["src"].rsplit("/", 1)[-1]
    for group in SCREEN_GROUPS if group["kind"] == "iframe" and group["src"].startswith("candidates/")
}


def board_screens(tokens):
    """Экраны — по поверхностям продукта, каждая своим артефактом.

    Прежде здесь висел один длинный лист макетов; система в работе видна, но
    поверхности в нём не различить. Теперь — подкатегории (онбординг, главный,
    нотч-хелпер, DMG, весь лист), и каждая показывает СВОЙ файл: эскиз-кандидат
    целиком, фон установщика картинкой, лист — листом. Чего ещё нет — честно
    пусто, а не нарисовано.
    """
    lines = []
    # Локальный рельс по подкатегориям: якоря и ⌘F обязаны работать.
    lines.append('<nav class="subrail">')
    for group in SCREEN_GROUPS:
        lines.append('  <a href="#%s">%s</a>' % (escape(group["anchor"]), escape(group["title"])))
    lines.append("</nav>")

    for group in SCREEN_GROUPS:
        if group["src"].startswith("../"):
            exists = (ROOT / group["src"].replace("../", "", 1)).exists()
        else:
            exists = (ROOT / "design" / group["src"]).exists()
        lines.append('<div class="block" id="%s">' % escape(group["anchor"]))
        lines.append(block_head(escape(group["title"]), escape(group["status"])))
        lines.append('  <p class="screen-blurb">%s</p>' % typo(escape(group["blurb"])))
        if not exists:
            lines.append('  <div class="empty">Артефакта ещё нет — подкатегория '
                         "названа, файл не приехал.</div>")
            lines.append("</div>")
            continue
        lines.append('  <div class="screens">')
        if group["kind"] == "image":
            # Картинку не ленивим: одна на подкатегорию, а lazy вне вьюпорта
            # не грузится при снимке — образец врал бы пустотой.
            lines.append('    <img src="%s" alt="%s">'
                         % (escape(group["src"]), escape(group["title"])))
        else:
            lines.append('    <iframe src="%s" style="height: calc(var(--space-10) * %d)" '
                         'loading="lazy" title="%s"></iframe>'
                         % (escape(group["src"]), group["height"], escape(group["title"])))
        lines.append("  </div>")
        note = ("Лист длинный — панель скроллится сама. " if group.get("external") else "")
        lines.append('  <p class="hint" style="margin-top: var(--space-3); color: var(--text-tertiary)">'
                     '%sОткрыть отдельно — <a href="%s">в своей вкладке</a>.</p>'
                     % (note, escape(group["src"])))
        lines.append("</div>")
    return lines


# --------------------------------------------------------------------------
# Приёмная и кладбище
# --------------------------------------------------------------------------

def board_intake(records):
    lines = board_parts(records)
    can = []
    cant = []
    for record in records:
        can.append(part_verdict_line(record, "why"))
        cant.append(part_verdict_line(record, "never"))
    if can:
        lines.extend(render_verdict(can, cant, "Зачем это спасали", "Чего с этим делать нельзя"))
    return lines


def board_graveyard(items):
    """Кладбище — содержание, а не сноска.

    Шестнадцать мёртвых идей с причинами стоят дороже принятого: принятое
    видно на экране, отвергнутое не видно нигде — и потому предлагается
    заново каждой следующей сессией.
    """
    lines = ['<div class="grave">']
    for item in items:
        lines.append('  <div class="grave-item">')
        lines.append("    <h4>%s</h4>" % escape(item["name"]))
        # Причина — тем же сжатием, что и всё на доске: вердикт виден,
        # разбирательство — под «+N». Шестнадцать причин по семь строк —
        # это стена прозы, то есть ровно то, ради ухода от чего доска есть.
        lines.append("    <p>%s</p>" % typo(compress(item["reason"])))
        lines.append('    <a href="rejected/%s">%s</a>' % (escape(item["file"]), escape(item["file"])))
        lines.append("  </div>")
    lines.append("</div>")
    return lines


# --------------------------------------------------------------------------
# Живые приборы доски
#
# Три штуки, и каждая — то, чего доска-картинка не умеет в принципе:
# посчитать контраст при читателе, отдать имя токена в буфер, показать
# переход переходом. Ради них витрина и является страницей, а не PDF.
# --------------------------------------------------------------------------

CANVAS_SCRIPT = """
(function () {
  var data = JSON.parse(document.getElementById("canvas-data").textContent);

  // ——— WCAG, посчитанный здесь ———
  // Альфа-белый — рецепт, а не цвет: пока он не лёг на фон, контраста
  // у него нет. Наивный счёт по «rgba(255,255,255,0.7)» врёт.
  function toLinear(channel) {
    var value = channel / 255;
    return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
  }
  function luminance(rgb) {
    return 0.2126 * toLinear(rgb[0]) + 0.7152 * toLinear(rgb[1]) + 0.0722 * toLinear(rgb[2]);
  }
  function over(rgb, alpha, background) {
    return [0, 1, 2].map(function (i) { return alpha * rgb[i] + (1 - alpha) * background[i]; });
  }
  function ratio(first, second) {
    var a = luminance(first), b = luminance(second);
    if (b > a) { var swap = a; a = b; b = swap; }
    return (a + 0.05) / (b + 0.05);
  }
  function css(rgb) {
    return "rgb(" + rgb.map(function (c) { return Math.round(c); }).join(",") + ")";
  }

  // Подпись в клетке обязана быть читаемой на ЛЮБОЙ заливке — иначе доска
  // о нечитаемости рассказывает нечитаемым текстом. Красный sem.error берётся
  // только там, где он сам проходит; где не проходит — берётся то, что
  // контрастнее, а провал держит форма (✕), как и требует sem._role: цвет
  // никогда не единственный носитель смысла.
  function legible(backgroundRgb, preferred) {
    if (preferred && ratio(preferred, backgroundRgb) >= 3) { return preferred; }
    var white = [255, 255, 255];
    return ratio(white, backgroundRgb) >= ratio(data.base, backgroundRgb) ? white : data.base;
  }

  function cell(inkRgb, alpha, backgroundRgb, exempt) {
    var mixed = over(inkRgb, alpha === undefined ? 1 : alpha, backgroundRgb);
    var value = ratio(mixed, backgroundRgb);
    var fails = !exempt && value < data.threshold;
    var meta = legible(backgroundRgb, fails ? data.error : null);
    var td = document.createElement("td");
    td.className = fails ? "fail" : "pass";
    td.style.background = css(backgroundRgb);
    td.innerHTML =
      '<span class="cell">' +
      '<span class="sample" style="color:' + css(mixed) + '">Ждёт ревью</span>' +
      '<span class="ratio" style="color:' + css(meta) + '">' + value.toFixed(1) + ":1</span>" +
      '<span class="flag" style="color:' + css(meta) + '">✕</span></span>';
    return td;
  }

  // Матрица 1 — чернила на поверхностях.
  var inks = document.querySelector("#matrix-inks");
  var head = inks.querySelector("thead tr");
  data.surfaces.forEach(function (surface) {
    var th = document.createElement("th");
    th.textContent = surface.path;
    head.appendChild(th);
  });
  var inkBody = inks.querySelector("tbody");
  data.inks.forEach(function (ink) {
    var tr = document.createElement("tr");
    var th = document.createElement("th");
    th.textContent = ink.path;
    th.title = ink.role;
    th.setAttribute("data-token", ink.path);
    tr.appendChild(th);
    data.surfaces.forEach(function (surface) {
      tr.appendChild(cell(ink.rgb, ink.alpha, surface.rgb, ink.exempt));
    });
    inkBody.appendChild(tr);
  });

  // Матрица 2 — что можно положить на фирменную заливку. Ровно то место,
  // где text.on-accent запрещает белый, и видно почему.
  var accents = document.querySelector("#matrix-accents");
  var accentHead = accents.querySelector("thead tr");
  ["белый", "bg.base"].forEach(function (name) {
    var th = document.createElement("th");
    th.textContent = name;
    accentHead.appendChild(th);
  });
  var accentBody = accents.querySelector("tbody");
  var base = data.surfaces[0].rgb;
  data.accents.forEach(function (accent) {
    var tr = document.createElement("tr");
    var th = document.createElement("th");
    th.textContent = accent.path;
    th.setAttribute("data-token", accent.path);
    tr.appendChild(th);
    tr.appendChild(cell(data.onAccent.rgb, data.onAccent.alpha, accent.rgb, false));
    tr.appendChild(cell(base, 1, accent.rgb, false));
    accentBody.appendChild(tr);
  });

  // ——— Клик копирует имя токена, shift+клик — значение ———
  // Никакой кнопки: у кнопки «скопировать» нет работы, которой не делает
  // сам свотч (01 §2.2 — пиксель платит аренду).
  var toast = document.createElement("div");
  toast.className = "toast";
  document.body.appendChild(toast);
  var timer = null;

  function say(text) {
    toast.textContent = text;
    toast.classList.add("on");
    clearTimeout(timer);
    timer = setTimeout(function () { toast.classList.remove("on"); }, 1200);
  }

  function copy(text) {
    // file:// не везде отдаёт clipboard API — запасной ход обязателен,
    // иначе прибор работает «почти всегда», то есть не работает.
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text).then(function () { say("скопировано · " + text); },
                                                function () { fallback(text); });
    } else { fallback(text); }
  }
  function fallback(text) {
    var field = document.createElement("textarea");
    field.value = text;
    field.setAttribute("readonly", "");
    field.style.position = "fixed";
    field.style.opacity = "0";
    document.body.appendChild(field);
    field.select();
    try { document.execCommand("copy"); say("скопировано · " + text); }
    catch (error) { say("скопировать не вышло · " + text); }
    document.body.removeChild(field);
  }

  document.addEventListener("click", function (event) {
    var target = event.target.closest("[data-token]");
    if (!target) { return; }
    var hex = target.getAttribute("data-hex");
    copy(event.shiftKey && hex ? hex : target.getAttribute("data-token"));
  });

  // ——— Движение: переход показывается переходом ———
  // Гонять точку туда-обратно нельзя: обратный ход ease-out — это ease-in,
  // и образец начнёт врать про кривую. Поэтому — прогон и возврат мгновенно.
  if (!window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    var tracks = document.querySelectorAll(".motion-track");
    setInterval(function () {
      tracks.forEach(function (track) { track.classList.add("go"); });
      setTimeout(function () {
        tracks.forEach(function (track) {
          var dot = track.querySelector(".motion-dot");
          var kept = dot.style.transition;
          dot.style.transition = "none";
          track.classList.remove("go");
          void dot.offsetWidth;
          dot.style.transition = kept;
        });
      }, 900);
    }, 1800);
  }

  // ——— Рельс-табы: подсветить раздел, который сейчас читают ———
  // Таб — цель по Фиттсу, но у пассивной цели нет обратной связи: какой
  // раздел под тобой, видно только по нему самому. Scroll-spy эту связь
  // возвращает, не требуя клика.
  var railLinks = {};
  document.querySelectorAll(".rail a").forEach(function (link) {
    var id = (link.getAttribute("href") || "").slice(1);
    if (id) { railLinks[id] = link; }
  });
  var railSections = document.querySelectorAll("section.section[id]");
  if (railSections.length && "IntersectionObserver" in window) {
    var spy = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) { return; }
        var link = railLinks[entry.target.id];
        if (!link) { return; }
        Object.keys(railLinks).forEach(function (id) { railLinks[id].classList.remove("active"); });
        link.classList.add("active");
      });
    }, { rootMargin: "-12% 0px -78% 0px", threshold: 0 });
    railSections.forEach(function (section) { spy.observe(section); });
  }
})();
"""


# --------------------------------------------------------------------------
# Таксономия доски — единственный источник её разделов
#
# Части физически лежат в атомарных папках (1-foundation…7-behaviour): папка
# кодирует настоящее правило (элемент или блок — знает ли про домен?) и даёт
# новой части дом. А доска показывается КОНКРЕТНЫМИ категориями — теми, что
# узнаёт любой дизайнер: цвета, типографика, кнопки, табы, лейблы… Мост между
# папкой и доской — вот этот список. Он один, из него доска и собирается,
# поэтому разойтись доске с составом системы нечем: часть без секции валит
# сборку (check_sections_cover_parts), а секция без части честно пустует.
#
# Тип раздела говорит, чем он наполнен:
#   «foundation» — блоки, нарисованные из tokens.json (blocks), и «Можно /
#                  Нельзя» по его группам (groups);
#   «parts»      — образцы частей по слагам (slugs);
#   «screens»    — макет девятнадцати экранов (плюс части, если появятся).
BOARD_SECTIONS = [
    {
        "kind": "foundation", "anchor": "colors", "title": "Цвета",
        "lede": "Это значения, а не картинки: каждая ступень, состояние и "
                "контраст нарисованы из tokens.json — поменяется хекс в источнике, "
                "поменяется эта секция. Контраст доска считает при читателе.",
        "blocks": colors_blocks,
        "groups": ["brand", "bg", "border", "text", "sem"],
    },
    {
        "kind": "foundation", "anchor": "typography", "title": "Типографика",
        "lede": "Лестница кеглей в натуральную величину, на реальных строках "
                "продукта — на lorem не видно ни длины, ни кириллицы.",
        "blocks": typography_blocks,
        "groups": ["type"],
    },
    {
        "kind": "foundation", "anchor": "layout", "title": "Сетка",
        "lede": "Модульная сетка на трёх уровнях: панели окна в натуральную "
                "величину, микросетка колонок с единым гаттером, колонка чтения "
                "ровно в меру — правило, которому подчинена и эта страница.",
        "blocks": layout_blocks,
        "groups": ["_layout"],
    },
    {
        "kind": "foundation", "anchor": "spacing", "title": "Отступы",
        "lede": "Шкала, измеряющая сама себя: столбик длиной ровно в свой токен, "
                "1:1 — линейка, а не таблица; рядом — инвариант Бирмана «внутреннее "
                "≤ внешнее», нарисованный.",
        "blocks": spacing_blocks,
        "groups": ["space"],
    },
    {
        "kind": "foundation", "anchor": "radius", "title": "Скругления",
        "lede": "Концентрика, нарисованная и заодно проверенная: вложенный радиус "
                "= внешний − паддинг, и шкала попадает шагом в один space.1 ровно "
                "в следующий токен.",
        "blocks": radius_blocks,
        "groups": ["radius"],
    },
    {
        "kind": "parts", "anchor": "buttons", "title": "Кнопки",
        "lede": "Базовый элемент действия: сам по себе смысла не несёт и о "
                "предметной области не знает.",
        "slugs": ["button"],
    },
    {
        "kind": "parts", "anchor": "tabs", "title": "Табы",
        "lede": "Переключение вида: один активный, остальные ждут.",
        "slugs": ["tabs"],
    },
    {
        "kind": "parts", "anchor": "labels", "title": "Лейблы",
        "lede": "Метки состояния и принадлежности: бейдж, точка статуса, чип, "
                "лейбл проекта.",
        "slugs": ["badge", "status-dot", "chip", "project-label"],
    },
    {
        "kind": "parts", "anchor": "panels", "title": "Панели",
        "lede": "Контейнер для другого: панель как слой поверх фона.",
        "slugs": ["panel"],
    },
    {
        "kind": "parts", "anchor": "blocks", "title": "Блоки",
        "lede": "Доменный компонент — знает про предметную область: строка диффа, "
                "стадия, change.",
        "slugs": ["diff-line"],
    },
    {
        "kind": "icons", "anchor": "icons", "title": "Иконки",
        "lede": "Система, а не ряд картинок: размеры из токенов, закреплённый "
                "словарь доменных метафор на SF Symbols, статусы «глиф + цвет» — "
                "и опознавательные марки продукта «Восход» и орб.",
        "slugs": ["app-icon", "orb"],
    },
    {
        "kind": "parts", "anchor": "logo", "title": "Логотип",
        "lede": "Вордмарк «Foundry AI» — знак неделим.",
        "slugs": ["wordmark"],
    },
    {
        "kind": "foundation", "anchor": "animation", "title": "Анимации",
        "lede": "Движение и свечение показываются собой — переход переходом, свет "
                "светом; при prefers-reduced-motion молчат.",
        "blocks": animation_blocks,
        "groups": ["motion", "glow"],
    },
    {
        "kind": "screens", "anchor": "screens", "title": "Экраны",
        "lede": "Вся система разом, собранная обратно в экраны — единственное "
                "место, где её видно в работе.",
        "slugs": [],
    },
]


def check_sections_cover_parts(parts):
    """Каждая часть привязана ровно к одной секции доски — иначе доска врёт
    составом. Часть без секции немо пропала бы с доски, оставшись в счётчике
    обложки; две секции на один слаг — уже не одна таксономия. И то и другое
    валит сборку с адресом правки, ровно как лестница кеглей валит сборку без
    образца: правило, которое не проверяется, не существует."""
    wired = {}
    for section in BOARD_SECTIONS:
        for slug in section.get("slugs", []):
            if slug in wired:
                raise ValueError(
                    "слаг «%s» привязан к двум секциям доски («%s» и «%s») — "
                    "таксономия доски одна, поправь BOARD_SECTIONS в design/build.py"
                    % (slug, wired[slug], section["anchor"]))
            wired[slug] = section["anchor"]
    for record in parts:
        if record["slug"] not in wired:
            raise ValueError(
                "часть «%s» (%s) не привязана ни к одной секции доски: добавь её "
                "слаг в BOARD_SECTIONS (design/build.py) — иначе доска молчит о "
                "части, которую обложка уже посчитала"
                % (record["slug"], record["category"]))


def board_section_parts(section, law_parts, candidate_parts):
    """Секция категории — её части образцами, принятые раньше кандидатов.

    Зрелость несёт статус-чип под образцом, а не пряталка. Часть, оформленная
    по контракту, стоит в своей категории независимо от статуса — «статус это
    зрелость, папка это категория, файл при смене статуса не переезжает»
    (parts/README.md). Прятать оформленного кандидата в приёмную значило бы
    показывать пустую категорию там, где часть есть, оформлена и проходит линт;
    честность за это отвечает чип «кандидат», а не отсутствие образца. Приёмная —
    для неоформленного (сайдкары: целые экраны и эталоны), не для частей-кандидатов.

    Ни одной части — секция честно пустует: слаг привязан, а файла-образца ещё
    нет (tabs/panel/chip могли не собраться), и выдумывать содержимое нельзя."""
    slugs = section["slugs"]
    accepted = [record for record in law_parts if record["slug"] in slugs]
    candidates = [record for record in candidate_parts if record["slug"] in slugs]
    shown = accepted + candidates
    if not shown:
        return ['<div class="empty">Часть пока не оформлена — файла с образцом '
                "ещё нет.</div>"]
    lines = board_parts(shown)
    can = [part_verdict_line(record, "why") for record in shown]
    cant = [part_verdict_line(record, "never") for record in shown]
    lines.extend(render_verdict(can, cant, "Можно — зачем компонент есть",
                                "Нельзя — где компонент неуместен"))
    return lines


def board_icons(tokens, section, law_parts, candidate_parts):
    """Иконки — не картинка ряда глифов, а система: размеры из токенов, карта
    доменных метафор и статусов из канона 12, и опознавательные марки продукта.

    SF Symbols браузер не рисует — это продолжение шрифта San Francisco, а не
    набор картинок. Поэтому доска показывает то, что МОЖЕТ показать правдой:
    шкалу размеров в натуральную величину (из icon.*), карту «понятие → символ»
    (закреплённый словарь §3) и связку «статус = глиф + цвет» (§6, форма
    дублирует цвет). Сам глиф живёт в приложении; выдумывать его начертание
    на доске значило бы ломать систему руками (§2.1)."""
    lines = []

    # Размеры — в натуральную величину, из icon.*. Правило §2.1: кегль иконки =
    # кегль соседнего текста; квадрат размера стоит рядом со строкой body.
    lines.append('<div class="block" id="icon-sizes">')
    lines.append(block_head("Размеры",
                            "в натуральную величину из icon.*; кегль иконки = кегль "
                            "соседнего текста (§2.1)"))
    lines.append('  <ul class="icon-sizes">')
    for name, token in tokens["icon"].items():
        if is_documentation_key(name):
            continue
        path = "icon.%s" % name
        lines.append('    <li data-token="%s">' % escape(path))
        lines.append('      <i style="width: var(%s); height: var(%s)"></i>'
                     % (variable_name(path), variable_name(path)))
        lines.append('      <span class="t">%s</span>' % escape(path))
        lines.append('      <span class="n">%spt</span>' % format_number(token["pt"]))
        lines.append('      <span class="r">%s</span>' % escape(token.get("role", "")))
        lines.append("    </li>")
    lines.append("  </ul>")
    lines.append("</div>")

    # Карта доменных метафор — закреплённый словарь §3. Символ моноширинным:
    # это идентификатор в приложении, а не слово.
    lines.append('<div class="block" id="icon-metaphors">')
    lines.append(block_head("Доменные метафоры",
                            "одно понятие — один SF Symbol, везде (§3); браузер их не "
                            "рисует — это карта, глиф живёт в приложении"))
    lines.append('  <table class="icon-map">')
    lines.append("    <thead><tr><th>Понятие</th><th>SF Symbol</th><th>Почему</th></tr></thead>")
    lines.append("    <tbody>")
    for concept, symbol, why in ICON_METAPHORS:
        lines.append("      <tr><th>%s</th><td><code>%s</code></td><td>%s</td></tr>"
                     % (escape(concept), escape(symbol), typo(escape(why))))
    lines.append("    </tbody>")
    lines.append("  </table>")
    lines.append("</div>")

    # Статусы стадии — форма ДУБЛИРУЕТ цвет (§6). Цвет берём из токена, форму
    # несёт имя глифа: цвет и имя рядом, а не цвет вместо имени.
    lines.append('<div class="block" id="icon-statuses">')
    lines.append(block_head("Статусы стадии",
                            "форма дублирует цвет: каждому статусу свой глиф И свой "
                            "токен-цвет (§6)"))
    lines.append('  <ul class="icon-statuses">')
    for status, glyph, color_path in ICON_STATUSES:
        lines.append('    <li data-token="%s">' % escape(color_path))
        lines.append('      <i class="dot" style="background: var(%s)"></i>' % variable_name(color_path))
        lines.append('      <span class="t">%s</span>' % escape(status))
        lines.append('      <span class="g"><code>%s</code></span>' % escape(glyph))
        lines.append('      <span class="c">%s</span>' % escape(color_path))
        lines.append("    </li>")
    lines.append("  </ul>")
    lines.append("</div>")

    # Марки продукта в пикселях — иконка приложения «Восход» и орб — образцами.
    slugs = section["slugs"]
    accepted = [record for record in law_parts if record["slug"] in slugs]
    candidates = [record for record in candidate_parts if record["slug"] in slugs]
    marks = accepted + candidates
    if marks:
        lines.append('<div class="block" id="icon-marks">')
        lines.append(block_head("Марки продукта",
                                "опознавательный знак в пикселях: иконка приложения "
                                "и орб"))
        lines.extend(board_parts(marks))
        lines.append("</div>")

    # Один закрывающий вердикт на всю секцию: императивы канона 12 плюс why/never
    # самих марок. Правила системы иконок написаны автором главы — как и why/never
    # части; доска их не выдумывает, а собирает.
    can = [
        "<code>SF Symbols</code> — monochrome по умолчанию, alpha-белый уровней текста; hierarchical для составных (§2.2)",
        "иконка ставится, только если ускоряет распознавание уже знакомого (§1.1)",
        "одно понятие — один символ, везде: словарь §3 закреплён",
        "кегль и вес иконки = кегль и вес соседнего текста (§2.1)",
        "статус = глиф + цвет: форма дублирует цвет (§6)",
    ]
    cant = [
        "multicolor запрещён — пёстрые заливки разваливают тёмную палитру (§2.2)",
        "доменная иконка без подписи и тултипа — «стадия», «луп», «change» иконкой не читаются (§1.2)",
        "синонимия: сегодня change молния, завтра карандаш — выученность убита (§3)",
        "декоративные иконки-обои у каждого пункта — ряд пестрит, чтение медленнее (§1.1)",
        "смешивать outline и filled как «просто разные»: заполненность означает состояние, и только его (§4)",
    ]
    can.extend(part_verdict_line(record, "why") for record in marks)
    cant.extend(part_verdict_line(record, "never") for record in marks)
    lines.extend(render_verdict(can, cant, "Можно — правила системы иконок",
                                "Нельзя — запреты канона 12"))
    return lines


# --------------------------------------------------------------------------
# Сборка доски
# --------------------------------------------------------------------------

def generate_showcase(tokens):
    """Доска, а не вики.

    Разделы — конкретные категории, которые узнаёт любой дизайнер: цвета,
    типографика, кнопки, табы, лейблы, панели, блоки, иконки, логотип,
    анимации, экраны. Их порядок и состав — в BOARD_SECTIONS, и доска
    собирается только оттуда: части остаются в атомарных папках, а секции
    показываются поверх них. Прокрутка одна и непрерывная: якоря, адреса и
    ⌘F обязаны работать — это документ, которым пользуются, а не витраж,
    на который смотрят.
    """
    parts = collect_parts()
    rejected = collect_rejected()
    check_sections_cover_parts(parts)

    # Раскладка по зрелости — по статусу карточки, а не по папке: статус —
    # единственная истина о зрелости, папка говорит только о категории
    # (README, «Три статуса»). Файл при смене статуса никуда не едет.
    candidate_parts = [record for record in parts if record["card"].get("status") == CANDIDATE_STATUS]
    law_parts = [record for record in parts if record["card"].get("status") != CANDIDATE_STATUS]
    # Приёмная — только сайдкары: крупное неразобранное (целые экраны, эталоны),
    # ради чего приёмная и есть. Оформленные части-кандидаты приёмной не касаются
    # — они стоят в своих категориях с чипом «кандидат» (board_section_parts).
    # Экранные сайдкары показывает секция «Экраны» подкатегориями — в приёмной
    # их не дублируем (двойной тяжёлый iframe — два якоря на одно, 11 §1.1).
    sidecars = [record for record in collect_sidecars()
                if not (record.get("specimen")
                        and record["specimen"].rsplit("/", 1)[-1] in SCREEN_SIDECAR_FILES)]

    sections = []
    for index, section in enumerate(BOARD_SECTIONS, start=1):
        if section["kind"] == "foundation":
            body = board_foundation(tokens, section)
        elif section["kind"] == "screens":
            body = board_screens(tokens)
        elif section["kind"] == "icons":
            body = board_icons(tokens, section, law_parts, candidate_parts)
        else:
            body = board_section_parts(section, law_parts, candidate_parts)
        sections.append({
            "num": "%02d" % index,
            "anchor": section["anchor"],
            "title": section["title"],
            "lede": section["lede"],
            "body": body,
        })

    if sidecars:
        sections.append({
            "num": "—",
            "anchor": "candidates",
            "title": "Приёмная",
            "lede": "Крупное неразобранное — целые экраны и эталоны, приехавшие из "
                    "сессий и приёмку не проходившие: ссылаться как на решённое нельзя. "
                    "Штатный вход в систему — иначе находки оседают в рабочей ветке и "
                    "теряются вместе с ней. Оформится в компонент — переедет в свою "
                    "категорию кандидатом.",
            "body": board_intake(sidecars),
        })

    if rejected:
        sections.append({
            "num": "—",
            "anchor": "rejected",
            "title": "Отвергнуто",
            "lede": "Отвергнутое стоит дороже принятого: принятое видно на экране, "
                    "а отвергнутое не видно нигде — и потому предлагается заново "
                    "каждой следующей сессией.",
            "body": board_graveyard(rejected),
        })

    lines = ["<!doctype html>", '<html lang="ru">', "<head>", '<meta charset="utf-8">',
             "<!-- %s -->" % HEADER,
             "<title>Дизайн-система Foundry</title>",
             '<link rel="stylesheet" href="tokens/tokens.css">',
             '<link rel="stylesheet" href="canvas.css">',
             "</head>", "<body>", '<div class="canvas">']

    lines.extend(board_cover(tokens, law_parts, candidate_parts, sidecars, rejected))

    lines.append('<nav class="rail">')
    for section in sections:
        lines.append('  <a href="#%s"><span class="n">%s</span>%s</a>'
                     % (escape(section["anchor"]), escape(section["num"]), escape(section["title"])))
    lines.append("</nav>")

    for section in sections:
        lines.append('<section class="section" id="%s">' % escape(section["anchor"]))
        lines.append('  <div class="section-head"><span class="num">%s</span><h2>%s</h2></div>'
                     % (escape(section["num"]), escape(section["title"])))
        if section["lede"]:
            lines.append('  <p class="section-lede">%s</p>' % typo(escape(section["lede"])))
        lines.extend("  " + line for line in section["body"])
        lines.append("</section>")

    lines.append('<footer class="foot">Собрана из компонентов и из <a href="tokens/tokens.json">'
                 "tokens.json</a> скриптом <code>design/build.py</code>. Своего содержимого "
                 "не имеет: правка руками теряется при следующей сборке. Договор о формате "
                 'компонента — <a href="parts/README.md">design/parts/README.md</a>.</footer>')
    lines.append("</div>")
    lines.append('<script type="application/json" id="canvas-data">%s</script>'
                 % json.dumps(contrast_payload(tokens), ensure_ascii=False))
    lines.append("<script>%s</script>" % CANVAS_SCRIPT)
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
