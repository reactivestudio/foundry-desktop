# 05 · macOS: визуальный дизайн и UI-паттерны

> Серия practices · [оглавление](README.md)

Эта глава — про то, как foundry-desktop **выглядит**: актуальный дизайн-язык (Liquid Glass), типографика и плотность, цвет и материалы, SF Symbols, иконка приложения и — главное — конкретные паттерны dev-инструментов для каждого нашего экрана: сайдбар проектов, канбан change'ей, ревью markdown-артефактов с диффом и комментариями, live-лог, аналитика. Поведение (меню, окна, клавиатура, drag & drop) — в [04-macos-platform.md](04-macos-platform.md). Код сцен — в [03-swiftui-architecture.md](03-swiftui-architecture.md); WKWebView-остров для рендера diff/markdown — в [06-system-integration.md](06-system-integration.md).

Таргет: **macOS 26 SDK (Tahoe), Xcode 26**.

---

## 1. Дизайн-язык: Liquid Glass

### 1.1 Состояние на середину 2026

- **WWDC25 (июнь 2025)**: Apple представила **Liquid Glass** — первый единый кросс-платформенный дизайн-язык (iOS/iPadOS/macOS 26 «Tahoe»/tvOS/watchOS/visionOS 26). Полупрозрачный, преломляющий, динамический материал для **слоя управления/навигации**, плавающего над контентом.
- **macOS 26 Tahoe** вышла в сентябре 2025: на Mac эффект сдержаннее, чем на iOS, но затрагивает тулбары, сайдбары, меню, контролы, алерты, меню-бар (полностью прозрачный) и иконки приложений.
- **WWDC26: macOS 27 «Golden Gate»** — Liquid Glass **не отменён, а шлифуется**: пользовательский слайдер прозрачности, ужесточённый единый радиус углов окон (даже для не обновлённых приложений), диффузные тени для читаемости, более консистентные системные иконки. Релиз — осень 2026.

⚠️ **Устарело:** дизайн-язык эпохи Big Sur–Sequoia (2020–2024): непрозрачные unified-тулбары как часть окна, freeform-иконки, «плоские» сайдбары в теле окна. Всё, что рисовалось «под старый Mac» с ручными фонами тулбаров, теперь выглядит чужим.

### 1.2 Двухслойная модель — главная ментальная схема

UI = два слоя:

| Слой | Что | Материал | В foundry-desktop |
|---|---|---|---|
| **Content layer** | Документы, данные, рабочая область | Обычные материалы и фоны (`windowBackgroundColor`, `controlBackgroundColor`, `Material.*`) | Дифф, markdown, лог-таблица, доска, чарты |
| **Functional layer** | Плавающая навигация и управление | **Liquid Glass** | Тулбар, сайдбар, меню, popovers, алерты |

Правила:

1. **Стекло никогда не в контенте.** `glassEffect(_:in:)` существует, но HIG прямо говорит: системные компоненты уже стеклянные; кастомное стекло — только для считанных важнейших плавающих элементов. Кандидат №1 у нас — плавающая пилюля «Jump to latest» над логом (§6.4). Стеклянная карточка канбана или стеклянная строка диффа — ошибка.
2. **Контент уходит под chrome.** `backgroundExtensionEffect()` растягивает контент под плавающий сайдбар/инспектор; **scroll edge effects** (`ScrollEdgeEffectStyle`) отделяют тулбар от проскролленного контента вместо непрозрачного фона тулбара.
3. **Стекло бесцветно.** Иконки на тулбаре — монохром, авто-адаптация light/dark под контент внизу. **Accent — только на одном главном действии** (`.prominent`: у нас — «Submit Review»). Тонировать несколько контролов — нельзя.
4. **Два варианта стекла**: **regular** (блюрит фон — для text-heavy: сайдбары, алерты, popovers) и **clear** (сильно прозрачный — только поверх визуально насыщенного медиа; может требовать ~35% dim-слой). Для dev-инструмента практически всегда regular.
5. **Пользовательские настройки меняют стекло**: Reduce Transparency, Increase Contrast, слайдер прозрачности macOS 27. Поэтому у каждого кастомного цвета — light+dark варианты, «даже если приложение в одном режиме» (HIG Color).
6. **Концентрические радиусы**: радиусы кастомных компонентов согласуются с радиусами контейнера/окна; macOS 27 ужесточает радиусы окон — **не хардкодить радиусы**, выводить из контейнера.

### 1.3 SwiftUI на macOS 26 SDK даёт новый дизайн почти бесплатно

Собранное на стандартных компонентах приложение получает Liquid Glass без усилий:

