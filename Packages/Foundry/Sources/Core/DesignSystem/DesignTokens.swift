// swift-format-ignore-file
// СГЕНЕРИРОВАНО design/build.py — не править руками
// ЕДИНСТВЕННЫЙ ИСТОЧНИК ЗНАЧЕНИЙ foundry-desktop. Правится только здесь. Из него build.py генерит tokens.css (макеты), Tokens.swift (приложение) и таблицы значений в docs/design/13-tokens.md (канон). Руками эти три не править — перезатрёт. Обоснования значений — проза канона, здесь только вердикты. Нет нужного токена — сначала добавить сюда, потом использовать.

import SwiftUI

/// Семейство шрифта токена: интерфейсный текст или моноширинный.
public enum TokenFontFamily: Sendable {
    case text
    case mono
}

/// Типографский токен: кегль, интерлиньяж, вес, семейство.
public struct TypeToken: Sendable {
    public let size: CGFloat
    public let leading: CGFloat
    public let weight: Font.Weight
    public let family: TokenFontFamily
    /// Прописные (лейблы секций сайдбара).
    public let isUppercased: Bool
    /// Трекинг долей кегля.
    public let tracking: CGFloat

    public init(size: CGFloat, leading: CGFloat, weight: Font.Weight, family: TokenFontFamily,
                isUppercased: Bool = false, tracking: CGFloat = 0) {
        self.size = size
        self.leading = leading
        self.weight = weight
        self.family = family
        self.isUppercased = isUppercased
        self.tracking = tracking
    }

    public var font: Font {
        .system(size: size, weight: weight, design: family == .mono ? .monospaced : .default)
    }

    /// Насколько развести строки, чтобы вышел интерлиньяж канона, и сколько
    /// добавить полем сверху и снизу, — не здесь: высота строки у SwiftUI
    /// не выводится из кегля и метрик шрифта, её приходится СНИМАТЬ.
    /// Смотри `TypeMetrics`, снимающий её у самого текста.
}

/// Токен движения. duration == nil — непрерывное состояние, а не переход.
public struct MotionToken: Sendable {
    public let duration: TimeInterval?
    public let animation: Animation?
}

/// Свечение — фирменная замена тени. Рецепт двухслойный: внутренний ореол
/// blur 10 @ 40% и внешний blur 36 @ 15% цвета токена (06-color.md, раздел 5.6).
public struct GlowToken: Sendable {
    public let color: Color
    public let innerRadius: CGFloat = 10
    public let innerOpacity: Double = 0.4
    public let outerRadius: CGFloat = 36
    public let outerOpacity: Double = 0.15
}

extension Color {
    /// Цвет из целого 0xRRGGBB — тем же написанием, что и в tokens.json.
    public init(hexValue: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hexValue >> 16) & 0xFF) / 255,
            green: Double((hexValue >> 8) & 0xFF) / 255,
            blue: Double(hexValue & 0xFF) / 255,
            opacity: opacity
        )
    }
}

