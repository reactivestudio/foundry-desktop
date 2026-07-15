# 04 · macOS: поведение нативного приложения

> Серия practices · [оглавление](README.md)

Эта глава — про **поведение**: что должно происходить при клике, шорткате, drag'е и перезапуске, чтобы foundry-desktop ощущался родным Mac-приложением, а не Electron-подделкой или iPad-портом. Визуальный слой (Liquid Glass, типографика, паттерны экранов) — в [05-ui-design.md](05-ui-design.md). Код сцен, окон и state-менеджмента — в [03-swiftui-architecture.md](03-swiftui-architecture.md).

Таргет: сборка против **macOS 26 SDK (Xcode 26)**, **deployment target — macOS 15 Sequoia**. Поведенческие конвенции главы от версии macOS не зависят; редкие 15+-пометки (`.pointerStyle`) уже в пределах таргета.

---

## 1. Канонический чеклист native feel

HIG «Designing for macOS» формулирует приоритеты платформы прямо: плотность большого дисплея с минимумом модальности и вложенности; свободное управление окнами; **полный меню-бар со ВСЕМИ командами**; точный указатель; **шорткаты везде и keyboard-only режимы работы**; персонализация (кастомизируемые тулбары, системный accent color).

Развёрнутый чеклист — то, по чему пользователь Mac бессознательно оценивает «родное / не родное»:

| # | Требование | Почему | Где в foundry-desktop |
|---|---|---|---|
| 1 | **Полный меню-бар**: каждая команда приложения есть в меню, даже если доступна в UI | Меню — карта возможностей приложения; «исключение команд из меню-бара делает их труднонаходимыми для всех» (HIG) | «Move Card», «Approve Review», «Clear Log» — всё в меню, не только на кнопках |
| 2 | **Шорткаты + Full Keyboard Access**: стандартные ⌘-шорткаты работают, кастомные — у частых команд, Tab/стрелки ходят по всему UI с видимым focus ring | Power-юзеры dev-инструментов судят приложение в первую очередь по клавиатуре | Ревью и канбан целиком проходимы без мыши |
| 3 | **Правильные окна**: main/key/inactive состояния, resize с разумными min-размерами, несколько окон где полезно, Zoom/Minimize/Full Screen — системные, никакого кастомного chrome | Кастомный title bar — тел №1 у Electron-приложений | Ревью открывается в отдельном окне; лог отцепляется |
| 4 | **State restoration**: после перезапуска — точное прежнее состояние: окна, позиции, выбранный проект, скролл | На macOS нет launch screens — приложение обязано «продолжить с того же места» (HIG Launching) | Выбранный проект в сайдбаре, открытая review-сессия, позиция в логе |
| 5 | **Drag & drop везде**: между панелями, наружу в Finder, из неактивных окон, multi-select с бейджем количества, Option = copy | «People try it everywhere» (HIG) | Карточка → колонка; артефакт → Finder как `.md`; лог-строки → текст |
| 6 | **Контекстные меню на всём выделяемом**: Control-click/right-click на проекте, карточке, файле, hunk'е диффа, строке лога | Правый клик — базовый рефлекс десктопа | См. правила в §2.2 |
| 7 | **Dock + Services**: Dock-меню с окнами и 1–3 действиями, доступными даже когда приложение не frontmost; бейдж только для «непрочитанного» | Интеграция с системой = ощущение «части ОС» | Dock: «New Change», «Pause All Runs»; бейдж = pending reviews |
| 8 | **Уважение системных настроек**: accent color пользователя, Dark Mode (без in-app переключателя!), Reduce Motion, Increase Contrast, Reduce Transparency, размер иконок сайдбара, Text Size (Tahoe) | «Люди могут решить, что приложение сломано», если оно игнорирует системную тему (HIG Dark Mode) | Никаких хардкод-цветов selection; см. 05 §3 |
| 9 | **Undo/redo везде, где мутируются данные** + autosave | Mac-приложение не спрашивает «сохранить?» и не боится ошибок пользователя | Перемещение карточек, комментарии, правки — всё undoable |
| 10 | **Settings (⌘,)**, тултипы на toolbar-иконках, Help-меню, правильные формы курсора (I-beam, resize на разделителях) | Сотни мелких деталей, из которых складывается «finished app» | — |
| 11 | **Плотность**: больше контента, меньше вложенности и модальности | Главный тел «iPad-порта» — огромные контролы и navigation stack там, где Mac использует панели | Таблицы + инспектор вместо push-навигации |

Правило серии: пункты 1–11 — не «nice to have», а **definition of done** каждого экрана.

---

## 2. Меню-бар

### 2.1 Стандартная структура и порядок

Порядок меню фиксирован: `Apple | Foundry | File | Edit | Format | View | [кастомные] | Window | Help`.