- `NavigationSplitView` → **плавающий стеклянный сайдбар**;
- `.toolbar { }` → стекло + scroll edge effects + автоматический overflow;
- стандартные контролы → стеклянный вид и морфинг.

```swift
// ХОРОШО: каркас, который «бесплатно» выглядит по-новому
NavigationSplitView {
    ProjectsSidebar()            // стеклянный floating sidebar
        .listStyle(.sidebar)
} content: {
    ChangesList()
} detail: {
    ChangeDetail()
        .backgroundExtensionEffect()   // контент тянется под chrome
}
.toolbar { … }                   // стекло + scroll edge effect

// ПЛОХО: ручная имитация — мгновенно устаревает и ломает адаптивность
VStack(spacing: 0) {
    CustomToolbar().background(Color(nsColor: .windowBackgroundColor))
    HStack { CustomSidebar().background(.ultraThinMaterial); Detail() }
}
```

Вывод для проекта: **стандартные контейнеры — обязательны**. Кастомный chrome — не только больше кода, но и гарантированное визуальное отставание при каждом мажорном релизе macOS.

### 1.4 Тулбар в новом дизайне: визуальные правила

⚠️ **Устарело:** таксономия стилей unified/inline/expanded ушла; актуальная модель — плавающий стеклянный тулбар с тремя регионами размещения (leading / center / trailing; поведение регионов и кастомизация — [04-macos-platform.md](04-macos-platform.md) §3.4).

