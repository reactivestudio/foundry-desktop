// СГЕНЕРИРОВАНО design/build.py — не править руками
// ЕДИНСТВЕННЫЙ ИСТОЧНИК ЗНАЧЕНИЙ foundry-desktop. Правится только здесь. Из него build.py генерит tokens.css (макеты), Tokens.swift (приложение) и таблицы значений в docs/design/13-tokens.md (канон). Руками эти три не править — перезатрёт. Обоснования значений — проза канона, здесь только вердикты. Нет нужного токена — сначала добавить сюда, потом использовать.

import SwiftUI

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

enum Token {
    /// Фирменная гамма: аналоговый ход ультрамарин → пурпур → маджента (OKLCH hue 266 → 293 → 316) + циан как «точка света». Мотив — орб, свет в темноте. Оранжевый/ember отвергнут, не возвращать → rejected/ember-palette.md
    enum Brand {
        /// главный акцент: primary-действия, активные состояния, выделение
        static let ultramarine = Color(hexValue: 0x2F5CFF)
        /// вторичный акцент: градиенты, AI-сущности
        static let purple = Color(hexValue: 0x8B5CF6)
        /// третичный: только в градиентах и орбе, не как самостоятельный цвет UI
        static let magenta = Color(hexValue: 0xD65CFF)
        /// «точка света»: данные, live-индикация, блики орба
        static let cyan = Color(hexValue: 0x58C7FF)
        /// ТОЛЬКО знак: логотип «Foundry AI» и фирменные места, где он появляется целиком. НИКОГДА не статус и не состояние — для этого есть sem.warning. Разведение ролей обязательно и держится дисциплиной, а не глазом: янтарь всего в 9° от sem.warning #FBBF24, глаз их не различит. Отсюда правило: увидел жёлтый в UI — это sem.warning; увидел жёлтый в знаке — это brand.amber; в одном экране они не встречаются.
        static let amber = Color(hexValue: 0xFFB020)
        /// орб, hero-акценты
        /// Интерполяция канона — oklch; SwiftUI смешивает в своём
        /// пространстве, поэтому опорные точки заданы явно.
        static let gradient = LinearGradient(
            colors: [Token.Brand.ultramarine, Token.Brand.purple, Token.Brand.magenta],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Elevation через светлоту, не через тень: равные шаги ΔL ≈ 0.03 в OKLCH, hue удержан в фиолетовой зоне 294±1, хрома растёт с высотой. Слой не перепрыгивает уровни; уровней на экране ≤3. Сайдбар и тулбар — системный Liquid Glass, их фон не хардкодим. Лестница сдвинута 2026-07-17 на шкалу принятого эталона онбординга (было #07060B/#0D0C14/#14121E/#1B1828): она исполняет правило канона точнее прежней — hue держится в 1.1° против прежнего разброса в 5°, при тех же шагах ΔL и растущей хроме. Все контрасты пересчитаны, сдвиг ≤0.3, ни один порог не пересечён.
    enum Background {
        /// фон окна, фон контентной зоны
        static let base = Color(hexValue: 0x05030D)
        /// карточки канбана, строки-контейнеры, панель кода/диффа/лога
        static let surface = Color(hexValue: 0x0B0717)
        /// поповеры, меню, тултипы, sticky-заголовки
        static let raised = Color(hexValue: 0x120B23)
        /// модалки/шиты (плюс скрим под ними)
        static let overlay = Color(hexValue: 0x1A1030)
        /// hover строк, карточек, пунктов меню
        static let hover = Color(white: 1, opacity: 0.06)
        /// нажатое состояние плоских элементов
        static let pressed = Color(white: 1, opacity: 0.1)
        /// выбранная строка/пункт; карточка — заливка 14% + бордер ультрамарин @ 50%
        static let selected = Token.Brand.ultramarine.opacity(0.14)
        /// подложка модалок; допуск 40–60%, с блюром 8–12px — 35–45%
        static let scrim = Color(white: 0, opacity: 0.5)
    }

    /// Дефолт — вообще без линейки: сначала воздух и выравнивание, линейка — осознанное исключение.
    enum Border {
        /// разделители списков (только многострочных), линии таблиц, сетки графиков
        static let subtle = Color(white: 1, opacity: 0.08)
        /// контур карточек, полей ввода, бейджей
        static let `default` = Color(white: 1, opacity: 0.12)
        /// hover-контур, обводка secondary-кнопок
        static let strong = Color(white: 1, opacity: 0.2)
        /// цвет фокус-ринга клавиатуры
        static let focus = Token.Brand.ultramarine
        /// толщина фокус-ринга клавиатуры
        static let focusWidth: CGFloat = 2
        /// отбивка фокус-ринга от элемента
        static let focusOffset: CGFloat = 2
    }

    /// Альфа-белый, не серые хардкоды. Ни один цвет палитры не используется как цвет текста: brand.ultramarine на тёмном даёт 4.0:1 и не проходит — текстом всегда text.accent. Контрасты посчитаны на bg.base, обоснования — 06-color.md §4.2.
    enum Text {
        /// основной текст, заголовки; длинное чтение — 85–90%
        static let primary = Color(white: 1, opacity: 1)
        /// вторичные строки, описания, подписи, иконки в покое
        static let secondary = Color(white: 1, opacity: 0.7)
        /// мета: время, счётчики, номера строк
        static let tertiary = Color(white: 1, opacity: 0.5)
        /// недоступное
        static let disabled = Color(white: 1, opacity: 0.38)
        /// ссылки, интерактивный текст, акценты
        static let accent = Color(hexValue: 0x7C9AFF)
        /// второстепенные акценты, активные иконки в плотных списках
        static let accentMuted = Color(hexValue: 0x6B8CFF)
        /// текст на ультрамарине (5.1:1) и пурпуре (4.2:1); на циане, мадженте и янтаре белый ЗАПРЕЩЁН (1.9:1, 3.1:1, 1.8:1) — там тёмный bg.base
        static let onAccent = Color(white: 1, opacity: 1)
    }

    /// Осветлённые и слегка десатурированные под тёмный фон; заливки — тот же цвет с альфой, не отдельные тёмные оттенки. Цвет всегда дублируется формой/иконкой (дейтеранопия).
    enum Semantic {
        /// approve/принято, зелёный диффа, пройденная стадия
        static let success = Color(hexValue: 0x4ADE80)
        /// заливка плашки
        static let successFill = Token.Semantic.success.opacity(0.14)
        /// бордер плашки (опционально)
        static let successBorder = Token.Semantic.success.opacity(0.3)
        /// request changes, зависший луп, устаревший снапшот
        static let warning = Color(hexValue: 0xFBBF24)
        /// заливка плашки
        static let warningFill = Token.Semantic.warning.opacity(0.14)
        /// бордер плашки (опционально)
        static let warningBorder = Token.Semantic.warning.opacity(0.3)
        /// fail стадии, красный диффа, деструктивные действия
        static let error = Color(hexValue: 0xF87171)
        /// заливка плашки
        static let errorFill = Token.Semantic.error.opacity(0.14)
        /// бордер плашки (опционально)
        static let errorBorder = Token.Semantic.error.opacity(0.3)
        /// live/стрим, работа агента, нейтральные уведомления
        static let info = Token.Brand.cyan
        /// заливка плашки
        static let infoFill = Token.Brand.cyan.opacity(0.14)
        /// бордер плашки (опционально)
        static let infoBorder = Token.Brand.cyan.opacity(0.3)
    }

    /// Дифф и код. Подсветка синтаксиса — тема на базе фирменной гаммы (циан/пурпур/маджента + нейтрали), референсы One Dark / Tokyo Night, контраст токенов ≥4.5:1.
    enum Diff {
        /// фон добавленной строки
        static let addedBg = Token.Semantic.success.opacity(0.12)
        /// текст добавленной строки
        static let addedText = Token.Semantic.success
        /// word-level подсветка внутри строки
        static let addedWord = Token.Semantic.success.opacity(0.25)
        /// фон удалённой строки
        static let removedBg = Token.Semantic.error.opacity(0.12)
        /// текст удалённой строки
        static let removedText = Token.Semantic.error
        /// word-level подсветка внутри строки
        static let removedWord = Token.Semantic.error.opacity(0.25)
        /// фон изменённой строки
        static let changedBg = Token.Semantic.warning.opacity(0.1)
    }

    enum Code {
        /// панель кода/диффа/лога
        static let bg = Token.Background.surface
        /// номера строк: tabular, выключка вправо
        static let linenum = Token.Text.tertiary
    }

    /// База 4pt, рабочая единица 8pt. Инвариант: внутреннее ≤ внешнее (Бирман). Соседние значения различаются минимум на шаг шкалы, промежуточных значений нет.
    enum Space {
        /// иконка↔текст в лейбле, внутренности бейджа (верт.)
        static let step1: CGFloat = 4
        /// внутри групп: строки формы, иконка↔заголовок
        static let step2: CGFloat = 8
        /// паддинги компактных контролов, ячеек таблиц, карточек канбана
        static let step3: CGFloat = 12
        /// паддинг панелей, полей, модалок; между соседними блоками
        static let step4: CGFloat = 16
        /// между группами внутри секции, поля контентных областей
        static let step5: CGFloat = 24
        /// между секциями экрана
        static let step6: CGFloat = 32
        /// крупные разрывы, поля контентной колонки
        static let step8: CGFloat = 48
        /// пустые состояния, hero-зоны
        static let step10: CGFloat = 64
    }

    /// Система концентрическая: вложенный радиус = внешний − паддинг. Окна скругляет система.
    enum Radius {
        /// бейджи, теги, мелкие плашки, чекбоксы
        static let small: CGFloat = 4
        /// кнопки (компакт и дефолт), поля ввода, пункты-выделения в списках
        static let medium: CGFloat = 6
        /// карточки, поповеры, тосты, крупные кнопки (36pt)
        static let large: CGFloat = 10
        /// модалки, крупные панели
        static let extraLarge: CGFloat = 14
        /// точки-статусы, счётчики-пилюли, орб
        static let full: CGFloat = 999
    }

    /// SF Pro Text + SF Mono; шкала ≈1.2, привязана к macOS text styles. Цифры в таблицах, счётчиках, логе и аналитике — всегда tabular. Веса Light/Thin на тёмном ЗАПРЕЩЕНЫ. Таблицы в 04-typography.md и здесь обязаны совпадать буквально.
    enum Typography {
        /// число-KPI в аналитике
        static let display = TypeToken(size: 26, leading: 32, weight: .bold, family: .text)
        /// заголовок экрана/окна
        static let title = TypeToken(size: 20, leading: 25, weight: .semibold, family: .text)
        /// заголовки секций, карточек
        static let heading = TypeToken(size: 16, leading: 21, weight: .semibold, family: .text)
        /// основной текст UI (дефолт macOS)
        static let body = TypeToken(size: 13, leading: 18, weight: .regular, family: .text)
        /// акценты в тексте, имена в строках
        static let bodyEm = TypeToken(size: 13, leading: 18, weight: .semibold, family: .text)
        /// мета, подписи, заголовки колонок
        static let caption = TypeToken(size: 11, leading: 14, weight: .regular, family: .text)
        /// самый мелкий вспомогательный текст
        static let caption2 = TypeToken(size: 10, leading: 13, weight: .regular, family: .text)
        /// лейблы секций сайдбара
        static let label = TypeToken(size: 11, leading: 13, weight: .medium, family: .text, isUppercased: true, tracking: 0.06)
        /// код, дифф, лог (интерлиньяж ≥150% для кода)
        static let mono = TypeToken(size: 12, leading: 20, weight: .regular, family: .mono)
        /// номера строк, inline-код в мете
        static let monoSmall = TypeToken(size: 10, leading: 14, weight: .regular, family: .mono)
    }

    enum FontStack {
        /// весь интерфейсный текст
        static let text: [String] = ["SF Pro Text", "-apple-system", "BlinkMacSystemFont", "system-ui", "sans-serif"]
        /// код, дифф, лог
        static let mono: [String] = ["SF Mono", "ui-monospace", "Menlo", "monospace"]
    }

    /// Размеры контролов и целей. Минимальная кликабельная цель — Фиттс, 07-interaction.md.
    enum Control {
        /// высота кнопок/полей в плотных панелях
        static let hCompact: CGFloat = 24
        /// высота кнопок/полей по умолчанию
        static let hDefault: CGFloat = 28
        /// primary в пустых состояниях, модалках
        static let hLarge: CGFloat = 36
        /// минимальная кликабельная цель 24×24pt; в тулбаре — 28×28
        static let hitMin: CGFloat = 24
    }

    enum Icon {
        /// мелкая иконка
        static let small: CGFloat = 12
        /// иконка по умолчанию
        static let medium: CGFloat = 16
        /// крупная иконка; в тексте SF Symbols масштабируются сами
        static let large: CGFloat = 20
    }

    enum Row {
        /// строка списка в сайдбаре
        static let compact: CGFloat = 28
        /// строка списка по умолчанию
        static let `default`: CGFloat = 36
        /// двухстрочная строка (инбокс)
        static let double: CGFloat = 52
    }

    /// Анимация — только смысловая (появление, перемещение, live-состояние); декоративного движения нет. Reduce Motion уважается всегда.
    enum Motion {
        /// hover, подсветки, мелкие переходы
        static let fast = MotionToken(duration: 0.15, animation: .easeOut(duration: 0.15))
        /// раскрытия, поповеры, смена панелей
        static let base = MotionToken(duration: 0.22, animation: .easeInOut(duration: 0.22))
        /// модалки, крупные перестановки (канбан)
        static let slow = MotionToken(duration: 0.32, animation: .timingCurve(0.22, 1, 0.36, 1, duration: 0.32))
        /// пульс орба/циана при стриме
        /// Непрерывное состояние, а не переход: длительности нет,
        /// пульс задаёт сама сцена (мягкая, непрерывная).
        static let live = MotionToken(duration: nil, animation: nil)
    }

    /// Фирменная замена тени для акцентов — «свет в темноте». Рецепт двухслойный (06-color.md §5.6): внутренний ореол blur 10 @ 40% + внешний blur 36 @ 15% цвета токена. ЖЁСТКОЕ ПРАВИЛО: не больше одного свечения в поле зрения. Glow не применяется к тексту, таблицам и данным.
    enum Glow {
        /// primary-кнопка (hover), активная стадия пайплайна
        static let accent = GlowToken(color: Token.Brand.ultramarine)
        /// индикатор работы Claude, live-лог
        static let live = GlowToken(color: Token.Brand.cyan)
        /// только орб
        /// Градиент, а не тень: заливка орба — brand.gradient.
        /// Значения свечения здесь нет намеренно.
    }
}