| Меню | Обязательные пункты | Заметки для foundry-desktop |
|---|---|---|
| **Foundry** (App) | About Foundry → Settings… (⌘,) → Services → Hide Foundry (⌘H) / Hide Others (⌥⌘H) / Show All → Quit Foundry (⌘Q) | App-level конфигурация — в одной группе с Settings. Option на Quit → «Quit and Keep Windows» |
| **File** | New Change (⌘N), New Project (⇧⌘N), Open Recent (имена, не пути; Clear Menu), Close (⌘W; Option → Close All), Export As… | Именуй тип объекта: «New Change», не «New Item». Save (⌘S) оставляем даже при autosave — для явного commit-действия. Duplicate предпочтительнее Save As |
| **Edit** | Undo/Redo (⌘Z/⇧⌘Z, с именем операции), Cut/Copy/Paste, Paste and Match Style (⌥⇧⌘V), Delete, Select All (⌘A), Find-подменю (⌘F, ⌘G/⇧⌘G, ⌘E, ⌘J), Spelling & Grammar | Критично для composer'а комментариев: используем системные text views — и почти всё это бесплатно, включая системные Dictation / Emoji & Symbols |
| **Format** | Bold/Italic и минимум для markdown | Только если есть user-visible форматирование — у нас markdown-комментарии, значит минимальный Format оправдан |
| **View** | Show/Hide Toolbar (⌥⌘T), Customize Toolbar…, Show/Hide Sidebar (⌃⌘S), Enter Full Screen (⌃⌘F), режимы вида: as Board (⌘1) / as List (⌘2) / as Table (⌘3), Unified/Side-by-Side diff, ⌘+/⌘−/⌘0 зум контента | Ярлыки-переключатели меняют текст («Show Sidebar» ↔ «Hide Sidebar»), а не дизейблятся. View — дом всех view options; в Settings им не место |
| **Кастомные** | **Project**, **Change**, **Review**, **Logs** — между View и Window, от общего к частному | Каждая доменная команда живёт здесь: Move to Column, Assign, Approve, Request Changes, Mark Viewed, Pause Stream, Clear Log (⌘K)… Это же делает их доступными через Help-поиск команд |
| **Window** | Minimize (⌘M), Zoom, Bring All to Front, алфавитный список открытых окон | Обязателен даже для «однооконного» приложения. Панели в списке окон не показываются |
| **Help** | Foundry Help (⌘?) | Help Book даёт бесплатный поиск по командам меню |

### 2.2 Правила поведения пунктов

- **В меню-баре недоступные пункты дизейблятся (dim), никогда не скрываются.** Меню обучает возможностям приложения. В **контекстных меню — наоборот: неприменимое скрывается** (кроме Cut/Copy/Paste, которые дизейблятся).
- Заголовки меню — одно слово; пункты — Title Case, без артиклей; многоточие `…`, если нужен дополнительный ввод; чекмарки — для действующих атрибутов.
- Иконки (SF Symbols) в пунктах меню теперь санкционированы HIG (ревизия 2025–2026): системные символы для частых действий; внутри группы — либо у всех пунктов, либо ни у одного.
- Option-альтернативы (dynamic items) — только как power-шорткат, один модификатор, никогда не единственный путь к функции.
- Подменю: один уровень, ≤5 пунктов, экономно.
- В контекстных меню шорткаты не отображаются; ≤3 группы разделителей.

### 2.3 SwiftUI Commands API

Меню строится декларативно на сцене (детали архитектуры сцен — [03-swiftui-architecture.md](03-swiftui-architecture.md)):

```swift
@main
struct FoundryApp: App {
    var body: some Scene {
        WindowGroup(id: "main") { MainWindow() }
            .commands {
                // Кастомное меню — автоматически встаёт между View и Window
                CommandMenu("Change") {
                    Button("Move to In Progress") { moveFocusedCard(.inProgress) }
                        .keyboardShortcut("2", modifiers: [.command, .option])
                        .disabled(focusedCard == nil)   // dim, не скрываем
                    Divider()
                    Button("Assign to Agent…") { … }
                }
                // Замена стандартного New Item
                CommandGroup(replacing: .newItem) {
                    Button("New Change") { newChange() }.keyboardShortcut("n")
                    Button("New Project") { newProject() }
                        .keyboardShortcut("n", modifiers: [.command, .shift])
                }
                CommandGroup(after: .toolbar) {
                    Picker("Diff Layout", selection: $diffLayout) {
                        Text("Unified").tag(DiffLayout.unified)
                        Text("Side by Side").tag(DiffLayout.sideBySide)
                    }
                }
            }

        Settings { SettingsView() }   // App menu → Settings… (⌘,) — бесплатно
    }
}
```

Роутинг команд в **сфокусированное** окно/выделение — через `@FocusedValue` / `@FocusedBinding`:

```swift
// Во view с выделением:
.focusedSceneValue(\.selectedCards, $selection)

// В Commands:
@FocusedBinding(\.selectedCards) var selection
Button("Delete Change") { delete(selection) }
    .disabled(selection?.isEmpty ?? true)
```

```swift
// ПЛОХО: команда дергает синглтон-стор — работает не на том окне,
// не дизейблится без выделения, ломает multi-window
Button("Approve") { AppStore.shared.approveCurrentReview() }

// ХОРОШО: команда идёт через focused value активного окна
@FocusedValue(\.activeReview) var review
Button("Approve") { review?.approve() }.disabled(review == nil)
```

### 2.4 Конвенции ⌘-шорткатов

Правила выбора модификаторов для кастомных команд:

- **⌘** — основной; **⇧⌘** — парная/дополняющая вариация; **⌥** — экономно, для power-фич; **⌃ — никогда** (зарезервирован системой). Порядок отображения модификаторов: ⌃ ⌥ ⇧ ⌘.
- **Никогда не переназначай стандартные шорткаты.** Исключение — стандарт, бессмысленный в приложении (⌘I «Get Info» можно занять, если нет text-editing Italic… но у нас есть markdown, значит ⌘I = Italic).
- Не «⇧ + строчный символ» — используй верхний символ: ⌘? , не ⇧⌘/.

Стандартные шорткаты, которые foundry-desktop обязан честно поддерживать:

| Шорткат | Команда | Где у нас |
|---|---|---|
| ⌘, | Settings | Settings scene |
| ⌘N / ⇧⌘N | New Change / New Project | File |
| ⌘W / ⌥⌘W | Close / Close All | окна ревью и лога |
| ⌘S | Save | явный commit черновика ревью |
| ⌘F | Find | инлайн find-бар в диффе/логе, не модалка |
| ⌘G / ⇧⌘G | Find Next / Previous | навигация по совпадениям |
| ⌘E | Use Selection for Find | дифф, лог |
| ⌘Z / ⇧⌘Z | Undo / Redo | все мутации |
| ⌘A / ⇧⌘A | Select All / Deselect All | карточки, строки лога |
| ⌘C/X/V | клипборд | вкл. copy лог-строк как текст |
| ⌘K | Clear | очистка лог-вью (конвенция консолей) |
| ⌘+ / ⌘− / ⌘0 | зум контента / Actual Size | дифф, markdown, лог |
| ⌘1/⌘2/⌘3 | режимы вида | Board / List / Table |
| ⌃⌘S | Show/Hide Sidebar | View |
| ⌃⌘F | Enter Full Screen | View |
| ⌘M / ⌘Q / ⌘H | Minimize / Quit / Hide | системные |
| ⌘` | цикл по окнам приложения | бесплатно с системными окнами |
| Esc / ⌘. | Cancel | закрыть popover, отменить inline-edit, остановить прогресс |
| ⌘? | Help | Help menu |

Локализацию и зеркалирование (RTL) шорткатов делает система — не вешай не-⌘ модификаторы на неалфавитные клавиши.

---

## 3. Окна

### 3.1 Анатомия и состояния

- Окно macOS = **frame** (title bar/toolbar + опциональный bottom bar) + **body**. Перетаскивание за frame — move, за края — resize.
- Три состояния: **main** (переднее окно приложения), **key** (принимает ввод — цветные traffic lights), **inactive** (серые контролы, материалы отключены). Системные компоненты отрабатывают это сами; **кастомные компоненты обязаны зеркалить эти состояния** — прежде всего цвет selection (см. §4.1).
- **Не клади критичные действия в нижнюю кромку окна**: «люди часто сдвигают окно так, что нижний край за экраном» (HIG). Bottom bar — только для статусной строки («128 changes, 3 running»). Дополнительная информация — в инспектор справа, не вниз.
- **Никакого кастомного window chrome.** Titlebar, traffic lights, поведение double-click по заголовку (zoom/minimize по системной настройке) — системные.
- Заголовок каждого окна — осмысленный и уникальный (имя проекта / change'а), никогда не имя приложения: окна должны различаться в Window-меню.
- Full screen — только системный механизм (зелёная кнопка, View → Enter Full Screen, ⌃⌘F).
- Ноутбуки с вырезом: не размещать контент в зоне camera housing (`NSPrefersDisplaySafeAreaCompatibilityMode`).

Мульти-окно для foundry-desktop: главное окно (сайдбар + канбан/список), **ревью в отдельном окне** (хочется рядом с редактором), **отцепляемый лог** — auxiliary window с close-аффордансом. SwiftUI: `WindowGroup(id:)` + `openWindow` (код — в [03-swiftui-architecture.md](03-swiftui-architecture.md)).

### 3.2 Restoration: перезапуск = продолжение

⚠️ На macOS **нет launch screens**. Ожидание платформы: быстрый запуск и **точное** восстановление прежнего состояния — окна на тех же местах, тот же выбранный проект, тот же скролл.

Восстанавливаем гранулярно:

| Что | Механизм |
|---|---|
| Позиции/размеры окон, открытые окна | системное window restoration (не отключать) |
| Выбранный проект в сайдбаре, активный change | `@SceneStorage` (per-window) |
| Режим вида (Board/List/Table), layout диффа | `@SceneStorage` / `@AppStorage` |
| Позиция скролла в длинном логе/диффе | `@SceneStorage` + ручной restore |
| Черновики комментариев ревью | persist на диск немедленно (autosave-постура, §4.5) |
| Раскрытость групп в outline, последняя pane Settings | системно / `@AppStorage` |

```swift
// ПЛОХО: каждый запуск — «свежий» экран с welcome-заглушкой
// ХОРОШО:
struct MainWindow: View {
    @SceneStorage("selectedProjectID") private var selectedProjectID: String?
    @SceneStorage("boardViewMode") private var viewMode: ViewMode = .board
    …
}
```

Онбординг: без wizard'ов. Пустое состояние «Add your first project» с prominent-действием + контекстные подсказки (TipKit) — быстрее, опциональнее и нативнее многостраничного welcome.

### 3.3 Sheets vs Windows vs Popovers vs Alerts vs Panels

Главная таблица главы — «когда что»:

| Поверхность | Когда | Пример в foundry-desktop | Анти-пример |
|---|---|---|---|
| **Sheet** | Модальная, scoped-задача, привязанная к конкретному окну; один sheet за раз; Cancel + Done | «New Project» (имя + путь), настройка экспорта | Целый flow ревью в sheet — «app within the app», запрещено HIG Modality |
| **Window** | Независимая или долгая задача; всё, что хочется видеть рядом с другим | Окно ревью, отцеплённый лог | Диалог из двух полей отдельным окном |
| **Popover** | Транзиентный, с якорем-стрелкой к вызвавшему контролу, немного контента; авто-закрытие по клику вовне (с сохранением введённого!) | Фильтр колонки канбана, quick-actions карточки, date picker | Warning в popover; popover из popover |
| **Alert** | Только критичное. Никогда: чисто информационные сообщения, при запуске, подтверждение undoable-действий | «Delete the project “Foundry API”? This cannot be undone.» | «Card moved successfully» алертом; «Delete comment?» — комментарий undoable, алерт не нужен |
| **Panel** | Плавающая утилита при активном окне, трекает selection; не в списке Window-меню, без minimize | Detached-фильтр лога (detachable popover → panel) | HUD-панель вне media-контекста |

Правила alert'ов: заголовок описывает ситуацию («Delete the artifact “RFC-12”?», не «Error»); кнопки — глаголы («Delete», «Cancel»); default — trailing; Cancel обязателен при деструктиве; destructive-стиль — только когда действие не было заявленным намерением пользователя; Esc/⌘. = Cancel; suppression-чекбокс «Don't ask again» для повторяющихся подтверждений.

Правила модальности: модальность только с явной пользой; коротко и линейно; очевидный dismiss; подтверждение перед dismiss, теряющим данные; одна модалка за раз.

### 3.4 Тулбар: поведение (регионы, кастомизация, overflow)

Визуальные правила тулбара — в [05-ui-design.md](05-ui-design.md); здесь — поведенческий контракт (HIG Toolbars, редакция эпохи Liquid Glass):

- Три региона размещения:
  - **Leading**: back/forward, sidebar-toggle, затем заголовок (≤15 символов; может нести document-меню: Duplicate/Rename/Move/Export). Leading-элементы пользователем **не** кастомизируются.
  - **Center**: частые действия; **пользователь может добавлять/убирать/переставлять**; при сужении окна элементы **автоматически** уходят в системное overflow-меню — свой overflow не строить никогда.
  - **Trailing**: всегда-видимые важные элементы, **inspector-toggle**, search-поле, меню More (…), единственное `.prominent`-действие.
- **Кастомизация тулбара обязательна** для long-session productivity-приложений (HIG прямо рекомендует для macOS): SwiftUI `.toolbar(id:)` — каждому item свой стабильный id; пункт «Customize Toolbar…» в View-меню появляется системно.
- ≤3 групп элементов; у каждой иконки — `.help()` тултип.

```swift
.toolbar(id: "review") {
    ToolbarItem(id: "layout", placement: .secondaryAction) {
        Picker("Layout", selection: $diffLayout) { … }.pickerStyle(.segmented)
    }
    ToolbarItem(id: "submit", placement: .primaryAction) {
        Button("Submit Review") { submit() }   // единственный prominent
    }
}
```

### 3.5 Settings window (⌘,)

- Открывается из App-меню → Settings… (⌘,). SwiftUI: `Settings`-сцена + `TabView` с toolbar-style панами.
- Конвенции окна: тулбар кнопок-панов (не кастомизируемый, активная пана подсвечена); **заголовок окна = имя текущей паны**; minimize/zoom задизейблены; окно ресайзится под пану; **при повторном открытии — последняя просмотренная пана**.
- Дисциплина содержимого: настроек мало, дефолты хороши настолько, что большинство пользователей окно не открывает. View options (режим борда, layout диффа, шрифт лога) живут в **View-меню**, не в Settings. Никогда не дублировать системные настройки (тема, accent color, поведение скролла).
- Уместные Settings у нас: пути/учётки агентов, поведение нотификаций, «Show menu bar icon», лимит хранимых лог-строк.

### 3.6 Инспекторы, панели, split views

- **Split view** — рабочая лошадь: 2–3 панели (наш каркас — sidebar → список → detail, см. [05-ui-design.md](05-ui-design.md) §6). Правила: **персистентная подсветка selection в каждой панели**, управляющей детали; тонкий (1 pt) разделитель; min/max ширины, чтобы divider не «терялся»; панели скрываемы **с несколькими путями возврата** (кнопка тулбара + пункт View-меню + шорткат); drag & drop между панелями прямо поощряется HIG.
- **Inspector** — детали **текущего выделения**, авто-обновляется при смене selection; trailing-панель. SwiftUI `.inspector(isPresented:)` (macOS 14+) даёт правильный материал и интеграцию с тулбаром. Наш дом для: метаданных карточки, тредов комментариев ревью, деталей run'а. Toggle — в trailing-регионе тулбара. Info window ≠ inspector: Info — заморожен на объекте и является обычным окном.
- **Panel** — плавает над окнами, титулуется существительным, становится key только при необходимости, прячется при деактивации приложения, без minimize; простые прямые контролы. Detachable popover (потянуть) → panel — приятный паттерн для постоянного фильтра.

---

## 4. Взаимодействие

### 4.1 Selection-модель

Полная десктопная модель — во всех коллекциях (проекты, карточки, файлы ревью, строки лога):

- Click = select; **⌘-click = toggle элемента (discontiguous); ⇧-click = расширение диапазона**; drag по пустому месту = rubber-band; ⌘A / ⇧⌘A = select/deselect all.
- `List(selection: Binding<Set<ID>>)` и `Table(selection:)` дают это бесплатно — **не пиши свою selection-модель на onTapGesture**.
- Навигационные списки подсвечивают selection **персистентно** (accent-фон, белый текст).
- **Non-key окно**: selection сереет (`unemphasizedSelectedContentBackgroundColor`). Бесплатно с системными компонентами; кастомные ячейки обязаны это повторить.
- **Background selection**: неактивное окно сохраняет серое выделение, и его элементы **можно перетаскивать, не активируя окно**.

```swift
// ПЛОХО: одиночный tap-хендлер, свой @State выделенной карточки,
// нет ⌘/⇧-click, нет rubber-band, selection не сереет в non-key
.onTapGesture { selected = card.id }