public enum Token {
    /// Фирменная гамма: аналоговый ход ультрамарин → пурпур → маджента (OKLCH hue 266 → 293 → 316). Мотив — орб, свет в темноте. Гамма держится смежной: циан-акцент в неё не входит → rejected/cyan-accent.md; live/стрим несёт brand.purple как «AI работает». Оранжевый/ember отвергнут, не возвращать → rejected/ember-palette.md
    public enum Brand {
        /// главный акцент: primary-действия, активные состояния, выделение
        public static let ultramarine = Color(hexValue: 0x2F5CFF)
        /// вторичный акцент: градиенты, AI-сущности; live/стрим и работа агента (sem.info, glow.live)
        public static let purple = Color(hexValue: 0x8B5CF6)
        /// третичный: только в градиентах и орбе, не как самостоятельный цвет UI
        public static let magenta = Color(hexValue: 0xD65CFF)
        /// ТОЛЬКО знак: логотип «Foundry AI» и фирменные места, где он появляется целиком. НИКОГДА не статус и не состояние — для этого есть sem.warning. Разведение ролей обязательно и держится дисциплиной, а не глазом: янтарь всего в 9° от sem.warning #FBBF24, глаз их не различит. Отсюда правило: увидел жёлтый в UI — это sem.warning; увидел жёлтый в знаке — это brand.amber; в одном экране они не встречаются.
        public static let amber = Color(hexValue: 0xFFB020)
        /// орб, hero-акценты
        /// Интерполяция канона — oklch; SwiftUI смешивает в своём
        /// пространстве, поэтому опорные точки заданы явно.
        public static let gradient = LinearGradient(
            colors: [Token.Brand.ultramarine, Token.Brand.purple, Token.Brand.magenta],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Elevation через светлоту, не через тень. Ниже базы нет ничего, выше базы — три полки, и они ОБЕСЦВЕЧЕНЫ: цвет на большой площади даёт грязь (янтарь 11 % поверх базы читается оливой), поэтому хрома падает на первом же шаге и дальше почти не растёт, а тон стоит на 286±1. Шаг неравный намеренно: от базы до первой полки он вдвое больше прочих — фон окна лежит заведомо ниже всего, что на нём стоит, а полки между собой близки. Слой не перепрыгивает уровни; уровней на экране ≤3. Сайдбар и тулбар — системный Liquid Glass, их фон не хардкодим. База снята с принятого эталона онбординга, полки — с принятого эталона главного экрана; ни один порог контраста не пересечён.
    public enum Background {
        /// фон окна, фон контентной зоны
        public static let base = Color(hexValue: 0x05030D)
        /// плита канваса, рейл, сайдбар, панель кода/диффа/лога
        public static let surface = Color(hexValue: 0x141417)
        /// карточки канбана, строки-контейнеры, поповеры, меню, тултипы, sticky-заголовки
        public static let raised = Color(hexValue: 0x1E1E23)
        /// плавающий инспектор, модалки/шиты, тосты (плюс скрим под ними)
        public static let overlay = Color(hexValue: 0x26262C)
        /// hover строк, карточек, пунктов меню
        public static let hover = Color(white: 1, opacity: 0.06)
        /// нажатое состояние плоских элементов
        public static let pressed = Color(white: 1, opacity: 0.1)
        /// выбранная строка/пункт; карточка — заливка 14% + бордер ультрамарин @ 50%
        public static let selected = Token.Brand.ultramarine.opacity(0.14)
        /// подложка модалок; допуск 40–60%, с блюром 8–12px — 35–45%
        public static let scrim = Color(white: 0, opacity: 0.5)
    }

    /// Дефолт — вообще без линейки: сначала воздух и выравнивание, линейка — осознанное исключение.
    public enum Border {
        /// разделители списков (только многострочных), линии таблиц, сетки графиков
        public static let subtle = Color(white: 1, opacity: 0.08)
        /// контур карточек, полей ввода, бейджей
        public static let `default` = Color(white: 1, opacity: 0.12)
        /// hover-контур, обводка secondary-кнопок
        public static let strong = Color(white: 1, opacity: 0.2)
        /// цвет фокус-ринга клавиатуры
        public static let focus = Token.Brand.ultramarine
        /// толщина фокус-ринга клавиатуры
        public static let focusWidth: CGFloat = 2
        /// отбивка фокус-ринга от элемента
        public static let focusOffset: CGFloat = 2
    }

    /// Альфа-белый, не серые хардкоды. Ни один цвет палитры не используется как цвет текста: brand.ultramarine на тёмном даёт 4.0:1 и не проходит — текстом всегда text.accent. Контрасты посчитаны на bg.base, обоснования — 06-color.md, раздел 4.2.
    public enum Text {
        /// основной текст, заголовки. Не чистый белый: на почти чёрном он звенит и тянет строку на себя. Оба принятых эталона — онбординг и главный экран — набраны на 0.96, и токен приведён к практике, а не наоборот. Чистый белый остался там, где он не текст на фоне, а надпись на заливке: text.on-accent
        public static let primary = Color(white: 1, opacity: 0.96)
        /// вторичные строки, описания, подписи, иконки в покое
        public static let secondary = Color(white: 1, opacity: 0.7)
        /// мета: время, счётчики, номера строк
        public static let tertiary = Color(white: 1, opacity: 0.5)
        /// недоступное
        public static let disabled = Color(white: 1, opacity: 0.38)
        /// ссылки, интерактивный текст, акценты
        public static let accent = Color(hexValue: 0x7C9AFF)
        /// второстепенные акценты, активные иконки в плотных списках
        public static let accentMuted = Color(hexValue: 0x6B8CFF)
        /// текст на ультрамарине (5.1:1); на пурпуре (4.2:1), мадженте (3.1:1) и янтаре (1.8:1) белый ЗАПРЕЩЁН — там тёмный bg.base
        public static let onAccent = Color(white: 1, opacity: 1)
    }

    /// Осветлённые и слегка десатурированные под тёмный фон; заливки — тот же цвет с альфой, не отдельные тёмные оттенки. Цвет всегда дублируется формой/иконкой (дейтеранопия).
    public enum Semantic {
        /// approve/принято, зелёный диффа, пройденная стадия
        public static let success = Color(hexValue: 0x4ADE80)
        /// заливка плашки
        public static let successFill = Token.Semantic.success.opacity(0.14)
        /// бордер плашки (опционально)
        public static let successBorder = Token.Semantic.success.opacity(0.3)
        /// request changes, зависший луп, устаревший снапшот
        public static let warning = Color(hexValue: 0xFBBF24)
        /// заливка плашки
        public static let warningFill = Token.Semantic.warning.opacity(0.14)
        /// бордер плашки (опционально)
        public static let warningBorder = Token.Semantic.warning.opacity(0.3)
        /// fail стадии, красный диффа, деструктивные действия
        public static let error = Color(hexValue: 0xF87171)
        /// заливка плашки
        public static let errorFill = Token.Semantic.error.opacity(0.14)
        /// бордер плашки (опционально)
        public static let errorBorder = Token.Semantic.error.opacity(0.3)
        /// live/стрим, работа агента, нейтральные уведомления
        public static let info = Token.Brand.purple
        /// заливка плашки
        public static let infoFill = Token.Brand.purple.opacity(0.14)
        /// бордер плашки (опционально)
        public static let infoBorder = Token.Brand.purple.opacity(0.3)
    }

    /// Дифф и код. Подсветка синтаксиса — тема на базе фирменной гаммы (светлый ультрамарин #7C9AFF для типов/функций, пурпур для ключевых слов, маджента для констант + нейтрали), референсы One Dark / Tokyo Night, контраст токенов ≥4.5:1.
    public enum Diff {
        /// фон добавленной строки
        public static let addedBg = Token.Semantic.success.opacity(0.12)
        /// текст добавленной строки
        public static let addedText = Token.Semantic.success
        /// word-level подсветка внутри строки
        public static let addedWord = Token.Semantic.success.opacity(0.25)
        /// фон удалённой строки
        public static let removedBg = Token.Semantic.error.opacity(0.12)
        /// текст удалённой строки
        public static let removedText = Token.Semantic.error
        /// word-level подсветка внутри строки
        public static let removedWord = Token.Semantic.error.opacity(0.25)
        /// фон изменённой строки
        public static let changedBg = Token.Semantic.warning.opacity(0.1)
    }

    public enum Code {
        /// панель кода/диффа/лога
        public static let bg = Token.Background.surface
        /// номера строк: tabular, выключка вправо
        public static let linenum = Token.Text.tertiary
    }

    /// База 4pt, рабочая единица 8pt. Инвариант: внутреннее ≤ внешнее (Бирман). Соседние значения различаются минимум на шаг шкалы, промежуточных значений нет.
    public enum Space {
        /// иконка↔текст в лейбле, внутренности бейджа (верт.)
        public static let step1: CGFloat = 4
        /// внутри групп: строки формы, иконка↔заголовок
        public static let step2: CGFloat = 8
        /// паддинги компактных контролов, ячеек таблиц, карточек канбана
        public static let step3: CGFloat = 12
        /// паддинг панелей, полей, модалок; между соседними блоками
        public static let step4: CGFloat = 16
        /// между группами внутри секции, поля контентных областей
        public static let step5: CGFloat = 24
        /// между секциями экрана
        public static let step6: CGFloat = 32
        /// крупные разрывы, поля контентной колонки
        public static let step8: CGFloat = 48
        /// пустые состояния, hero-зоны
        public static let step10: CGFloat = 64
    }

    /// Система концентрическая: вложенный радиус = внешний − паддинг. Окна скругляет система.
    public enum Radius {
        /// бейджи, теги, мелкие плашки, чекбоксы
        public static let small: CGFloat = 4
        /// кнопки (компакт и дефолт), поля ввода, пункты-выделения в списках
        public static let medium: CGFloat = 6
        /// карточки, поповеры, тосты, крупные кнопки (36pt)
        public static let large: CGFloat = 10
        /// модалки, крупные панели
        public static let extraLarge: CGFloat = 14
        /// точки-статусы, счётчики-пилюли, орб
        public static let full: CGFloat = 999
    }

    /// SF Pro Text + SF Mono; шкала ≈1.2, привязана к macOS text styles. Цифры в таблицах, счётчиках, логе и аналитике — всегда tabular. Веса Light/Thin на тёмном ЗАПРЕЩЕНЫ. Таблицы в 04-typography.md и здесь обязаны совпадать буквально.
    public enum Typography {
        /// знак продукта «Foundry AI» и hero-заголовок первого запуска; базовый кегль знака — внутренние меры знака считаются em-ами от него
        public static let hero = TypeToken(size: 34, leading: 40, weight: .bold, family: .text, tracking: -0.02)
        /// число-KPI в аналитике
        public static let display = TypeToken(size: 26, leading: 32, weight: .bold, family: .text)
        /// заголовок экрана/окна
        public static let title = TypeToken(size: 20, leading: 25, weight: .semibold, family: .text)
        /// заголовки секций, карточек
        public static let heading = TypeToken(size: 16, leading: 21, weight: .semibold, family: .text)
        /// основной текст UI (дефолт macOS)
        public static let body = TypeToken(size: 13, leading: 18, weight: .regular, family: .text)
        /// акценты в тексте, имена в строках
        public static let bodyEm = TypeToken(size: 13, leading: 18, weight: .semibold, family: .text)
        /// мета, подписи, заголовки колонок
        public static let caption = TypeToken(size: 11, leading: 14, weight: .regular, family: .text)
        /// самый мелкий вспомогательный текст
        public static let caption2 = TypeToken(size: 10, leading: 13, weight: .regular, family: .text)
        /// лейблы секций сайдбара
        public static let label = TypeToken(size: 11, leading: 13, weight: .medium, family: .text, isUppercased: true, tracking: 0.06)
        /// код, дифф, лог (интерлиньяж ≥150% для кода)
        public static let mono = TypeToken(size: 12, leading: 20, weight: .regular, family: .mono)
        /// номера строк, inline-код в мете
        public static let monoSmall = TypeToken(size: 10, leading: 14, weight: .regular, family: .mono)
    }

    /// «-apple-system» стоит первым не для красоты: он отдаёт системный SF с живой оптической осью, и macOS сама переключает Text → Display на пороге ~20 pt. Имя семейства первым («SF Pro Text») эту ось выключает — на машине, где SF Pro установлен, оно перехватывает стек и прибивает Text ко всем кеглям, включая type.display и type.hero. Канон 04, раздел 2.1 требует ровно обратного: «система переключает оптический размер сама — не мешать, не форсировать». Порядок здесь и есть исполнение этого правила.
    public enum FontStack {
        /// весь интерфейсный текст
        public static let text: [String] = ["-apple-system", "BlinkMacSystemFont", "SF Pro Text", "system-ui", "sans-serif"]
        /// код, дифф, лог
        public static let mono: [String] = ["SF Mono", "ui-monospace", "Menlo", "monospace"]
    }

    /// Размеры контролов и целей. Минимальная кликабельная цель — Фиттс, 07-interaction.md.
    public enum Control {
        /// высота кнопок/полей в плотных панелях
        public static let hCompact: CGFloat = 24
        /// высота кнопок/полей по умолчанию
        public static let hDefault: CGFloat = 28
        /// primary в пустых состояниях, модалках
        public static let hLarge: CGFloat = 36
        /// минимальная кликабельная цель 24×24pt; в тулбаре — 28×28
        public static let hitMin: CGFloat = 24
    }

    public enum Icon {
        /// мелкая иконка
        public static let small: CGFloat = 12
        /// иконка по умолчанию
        public static let medium: CGFloat = 16
        /// крупная иконка; в тексте SF Symbols масштабируются сами
        public static let large: CGFloat = 20
    }

    public enum Row {
        /// строка списка в сайдбаре
        public static let compact: CGFloat = 28
        /// строка списка по умолчанию
        public static let `default`: CGFloat = 36
        /// двухстрочная строка (инбокс)
        public static let double: CGFloat = 52
    }

    /// Анимация — только смысловая (появление, перемещение, live-состояние); декоративного движения нет. Reduce Motion уважается всегда.
    public enum Motion {
        /// hover, подсветки, мелкие переходы
        public static let fast = MotionToken(duration: 0.15, animation: .easeOut(duration: 0.15))
        /// раскрытия, поповеры, смена панелей
        public static let base = MotionToken(duration: 0.22, animation: .easeInOut(duration: 0.22))
        /// модалки, крупные перестановки (канбан)
        public static let slow = MotionToken(duration: 0.32, animation: .timingCurve(0.22, 1, 0.36, 1, duration: 0.32))
        /// пульс орба и live-индикатора при стриме
        /// Непрерывное состояние, а не переход: длительности нет,
        /// пульс задаёт сама сцена (мягкая, непрерывная).
        public static let live = MotionToken(duration: nil, animation: nil)
    }

    /// Фирменная замена тени для акцентов — «свет в темноте». Рецепт двухслойный (06-color.md, раздел 5.6): внутренний ореол blur 10 @ 40% + внешний blur 36 @ 15% цвета токена. ЖЁСТКОЕ ПРАВИЛО: не больше одного свечения в поле зрения. Glow не применяется к тексту, таблицам и данным.
    public enum Glow {
        /// primary-кнопка (hover), активная стадия пайплайна
        public static let accent = GlowToken(color: Token.Brand.ultramarine)
        /// индикатор работы Claude, live-лог
        public static let live = GlowToken(color: Token.Brand.purple)
        /// только орб
        /// Градиент, а не тень: заливка орба — brand.gradient.
        /// Значения свечения здесь нет намеренно.
    }
}