- Элементы — **borderless SF Symbols**; текстовые лейблы — только для несимволизируемых действий («Edit»); между соседними текстовыми кнопками — фиксированный спейсер.
- **Никаких кастомных фонов/тинтов тулбара** — вид тулбара информирует контент под ним; отделение от проскролленного контента — `ScrollEdgeEffectStyle`, не opaque-полоса.
- Один `.prominent` (тонированный) элемент на тулбар — наш «Submit Review» в окне ревью; всё остальное — монохром.
- Максимум ~3 визуальные группы элементов.
- Заголовок окна в leading-регионе — осмысленный (имя change'а/проекта), ≤15 символов до усечения, никогда — имя приложения.

---

## 2. Типографика и плотность

### 2.1 Шрифты

- **SF Pro** — системный шрифт; **SF Mono** — код, диффы, логи (`Font.system(.body, design: .monospaced)`); никогда не эмбеддить системные шрифты — только API, optical sizing автоматический.
- Веса Ultralight/Thin/Light — избегать.
- **Body на macOS = 13 pt, минимум 10 pt** (vs 17/11 на iOS). Это первая и главная цифра плотности: приложение, набранное 17-м кеглем, кричит «iPad-порт».

### 2.2 Таблица text styles macOS (точные значения)

| Style | Weight | Size, pt | Line height, pt | Emphasized |
|---|---|---|---|---|
| Large Title | Regular | 26 | 32 | Bold |
| Title 1 | Regular | 22 | 26 | Bold |
| Title 2 | Regular | 17 | 22 | Bold |
| Title 3 | Regular | 15 | 20 | Semibold |
| Headline | Bold | 13 | 16 | Heavy |
| Body | Regular | 13 | 16 | Semibold |
| Callout | Regular | 12 | 15 | Semibold |
| Subheadline | Regular | 11 | 14 | Semibold |
| Footnote | Regular | 10 | 13 | Semibold |
| Caption 1 | Regular | 10 | 13 | Medium |
| Caption 2 | Medium | 10 | 13 | Semibold |

Использовать **стили, не point sizes**: ⚠️ Dynamic Type на macOS не существует, но Tahoe добавил Accessibility Text Size (глобально/per-app) — наследуется только через text styles. Контент (дифф/лог/markdown) дополнительно зумится ⌘+/⌘− (см. [04-macos-platform.md](04-macos-platform.md) §5.3).

Раскладка по нашим экранам:

| Элемент | Стиль |
|---|---|
| Заголовок change'а в detail | Title 2 / Title 3 |
| Заголовок карточки канбана | Body (13 pt) |
| Метаданные карточки (агент, время) | Subheadline / Caption 1, `secondaryLabelColor` |
| Текст диффа и лога | SF Mono, Body-размер с зумом |
| Заголовки колонок канбана и таблиц | Headline |
| Счётчики в сайдбаре | Caption 1 |

### 2.3 Размеры контролов и хит-таргеты

- macOS: **минимальный контрол 20×20 pt, дефолтный 28×28 pt** (vs 44 pt iOS) — кодифицированная разница плотности.
- Размеры контролов: `mini / small / regular / large` через `.controlSize(_:)`. Про-инструменты используют **`.small` в плотных панелях** (инспектор, фильтр-бары, тулбары панелей), regular — в остальном UI. Ориентиры высот кнопок AppKit: regular ~20–22 pt, small ~17–19 pt, mini ~14–16 pt.
- Отступы: сетка 8 pt; классические 20 pt поля от края окна; ~12 pt вокруг bezeled-элементов.

```swift
// Инспектор карточки: плотная панель про-инструмента
Form { … }
    .formStyle(.grouped)
    .controlSize(.small)      // ← плотность инспектора
```

### 2.4 Плотность — главный рычаг против «iPad-порта»

Симптомы и лечение:

| // ПЛОХО (iPad-порт) | // ХОРОШО (Mac) |
|---|---|
| NavigationStack: список → push → детали → push | Трёхпанельный split: список и детали видны одновременно |
| Карточки-«плитки» со stacked-полями | Многоколоночная `Table` с сортировкой |
| Видимый ряд кнопок действий на каждой строке | Hover-действия + контекстное меню |
| Sheet на каждый чих | Инспектор / popover / inline-edit |
| 17 pt текст, 44 pt строки | 13 pt Body, строки 28 pt (24 при `.small`) |
| Пустоты «для воздуха» | Информация: «больше контента, меньше вложенных уровней» (HIG) |

Прогрессивное раскрытие — через disclosure-контролы и инспектор, не через навигацию вглубь.

---

## 3. Цвет и материалы

### 3.1 Семантические цвета — никогда не хардкодить

Динамические системные цвета macOS (AppKit-имена, бриджатся в SwiftUI): `labelColor`/`secondaryLabelColor`/`tertiaryLabelColor`/`quaternaryLabelColor`, `textColor`, `textBackgroundColor`, `windowBackgroundColor`, `controlBackgroundColor` (таблицы), `underPageBackgroundColor`, `separatorColor`, `gridColor`, `headerTextColor`, **`selectedContentBackgroundColor` + `unemphasizedSelectedContentBackgroundColor`** (selection в key/non-key окне!), `selectedTextBackgroundColor`, `keyboardFocusIndicatorColor`, `controlAccentColor`, `linkColor`, `placeholderTextColor`, `findHighlightColor`, `alternatingContentBackgroundColors`.

Не переопределять семантику (separator ≠ цвет текста). Стандартная палитра (red/orange/yellow/green/mint/teal/cyan/blue/indigo/purple/pink/brown) сама адаптируется к light/dark/Increase Contrast.

Маппинг на данные foundry-desktop:

| Данные | Цвет |
|---|---|
| Дифф: added / removed | системные green/red: **низкая opacity для фона строки**, полная — для бейджей и +/− в гаттере |
| Лог-уровни | red = error, yellow = warn, `secondaryLabelColor` = debug; иконка + текст, не только цвет |
| Selection везде | `selectedContentBackgroundColor` — key/non-key состояния бесплатно |
| Тэги канбана, серии чартов | стандартная семантическая палитра, консистентная между экранами |
| Chrome, панели, разделители | только системные семантические цвета — кастом резервируем под данные/статусы |

```swift
// ПЛОХО: хардкод — ломается в dark mode, Increase Contrast и на стекле
.background(selected ? Color(red: 0, green: 0.48, blue: 1) : .white)

// ХОРОШО:
.background(selected
    ? Color(nsColor: .selectedContentBackgroundColor)
    : Color(nsColor: .controlBackgroundColor))
```

### 3.2 Accent color: пользователь главнее

- Шипим `AccentColor`-asset; он действует **только когда системный accent = multicolor**. Любой выбранный пользователем accent заменяет наш **везде, включая иконки сайдбара**. Фиксированный цвет иконки — только когда цвет несёт смысл (как жёлтый VIP в Mail), экономно.
- Graphite-accent включает **desktop tinting** фонов окон → нейтральным кастомным фонам — лёгкую полупрозрачность, чтобы гармонировали.
- На стекле (§1.2) accent — только у одного prominent-действия.

### 3.3 Dark mode дисциплина

- **Никакого in-app переключателя темы** — «люди могут решить, что приложение сломано» (HIG).
- Каждый кастомный цвет — Color Set с light/dark (+ high-contrast) вариантами; это же требование Liquid Glass-адаптивности.
- Тестовая матрица: Light, Dark, Auto-переключение, Increase Contrast, Reduce Transparency — и их комбинации.
- Контраст ≥4.5:1 (7:1 для мелкого кастомно-окрашенного текста); чисто-белые контентные фоны в dark mode приглушать.
- SF Symbols адаптируются сами.

### 3.4 Материалы и vibrancy

- Стандартные материалы (`NSVisualEffectView` семантические материалы; SwiftUI `Material` ultraThin→thick) — **структура контентного слоя**; Liquid Glass — только плавающий functional layer.
- Материал выбирается **по семантической роли** (sidebar, menu, popover, under-window…), не по «подходящему цвету».
- На материалах — **vibrant** цвета текста/заливок (семантические label-цвета), никогда — плоские opaque-серые.
- Иерархия поверхностей 2026: фон окна (opaque/under-page) → контентные поверхности (`controlBackgroundColor`, alternating rows) → плавающий chrome (стеклянные сайдбар/тулбар) → транзиентные поверхности (materials popover/menu).

```swift
// ПЛОХО: opaque-серый на материале — «грязное» пятно, в dark mode разваливается
Text(card.agentName)
    .foregroundColor(Color(white: 0.45))
    .background(.regularMaterial)

// ХОРОШО: vibrant-семантика — система смешивает цвет с материалом сама
Text(card.agentName)
    .foregroundStyle(.secondary)
    .background(.regularMaterial)
```

---

## 4. SF Symbols

Текущий релиз — **SF Symbols 7** (WWDC25).

- Символы весово согласованы с SF и выравниваются с текстом автоматически; использовать во всех интерфейсных иконках: тулбар, сайдбар, меню, инлайн в тексте.
- **Rendering modes**: monochrome (дефолт тулбаров), hierarchical (один цвет, послойная opacity — хороший дефолт для сложных глифов), palette (2–3 явных цвета), multicolor. Automatic выбирает по контексту — проверять читаемость.
- **Weights/scales**: 9 весов под веса текста; 3 scale (small/medium/large) относительно cap height — `imageScale(_:)` меняет акцент, не ломая выравнивание с текстом.
- **Variants**: outline — дефолт для тулбаров/сайдбаров/списков; fill — акцент выделения; slash — «недоступно»; контейнеры часто сами подбирают вариант.
- **Variable color** — для меняющейся величины (сигнал, прогресс, ёмкость): «communicate change, not depth». Подходит для индикатора соединения/стриминга.
- **SF Symbols 7**: градиенты (из одного source-цвета, для крупных размеров) и **Draw On/Off** анимации (штрихи «рисуются» — семантика прогресса/загрузки).
- **`symbolEffect` — дисциплина**: только с коммуникативной целью, единицы на view, для смены статуса. Наши легитимные кейсы: `pulse`/`breathe` на глифе live-стрима лога, `rotate` на «agent running», Magic Replace при смене статуса change'а. Все циклические эффекты гейтятся Reduce Motion.
- **Кастомные символы**: экспорт template похожего символа → правка векторов → аннотация слоёв в приложении SF Symbols (rendering modes, variable color); совпадать по оптическому весу с системными; accessibility label обязателен. **Никогда не использовать SF Symbols (или похожие) в иконке приложения/логотипе.**

```swift
// Статус агента в строке канбан-карточки
Image(systemName: agent.isRunning ? "arrow.triangle.2.circlepath" : "checkmark.circle")
    .symbolRenderingMode(.hierarchical)
    .symbolEffect(.rotate, isActive: agent.isRunning && !reduceMotion)
    .accessibilityLabel(agent.isRunning ? "Agent running" : "Agent finished")
```

Нормативная таблица символов foundry-desktop — один смысл = один символ на всех экранах:

| Смысл | Symbol | Заметка |
|---|---|---|
| Change / карточка | `square.and.pencil` | outline в списках |
| Agent running | `arrow.triangle.2.circlepath` | + `.rotate` при активности |
| Success / done | `checkmark.circle` | fill — в статус-бейджах |
| Error | `xmark.octagon.fill` + red | всегда с текстом уровня |
| Warning | `exclamationmark.triangle.fill` + yellow | всегда с текстом уровня |
| Live-стрим лога | `dot.radiowaves.left.and.right` | `.pulse`/`.breathe`, гейт Reduce Motion |
| Review pending | `text.bubble` | бейдж-счётчик рядом, не в символе |
| Viewed (дифф) | `checkmark.circle` / `circle` | чекбокс-пара |
| Инспектор-toggle | `sidebar.trailing` | trailing-регион тулбара |

---

## 5. Иконка приложения

⚠️ **Устарело: freeform-иконки macOS мертвы.** До 2025 macOS-иконка могла быть произвольной формы с выступами (молоток поверх круга и т.п.). С macOS 26 это не рендерится как задумано — система принудительно вписывает legacy-иконки в squircle.

Актуальные правила (HIG App icons, ревизии июнь 2025 и июнь 2026):

- Иконка — **слоёная**: один background-слой + один или несколько foreground-слоёв; система рендерит её с **Liquid Glass-атрибутами** (спекулярные блики, рефракция, полупрозрачность, динамика от окружения и темы).
- Макет — **квадрат 1024×1024 px**; **squircle-маску накладывает система** (концентрично системной кривизне). Не пре-маскировать, не рисовать свои скругления/тени: «pre-defined masking negatively impacts specular highlight effects and makes edges look jagged».
- **Icon Composer** (идёт с Xcode 26) — обязательный на практике инструмент: импорт векторных слоёв (SVG/PDF), встроенные фоны (solid/gradient), настройка стекла (specular, refraction, translucency), аннотация вариантов **default / dark / mono(tinted)**, превью по версиям ОС, экспорт `.icon` для Xcode. Одна работа обслуживает iOS+iPadOS+macOS.
- **Варианты внешнего вида**: default, dark, clear (light/dark), tinted (light/dark) — пользователь выбирает их на Tahoe как на iOS. Система догенерирует недостающие, но ручные dark/mono выглядят лучше. Ядро формы — идентично во всех вариантах.
- Дизайн: простые залитые перекрывающиеся формы; глубина — вариацией opacity слоёв; **без текста, фото, реплик UI, тонких штрихов**, без изображений техники Apple, без SF Symbols.
- macOS 27 дополнительно унифицирует системные иконки — давление на конформность растёт; sRGB или Display P3; все размеры (16–512 pt @1x/@2x) генерирует система из одного 1024 px `.icon`.

Для foundry-desktop: 2–3 простые формы (например, наковальня/пламя как слои), фон — градиент из палитры бренда, обязательные ручные dark- и mono-варианты в Icon Composer.

---

## 6. Паттерны dev-инструментов — прямой референс для экранов

Референсы: Xcode, Console.app, Tower, Fork, Kaleidoscope, GitHub Desktop. Tower маркетирует «true Mac-native interface… strict adherence to platform design guidelines» — это буквально наша планка.

### 6.1 Макро-структура: трёхпанельный split

Канон Mac dev-инструмента:

```
┌────────────┬──────────────────┬───────────────────────────┬─────────────┐
│  Toolbar (Liquid Glass, глобальные действия, поиск, inspector-toggle)   │
├────────────┼──────────────────┼───────────────────────────┼─────────────┤
│ Sidebar    │ Content list     │ Detail                    │ Inspector   │
│ (проекты,  │ (change'и /      │ (доска / дифф /           │ (метаданные,│
│  разделы)  │  файлы ревью)    │  markdown / лог)          │  треды)     │
├────────────┼──────────────────┤                           │             │
│            │ [фильтр-бар]     │                           │             │
└────────────┴──────────────────┴───────────────────────────┴─────────────┘
```

- SwiftUI: `NavigationSplitView` (+ `.navigationSplitViewColumnWidth`), `.inspector(isPresented:)` — детали в [03-swiftui-architecture.md](03-swiftui-architecture.md).
- **Фильтр-бары — per-pane**: тонкая полоса с search-полем и scope-кнопками вверху/внизу **той панели, которую фильтруют** (паттерн навигатора Xcode), а не в тулбаре окна. Тулбар окна — только глобальное.
- Keyboard-first: ⌘1…⌘9 переключение панелей/разделов, per-pane find, ⇧⌘O quick-open по change'ам/артефактам.
- Selection в каждой панели персистентно подсвечена — так связка «список → деталь» остаётся читаемой.

### 6.2 Сайдбар проектов

- `List(selection:)` + `.listStyle(.sidebar)`; ≤2 уровня иерархии (проект → разделы); глубже — выносить в content-колонку.
- SF Symbols у пунктов; тинт — accent пользователя (см. §3.2), не фиксированный.
- Группы с disclosure-контролами и короткими лейблами; счётчики (running/pending) — Caption 1, `secondaryLabelColor`.
- Скрытие/показ: кнопка тулбара + View-меню + ⌃⌘S; не прятать по умолчанию. Метрики строк следуют системной настройке «Sidebar icon size» — **не хардкодить высоту строки**.
- Разрешить пользователю реордер проектов и секцию Favorites.
- Контент уезжает под сайдбар через `backgroundExtensionEffect()`.

### 6.3 Дифф-вьюер (ревью артефактов)

Опорные конвенции (GitHub, Kaleidoscope, Xcode; рендер — WKWebView-остров, см. [06-system-integration.md](06-system-integration.md)):

- **Два layout'а, переключаемые пользователем**: side-by-side (split) и unified (inline). Toggle — в View-меню **и** сегмент-контролом в тулбаре. Слева/сверху — предыдущая версия, справа/снизу — текущая.
- Зелёный added / красный removed — **плюс глифы +/− в гаттере** (информация не только цветом, §3.1); фон строки — низкая opacity, бейджи — полная.
- **Word-level (intraline) подсветка** внутри изменённых строк — иначе длинные markdown-абзацы нечитаемы в диффе.
- Hunk-заголовки с **расширением контекста** («Show 20 more lines»); опции whitespace-ignore и moved-line detection (фирменные фичи Kaleidoscope) — в View-меню.
- **Навигация по файлам**: дерево/список изменённых файлов с per-file счётчиками +/−, статус-глифами (A/M/D), **чекбоксами «Viewed»** с индикатором прогресса ревью; кнопки ▲▼ «следующее изменение» (⌘-стрелки) — паттерн Xcode/Kaleidoscope.
- **Комментарии**: hover над гаттером → кнопка **«+»** на строке; **drag по номерам строк = выделение диапазона**, комментарий якорится к диапазону; треды — **инлайн, свёрнутые под якорной строкой**, со статусом resolve; сводная «Conversation»-панель агрегирует треды (наш инспектор); **pending-review модель** (батч комментариев → Submit Review — единственная prominent-кнопка тулбара). Composer — markdown text view: ⌘B/⌘I через Format-меню.
- **Markdown-артефакты**: сегмент source/rendered; дифф — по source, с опцией «rich diff» по рендеру.
- Нативные штрихи, которых нет у веба: контекстное меню на hunk'е (Copy, Revert Hunk, Open File), drag файла-строки в Finder/редактор, **QuickLook (Space)** на артефакте (`.quickLookPreview`), **⌘F — инлайн find-бар вверху панели** (паттерн Safari/Xcode), не модалка.

### 6.4 Лог-вьюер (live-лог Claude)

Референс-реализации — Console.app и консоль Xcode:

- **Таблица, не text soup**: колонки time / level / source / message; message — SF Mono; колонки resizable/sortable; строка — цвет **и иконка** уровня (yellow warn, red error).
- **Бар управления**: pause/resume стрима, Clear (⌘K), кнопка «Now»/scroll-to-bottom.
- **Auto-scroll (tail)**: приостанавливается, когда пользователь проскроллил вверх, возобновляется пилюлей **«Jump to latest»** — каноничное поведение живого стрима. Эта плавающая пилюля — легитимный кандидат на кастомный `glassEffect` (§1.2).
- **Фильтрация**: search-поле с **токенами/scope** (level:, source:, текст) — паттерн NSSearchField/Console.app; сохранённые фильтры; ⌥⌘F — фокус в search-поле.
- Selection: multi-select строк, ⌘C копирует как текст; контекстное меню (Copy, Hide similar, Show info); инспектор/нижняя панель — полные детали записи (паттерн Console.app).
- **Перформанс = нативность**: виртуализированный список, лимит хранимых строк с аффордансом «older entries trimmed», ноль работы на main thread в hot path — 60 fps скролл под нагрузкой обязателен. Выбор реализации (SwiftUI `Table` vs `NSTextView`-backed панель для больших объёмов) — вердикт в [03-swiftui-architecture.md](03-swiftui-architecture.md); визуальный контракт этого раздела не зависит от реализации.

### 6.5 Канбан change'ей

Нативных образцов меньше (Things/OmniFocus/Trello-гибриды), но правила выводимы:

- Колонки — горизонтальный скролл вертикальных списков; заголовок колонки — Headline + счётчик.
- Карточки — **полная macOS selection-модель** (⌘/⇧-click multi-select, rubber-band), см. [04-macos-platform.md](04-macos-platform.md) §4.1.
- **Drag & drop между колонками с insertion indicator**; multi-drag с бейджем количества; drop undoable.
- Контекстное меню на карточке (Move to…, Assign, Open); Return — rename; ⌘N — новая карточка; double-click — детали (инспектор или окно).
- Режимы Board/List/Table — в View-меню (⌘1/⌘2/⌘3); Table-режим — многоколоночная `Table` с сортировкой (плотный обзор — то, чего нет у веб-канбанов).
- Selection — accent пользователя; тэги — семантическая палитра (§3.1); визуальный шум карточки минимален: Body-заголовок + одна строка метаданных + статус-глиф.

### 6.6 Аналитика

- **Swift Charts** — нативный фреймворк; типы — привычные (bar/line), без экзотики.
- «Headline summary» над чартом (паттерн Weather): «Merge time ↓ 18% this week» — вывод, потом график.
- Консистентные цвета/типографика между связанными чартами; прогрессивное раскрытие: маленький glanceable-чарт → развёрнутая деталь в том же стиле.
- Hover = crosshair + value readout (`.chartXSelection`), только аддитивно.
- Accessibility: labels + **Audio Graphs** (`AXChartDescriptor`).

### 6.7 Пустые состояния

Пустое состояние — тоже дизайн экрана, не заглушка:

- Нет проектов → `ContentUnavailableView` с SF Symbol, одной фразой и **prominent-действием «Add Project»** — это и есть весь онбординг (см. [04-macos-platform.md](04-macos-platform.md) §3.2).
- Пустая колонка канбана — лёгкий placeholder-контур как drop-target, не текстовая простыня.
- Нет результатов фильтра ≠ нет данных: «No changes match “wip”» + кнопка Clear Filter.
- Тон — нейтральный и краткий; без иллюстраций-маскотов, чужих Mac-инструментам.

---

## 7. Quick-reference: SwiftUI API карта

Сводка API под всё описанное в главах 04–05 (детали использования — [03-swiftui-architecture.md](03-swiftui-architecture.md)):

| Нужно | API |
|---|---|
| Сайдбар + панели | `NavigationSplitView` (+ `.navigationSplitViewColumnWidth`), `.listStyle(.sidebar)` |
| Инспектор | `.inspector(isPresented:)` |
| Меню-бар | `.commands { CommandMenu, CommandGroup }`, `.keyboardShortcut()` |
| Settings | `Settings`-сцена, `SettingsLink` |
| Menu bar extra | `MenuBarExtra("…", systemImage:) { }.menuBarExtraStyle(.menu)` |
| Окна | `WindowGroup(id:)` / `Window`, `openWindow`, `.defaultSize`, `.windowResizability` |
| Restoration | `@SceneStorage`, `@AppStorage` |
| Новый дизайн | автоматически на macOS 26 SDK; `glassEffect(_:in:)`, `backgroundExtensionEffect()`, `ScrollEdgeEffectStyle`, toolbar-placement `.prominent` |
| Таблицы | `Table` (sortable `TableColumn`, `Set`-selection), `OutlineGroup` / `List(children:)` |
| Drag & drop | `.draggable` / `.dropDestination`, `Transferable`, `FileRepresentation` (drag-to-Finder) |
| Фокус/клавиатура | `@FocusState`, `.focusable()`, `.focusedValue`, `.onKeyPress`, `.onMoveCommand` |
| Undo | `@Environment(\.undoManager)` |
| Hover/указатель | `.onHover`, `.pointerStyle`, `.help("tooltip")` |
| Символы | `Image(systemName:)`, `.symbolRenderingMode`, `.symbolEffect`, `.symbolVariant`, `imageScale(_:)` |
| Чарты | Swift Charts (`Chart`, `.chartXSelection`), `AXChartDescriptor` |
| Нотификации/Dock | `UserNotifications` + actions; `NSApp.dockTile` (бейдж) |
| Quick Look | `.quickLookPreview` |

---

## Чеклист ревью (визуальный)

Прогоняется на каждом PR, затрагивающем UI:

**Слои и стекло**
- [ ] Liquid Glass только в functional layer; в контенте (дифф, лог, карточки) стекла нет
- [ ] Нет кастомных фонов/тинтов тулбара и сайдбара; разделение — scroll edge effects
- [ ] Контент уходит под chrome (`backgroundExtensionEffect()` где применимо)
- [ ] Accent-тинт — максимум на одном prominent-действии в тулбаре
- [ ] Радиусы кастомных элементов не хардкожены и концентричны контейнеру

**Цвет**
- [ ] Ни одного хардкод-цвета: только семантические системные цвета и Color Sets с light/dark(+contrast) вариантами
- [ ] Selection — `selectedContentBackgroundColor`; в non-key окне сереет
- [ ] Accent пользователя побеждает (иконки сайдбара перекрашиваются); наш `AccentColor` — только под multicolor
- [ ] Кастомные цвета — только у данных/статусов (дифф, лог-уровни, тэги, чарты), не у chrome
- [ ] Проверено: Light, Dark, Increase Contrast, Reduce Transparency; контраст ≥4.5:1
- [ ] Информация дублируется не-цветом (глифы +/−, иконки уровней)

**Типографика и плотность**
- [ ] Только text styles (Body = 13 pt), никаких фиксированных point sizes в хроме
- [ ] SF Mono для кода/диффа/лога; никаких Light/Thin весов
- [ ] Плотные панели — `.controlSize(.small)`; контролы ≥20×20 pt, дефолт 28 pt
- [ ] Нет push-навигации там, где должен быть split/инспектор; нет видимых рядов кнопок вместо hover/контекстного меню
- [ ] Выравнивание по 8 pt-сетке; иерархия — весом/размером/цветом, не декорацией

**Символы и анимация**
- [ ] Все иконки — SF Symbols правильного варианта (outline в тулбарах/сайдбарах); scale/weight согласованы с текстом
- [ ] `symbolEffect` — только со смыслом статуса; циклы гейтятся Reduce Motion
- [ ] Кастомные символы аннотированы и имеют accessibility label; SF Symbols не используются как логотип

**Экраны-паттерны**
- [ ] Фильтры — per-pane бары, не в тулбаре окна
- [ ] Дифф: split/unified toggle в View-меню + тулбаре; гаттер с +/−; word-level highlight; «Viewed»-чекбоксы; hover-«+» для комментария имеет меню-эквивалент
- [ ] Лог: таблица с колонками, pause/clear/⌘K, tail с «Jump to latest», токен-фильтры
- [ ] Канбан: insertion indicators при drag, тэги из семантической палитры, режимы ⌘1/2/3
- [ ] Чарты: headline summary, консистентная палитра, hover-readout аддитивен

**Иконка (при изменении)**
- [ ] Слоёная, 1024 px, без пре-маскировки/своих теней; собрана в Icon Composer; dark/mono варианты ручные; ядро формы идентично во всех вариантах

---

## Источники

- [Apple Newsroom — Apple introduces a delightful and elegant new software design](https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/)
- [WWDC25 — Build a SwiftUI app with the new design (session 323)](https://developer.apple.com/videos/play/wwdc2025/323/) · [Build an AppKit app with the new design (session 310)](https://developer.apple.com/videos/play/wwdc2025/310/)
- [HIG — Materials (Liquid Glass)](https://developer.apple.com/design/human-interface-guidelines/materials) · [Color](https://developer.apple.com/design/human-interface-guidelines/color) · [Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode) · [Layout](https://developer.apple.com/design/human-interface-guidelines/layout) · [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars) · [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars) · [Split views](https://developer.apple.com/design/human-interface-guidelines/split-views)
- [HIG — Typography](https://developer.apple.com/design/human-interface-guidelines/typography) · [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [HIG — SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols) · [App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- [HIG — Charting data](https://developer.apple.com/design/human-interface-guidelines/charting-data) · [Charts](https://developer.apple.com/design/human-interface-guidelines/charts) · [Search fields](https://developer.apple.com/design/human-interface-guidelines/search-fields) · [Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables)
- macOS 27 «Golden Gate»: [9to5Mac](https://9to5mac.com/2026/06/08/apple-announces-macos-golden-gate-27/) · [TechRadar](https://www.techradar.com/computing/mac-os/macos-27-golden-gate-announced-at-wwdc-2026-heres-everything-you-need-to-know) · [Tom's Guide](https://www.tomsguide.com/computing/macos/macos-27-set-to-launch-with-three-huge-new-features-and-no-apples-not-killing-liquid-glass-at-wwdc-2026) · [wccftech](https://wccftech.com/macos-27-golden-gate-preview-announced-at-wwdc-2026/amp/)
- macOS Tahoe: [Wikipedia](https://en.wikipedia.org/wiki/MacOS_Tahoe) · [Six Colors review](https://sixcolors.com/post/2025/09/macos-26-tahoe-review-power-under-glass/) · [Macworld](https://www.macworld.com/article/2862474/macos-tahoe-prioritizes-productivity-over-liquid-glass.html)
- [ControlSize (SwiftUI docs)](https://developer.apple.com/documentation/swiftui/view/controlsize(_:)) · [Fleeting Pixels — Control Sizing in SwiftUI](https://fleetingpixels.com/articles/2022/control-size/)
- Dev-инструменты: [Fork](https://git-fork.com/) · [Tower vs Fork](https://www.git-tower.com/compare/fork) · [Review Board — Reviewing diffs](https://www.reviewboard.org/docs/manual/latest/users/reviews/reviewing-diffs/) · [SmartBear Collaborator — Diff viewer](https://support.smartbear.com/collaborator/docs/reference/ui/diff-viewer.html) · [difit](https://dev.to/unhappychoice/difit-preview-github-like-diffs-locally-before-you-push-37gc) · [Plannotator — Local diff review](https://plannotator.ai/blog/local-diff-review-for-coding-agents/)
- [AbilityNet — Tahoe Text Size](https://api.abilitynet.org.uk/how-to-make-the-text-larger-on-your-apple-mac-computer-using-the-text-size-options-in-macos-26-tahoe)