// ХОРОШО:
@State private var selection = Set<Card.ID>()
Table(cards, selection: $selection, sortOrder: $sortOrder) { … }
```

### 4.2 Double-click и inline-редактирование

- Double-click = открыть/активировать: карточка → окно/инспектор change'а, файл в ревью → дифф.
- Single-click по уже выделенному редактируемому полю (или Return на выделенном) = **inline rename** — имя проекта, заголовок карточки.
- Double-click по title bar — системный zoom/minimize, не перехватывать.

### 4.3 Hover — десктопная суперсила

- Hover раскрывает вторичные контролы: кнопки действий на строке, quick-actions карточки, **«+» в гаттере диффа для комментария** (паттерн GitHub).
- Тултипы: `.help("Approve review")` на каждой иконке тулбара.
- Форма указателя сообщает интерактивность: I-beam над текстом, pointing hand над ссылками, resize-стрелки на разделителях. SwiftUI: `.onHover`, `.pointerStyle(_:)` (macOS 15+).
- **Hover не может быть единственным путём** к действию (клавиатурный паритет: у «+» в гаттере есть эквивалент «Comment on Line» в меню Review) и hover-аннотации (значения на графике) — только аддитивны.

### 4.4 Фокус и Full Keyboard Access

- Focus ring (`keyboardFocusIndicatorColor`) на сфокусированном контроле: **кольцо** для text/search-полей, **подсветка строки целиком** для списков/таблиц.
- Tab/⇧Tab — между контролами и группами; стрелки — внутри списков/таблиц; Space — toggle; Return — default-действие; Esc/⌘. — cancel.
- **Full Keyboard Access (⌃F1) обязан достигать всего**: канбан (стрелки между карточками/колонками, Space — открыть), гаттер диффа, строки лога.
- Не перемещай фокус программно — кроме случая, когда сфокусированный элемент исчез.
- SwiftUI: `@FocusState`, `.focusable()`, `.focusedValue`, `defaultFocus`, `.onKeyPress`, `.onMoveCommand`.

### 4.5 Undo/redo и autosave

- ⌘Z/⇧⌘Z из Edit-меню, **глубина не ограничена**, и — ключевая конвенция — **операция именуется**: «Undo Move Card to Done», «Undo Delete Comment», не безликое «Undo».
- **Показывай результат undo**: скролль к восстановленной карточке/комментарию.
- Батч связанных микро-правок в одну операцию (drag пяти карточек = один undo).
- SwiftUI: `@Environment(\.undoManager)`:

```swift
func move(_ cards: Set<Card.ID>, to column: Column) {
    let previous = snapshotPositions(of: cards)
    board.move(cards, to: column)
    undoManager?.registerUndo(withTarget: board) { board in
        board.restore(previous)
    }
    undoManager?.setActionName("Move Card to \(column.title)")   // ← имя!
}
```

- **Autosave — постура по умолчанию**: «сохраняй изменения периодически, чтобы люди не выбирали File → Save» (HIG). Черновики комментариев ревью переживают перезапуск (сцепка с restoration, §3.2).
- Следствие: **деструктивные-но-undoable действия не получают confirmation alert.** Удаление карточки = мгновенно + undo, а не «Are you sure?».

### 4.6 Таблицы и outline views

Поведенческий контракт `Table` / outline (важен для Table-режима канбана, списка файлов ревью, лог-таблицы):

- **Заголовки колонок сортируют**: клик — сортировка, повторный клик — реверс (`TableColumn` + `sortOrder`); колонки **resizable**; заголовки — описательные существительные.
- Путеподобный текст (файлы артефактов) — **middle-ellipsis** truncation, чтобы имя файла оставалось видно.
- Outline: иерархию несёт только первая колонка; **Option-click по disclosure-треугольнику раскрывает рекурсивно**; **состояние раскрытости персистится между запусками** (сцепка с restoration §3.2); для длинных outline конвенционален search-фильтр в панели.
- Row-editing: single-click-to-edit в ячейках, где это осмысленно (заголовок change'а в Table-режиме); reorder строк — где порядок имеет смысл (проекты в сайдбаре).

### 4.7 Drag & drop

Полный инженерный список:

- **Между панелями**: карточка между колонками канбана (insertion indicator), файл ревью в другую группу.
- **Наружу в Finder**: артефакт → `.md`-файл (`Transferable` + `FileRepresentation` — file promise), лог-выделение → текстовый файл.
- **Multi-select drag** с бейджем количества у указателя; бейдж обновляется у destination.
- **Option = copy** — проверяется **в момент drop**, не в момент начала drag'а; указатель меняется на drag-copy / not-allowed.
- Несколько фиделити на pasteboard: нативный объект → file promise → plain text/markdown — чтобы drop работал и в наш канбан, и в Finder, и в текстовый редактор.
- Drag из **неактивных окон** (background selection, §4.1), spring-loading, scroll-on-drag у краёв, placeholder-строка + прогресс для медленных переносов, подсветка drop-target, **drop обязан быть undoable**.

```swift
// Артефакт можно утащить в Finder как файл
extension Artifact: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { artifact in
            SentTransferredFile(try artifact.writeMarkdownToTemp())
        }
        ProxyRepresentation(exporting: \.markdown)   // fallback: plain text
    }
}
```

---

## 5. Accessibility

### 5.1 VoiceOver

- Каждый смысловой view — `accessibilityLabel`; значения — `accessibilityValue`; кастомные символы — alt-текст.
- Композитные строки (карточка: заголовок + статус + агент) — `accessibilityElement(children: .combine)`, чтобы VoiceOver читал одну сущность, а не четыре лейбла.
- Чарты аналитики — accessibility descriptions + **Audio Graphs** (`AXChartDescriptor`).
- Заголовки секций — traits `.isHeader` для rotor-навигации.
- Тест — Accessibility Inspector (Xcode) + живой прогон VoiceOver (⌘F5) по канбану и ревью.
- ⚠️ Не применимо: **Accessibility Nutrition Labels** (с 2025) — требование страницы App Store, а мы вне MAS навсегда ([глава 06 §7](06-system-integration.md), [глава 08 §4](08-project-tooling-distribution.md)). Практики доступности выше действуют независимо от канала дистрибуции.

### 5.2 Keyboard-only

Полное покрытие из §4.4 — это и есть accessibility-требование: всё достижимо и активируемо с клавиатуры, фокус виден, системные accessibility-шорткаты не переопределены.

### 5.3 Текст и масштабирование

⚠️ **Dynamic Type на macOS НЕ существует** — HIG говорит это прямо. Но:

- **Tahoe добавил Accessibility Text Size** (System Settings → Accessibility → Display → Text size, глобально и per-app). Чтобы его наследовать — **только text styles** (`.body`, `.callout`…), никаких фиксированных point sizes в UI-хроме.
- HIG Accessibility по-прежнему требует давать тексту увеличиваться **до 200%**.
- Практика foundry-desktop: **⌘+ / ⌘− / ⌘0 — зум контента** в дифф-, markdown- и лог-вью (независимо от UI-хрома). Это конвенция всех редакторов/просмотрщиков на Mac.

### 5.4 Контраст, прозрачность, движение

- WCAG AA кодифицирован HIG: текст ≤17 pt — **4.5:1**; ≥18 pt или bold — 3:1.
- **Increase Contrast**: системные цвета адаптируются сами; кастомные цвета (тэги канбана, лог-уровни) — high-contrast варианты в Color Set.
- **Reduce Transparency**: стекло становится непрозрачным — не полагаться на просвечивающий контент как на информацию.
- **Reduce Motion** (`@Environment(\.accessibilityReduceMotion)`): движение/зум → fade; без z-axis; глушим циклические `symbolEffect` (пульсация «streaming»-глифа).
- **Информация — не только цветом**: в диффе — глифы +/− в гаттере, не только красный/зелёный фон; в логе — иконка+текст уровня, не только тинт строки.
- Хит-таргеты: минимум 20×20 pt, дефолт 28×28 pt (см. плотность в [05-ui-design.md](05-ui-design.md) §2).

---

## 6. Нотификации, Dock, MenuBarExtra

### 6.1 Notifications

- **Сначала разрешение** (`UNUserNotificationCenter`), запрошенное **в контексте**: пользователь запускает длинный agent run → «Notify when finished?». Не при старте приложения.
- Контент: короткий заголовок, sentence-case тело, **без имени/иконки приложения в тексте** (система добавит), generic-плейсхолдер для скрытых превью.
- **Frontmost-правило**: не нотифицируй о том, что и так на экране — обнови UI тихо (инкремент бейджа, новая строка). Для live-лог инструмента это ключевое: run завершился, окно лога открыто → никакой нотификации.
- Действия: до 4 кнопок с SF Symbols («Open Review», «Mark Done»); **не делать кнопку «Open app»** — тап по нотификации уже открывает; предпочитать недеструктивные.
- **Ошибки — это alert или inline-UI, никогда не notification.**

### 6.2 Dock

- **Dock-меню** (Control-click по иконке): список окон + 1–3 high-value действий, работающих даже когда приложение не frontmost: «New Change», «Pause All Runs». Всё дублируется в меню-баре.
- **Бейдж** — только «непрочитанные»-счётчики (pending reviews). Поддерживать актуальным; обнуление чистит Notification Center; никаких декоративных бейджей. `NSApp.dockTile`.
- Прогресс долгих операций на иконке Dock — устоявшаяся конвенция сообщества (как прогресс загрузки), уместно для длинного agent run.

### 6.3 MenuBarExtra

- Высота меню-бара — 24 pt; иконка — **template/symbol image** (чёрный + прозрачный), система перекрашивает под light/dark/selected. ⚠️ Цветная иконка в меню-баре — классический тел не-нативного приложения.
- Клик → **меню, не окно**: `MenuBarExtra("Foundry", systemImage: "hammer") { … }.menuBarExtraStyle(.menu)`. `.window`-стиль — только если контент реально не помещается в меню.
- **Пользователь управляет присутствием**: Settings-toggle «Show menu bar icon». Система прячет extras при нехватке места — **никогда не делать extra единственным путём** к функции; всё дублируется в приложении и Dock-меню.
- Наш кейс — идеальный: глиф статуса агентов/пайплайна + быстрые действия (Pause Runs, Open Board, последняя активность) — как CI-статус-приложения.

---

## Чеклист ревью (поведенческий)

Прогоняется на каждом PR, добавляющем команду/экран/взаимодействие:

**Меню и клавиатура**
- [ ] У каждой новой команды есть пункт в меню-баре (в правильном меню, в правильной группе)
- [ ] У частой команды есть ⌘-шорткат по конвенциям §2.4; стандартные шорткаты не переназначены
- [ ] Пункты меню дизейблятся (не исчезают), когда неприменимы; ярлыки-переключатели меняют текст
- [ ] Команда достижима через Full Keyboard Access: Tab/стрелки доводят, Return/Space активирует, фокус виден
- [ ] Esc/⌘. отменяет транзиентный UI, который добавил PR
- [ ] Команда роутится через `@FocusedValue` в активное окно, а не в глобальный стор

**Окна и состояние**
- [ ] Новый экран восстанавливается после перезапуска (selection, режим, скролл — `@SceneStorage`)
- [ ] Выбрана правильная поверхность по таблице §3.3 (sheet/window/popover/alert/panel) — и это можно защитить
- [ ] Alert (если есть) — только для критичного; undoable-действия без подтверждений
- [ ] Кастомные ячейки корректно выглядят в non-key окне (серое selection)
- [ ] Нет критичных контролов у нижней кромки окна

**Мутации**
- [ ] Каждая мутация undoable, операция именована («Undo Move Card…»), связанные правки сбатчены
- [ ] Данные автосохраняются; черновики переживают перезапуск
- [ ] Drop-операции undoable; Option=copy проверяется при drop

**Взаимодействие**
- [ ] Selection: ⌘-click, ⇧-click, rubber-band, ⌘A работают (через `List`/`Table` selection, не самописно)
- [ ] Контекстное меню на каждом новом выделяемом объекте; его пункты есть и в меню-баре
- [ ] Hover-действия имеют клавиатурный/меню-эквивалент; на toolbar-иконках `.help()`
- [ ] Drag & drop: между панелями, в Finder где осмысленно, multi-select с бейджем

**Accessibility**
- [ ] VoiceOver: labels/values на новых элементах, композитные строки — `.combine`, прогон Accessibility Inspector
- [ ] Только text styles (не фиксированные размеры); контент-зум ⌘+/− работает в новых вью контента
- [ ] Информация передаётся не только цветом; Reduce Motion гейтит новые анимации
- [ ] Контраст: 4.5:1 для текста ≤17 pt (проверить кастомные цвета в dark mode + Increase Contrast)

**Система**
- [ ] Нотификации не стреляют по frontmost-контенту; ошибки не в нотификациях
- [ ] Новая функция MenuBarExtra/Dock-меню продублирована в главном UI

---

## Источники

- [HIG — Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos)
- [HIG — The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar)
- [HIG — Menus](https://developer.apple.com/design/human-interface-guidelines/menus)
- [HIG — Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards) · [Apple Support 102650 — Mac keyboard shortcuts](https://support.apple.com/en-us/102650)
- [HIG — Windows](https://developer.apple.com/design/human-interface-guidelines/windows) · [Going full screen](https://developer.apple.com/design/human-interface-guidelines/going-full-screen)
- [HIG — Launching](https://developer.apple.com/design/human-interface-guidelines/launching) · [Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)
- [HIG — Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets) · [Popovers](https://developer.apple.com/design/human-interface-guidelines/popovers) · [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts) · [Panels](https://developer.apple.com/design/human-interface-guidelines/panels) · [Modality](https://developer.apple.com/design/human-interface-guidelines/modality)
- [HIG — Settings](https://developer.apple.com/design/human-interface-guidelines/settings)
- [HIG — Split views](https://developer.apple.com/design/human-interface-guidelines/split-views) · [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)
- [HIG — Focus and selection](https://developer.apple.com/design/human-interface-guidelines/focus-and-selection) · [Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables) · [Outline views](https://developer.apple.com/design/human-interface-guidelines/outline-views)
- [HIG — Undo and redo](https://developer.apple.com/design/human-interface-guidelines/undo-and-redo) · [Drag and drop](https://developer.apple.com/design/human-interface-guidelines/drag-and-drop) · [Context menus](https://developer.apple.com/design/human-interface-guidelines/context-menus) · [Pointing devices](https://developer.apple.com/design/human-interface-guidelines/pointing-devices)
- [HIG — Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) · [Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- [HIG — Notifications](https://developer.apple.com/design/human-interface-guidelines/notifications) · [Dock menus](https://developer.apple.com/design/human-interface-guidelines/dock-menus)
- [Apple — Menus and commands (SwiftUI)](https://developer.apple.com/documentation/swiftui/menus-and-commands) · [Swift with Majid — Commands](https://swiftwithmajid.com/2020/11/24/commands-in-swiftui/) · [fatbobman — SwiftUI Commands](https://fatbobman.com/en/posts/swiftui2-commands/) · [danielsaidi — Customizing the macOS menu bar](https://danielsaidi.com/blog/2023/11/22/customizing-the-macos-menu-bar-in-swiftui)
- [AbilityNet — Tahoe Text Size](https://api.abilitynet.org.uk/how-to-make-the-text-larger-on-your-apple-mac-computer-using-the-text-size-options-in-macos-26-tahoe) · [Apple Support — Make text and icons bigger](https://support.apple.com/guide/mac-help/make-text-and-icons-bigger-mchld786f2cd/mac) · [macos-tahoe.com — Accessibility guide](https://macos-tahoe.com/blog/macos-tahoe-accessibility-complete-guide-2025/)
- [anhphong — What I Learned Building a Native macOS Menu Bar App](https://medium.com/@p_anhphong/what-i-learned-building-a-native-macos-menu-bar-app-eacbc16c2e14) · [steipete — Showing Settings from macOS menu bar items](https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items)
