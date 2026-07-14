# 03 · SwiftUI: архитектура и состояние

> Серия practices · [оглавление](README.md)

Глава фиксирует архитектурные решения UI-слоя foundry-desktop: как устроено
состояние, где живёт логика, как данные из файловой системы, SQLite и
подпроцессов доезжают до экрана. Базовая линия: **Swift 6.2+, Xcode 26,
macOS 26 SDK, deployment target — macOS 26** (вердикт серии: приложение для
собственного Mac, `#available`-ветки не заводим; пометки «macOS 14+/15+» у
API ниже — справка о происхождении, не повод для веток). Язык и конкурентность — в
[01-swift-language.md](01-swift-language.md) и
[02-swift-concurrency.md](02-swift-concurrency.md); системные API (FSEvents,
Subprocess, GRDB) — в [06-system-integration.md](06-system-integration.md);
визуальный дизайн — в [05-ui-design.md](05-ui-design.md).

---

## 1. Состояние: `@Observable` — единственный современный путь

**ЧТО**: все модели состояния — классы с макросом `@Observable` (framework
Observation, macOS 14+). **ПОЧЕМУ**: per-property tracking — SwiftUI следит,
какие именно свойства читает `body` каждой view, и инвалидирует только те view,
что читают изменившееся свойство. `ObservableObject` инвалидировал *все* view,
подписанные на объект, при изменении *любого* `@Published`-свойства — целый
класс проблем производительности исчезает на уровне фреймворка.

### Таблица враперов

| Роль | Врапер | Когда |
|---|---|---|
| **Владеет** объектом | `@State var store = FilterModel()` | View создаёт и владеет `@Observable`-объектом (время жизни = identity view) |
| **Наблюдает** | обычный `let store: ProjectsStore` | Объект пришёл извне; tracking автоматический, врапер не нужен |
| **Биндит** | `@Bindable var store: ProjectsStore` | Нужны `$store.prop` для `TextField`, `List(selection:)` и т.п. |
| **Инжектит** | `@Environment(ProjectsStore.self) var store` | Объект положен в environment через `.environment(store)` |
| **Environment-значение** | `@Entry var reviewService: ReviewService = .live` | Кастомный ключ environment одной строкой (Xcode 16+) |

```swift
@Observable @MainActor
final class ProjectsStore {
    var projects: [Project] = []
    var selection: Project.ID?
    @ObservationIgnored private let repo: ProjectRepository  // зависимости не наблюдаем
    init(repo: ProjectRepository) { self.repo = repo }
}

struct ProjectListView: View {
    @Environment(ProjectsStore.self) private var store
    var body: some View {
        @Bindable var store = store   // локальный @Bindable ради $store.selection
        List(store.projects, selection: $store.selection) { p in
            ProjectRow(project: p)
        }
    }
}
```

Приём с локальным `@Bindable var store = store` внутри `body` — идиоматичный
способ получить биндинги от объекта из environment.

> **⚠️ Устарело (2023−):** `ObservableObject` / `@Published` /
> `@StateObject` / `@ObservedObject` / `@EnvironmentObject` — legacy-совместимость,
> в новом коде не используются. Миграция механическая:
>
> | Legacy | Современно |
> |---|---|
> | `class M: ObservableObject { @Published var x }` | `@Observable class M { var x }` |
> | `@StateObject var m = M()` | `@State var m = M()` |
> | `@ObservedObject var m: M` | `let m: M` |
> | `@ObservedObject` + `$m.x` | `@Bindable var m: M` |
> | `@EnvironmentObject var m: M` | `@Environment(M.self) var m` |
> | `struct MyKey: EnvironmentKey { ... }` + `extension EnvironmentValues` | `@Entry var my: My = .default` |
>
> Старые туториалы (и модели, обученные на них) массово генерируют
> `ObservableObject` — это маркер № 1 на ревью (см. чеклист).

### Правила и ловушки tracking

- **Tracking работает только там, где SwiftUI вычисляет view** (`body` и
  tracked-замыкания). Чтение observed-свойств внутри `Task {}` или escaping
  closure **не** подписывает view на изменения.
- **Коллекции `@Observable`-объектов**: свойство-массив «меняется» только при
  insert/remove. Изменение поля элемента инвалидирует только строки, читающие
  этот элемент. Это главный выигрыш для ChangeBoard: перетаскивание карточки не
  перерисовывает всю доску.
- **Computed-свойства** трекаются транзитивно, если читают stored
  observed-свойства.
- **`@Observable` не даёт потокобезопасности.** Store — `@MainActor`; мутация
  observed-состояния с фонового потока под Swift 6 strict checking — ошибка
  компиляции или runtime-крэш. Правило одного писателя: только store мутирует
  своё состояние, сервисы шлют данные, а не лезут в UI-стейт.
- **`@ObservationIgnored`** — для зависимостей и кэшей внутри store, которые не
  должны участвовать в tracking.

> **⚠️ Устарело:** ловушка «инициализатор `@State` выполняется при каждом
> обновлении родителя» смягчена на уровне фреймворка — с WWDC26 `@State`
> получил ленивую (autoclosure-style) инициализацию, значение вычисляется один
> раз. Дорогие объекты в `@State var x = Expensive()` больше не требуют
> обходных манёвров, но и злоупотреблять не стоит: тяжёлое создаётся в
> composition root.

### Observation вне SwiftUI: `Observations` (SE-0475, macOS 26)

Не-UI код может наблюдать `@Observable`-модели как `AsyncSequence` с
транзакционной коалесценцией (несколько синхронных мутаций → одна эмиссия):

```swift
// Сервис проекции пересчитывает SQL-запрос при смене фильтра в store
let filters = Observations { boardStore.activeFilter }   // трекает прочитанное
for await filter in filters {
    await projection.requery(filter)
}
```

Это закрывает нишу «store → сервис» без Combine и без ручных `didSet`.

---

## 2. Архитектурный вердикт: MV (vanilla SwiftUI), не MVVM и не TCA

**ЧТО**: логика живёт в `@Observable @MainActor` stores (per-domain, не
per-screen) и в actor-сервисах; view биндятся к stores напрямую. Отдельного
слоя ViewModel-на-экран **нет**. **ПОЧЕМУ**: маятник качнулся. Главный
исторический аргумент за ViewModels — «крупный ObservableObject перерисовывает
всё, дробим на мелкие VM» — умер вместе с `ObservableObject`: per-property
tracking `@Observable` даёт мелкозернистую инвалидацию бесплатно. Остальные
аргументы («тестируемость», «разделение») закрываются stores: `ProjectsStore`
тестируется так же, как тестировался бы ViewModel, только он один на домен, а
не один на экран.

Это согласуется с направлением самого Apple (сэмплы Food Truck, Backyard
Birds — без ViewModels; framing «Data Flow Through SwiftUI» с 2019) и с
консенсусом 2025–2026 (Ricouard «Forget MVVM», приложение Medium — почти без
VM). SwiftUI view — это struct, пересчитываемый из состояния; она и *есть*
презентационный слой.

### Слои foundry-desktop

| Слой | Что это | Изоляция |
|---|---|---|
| **Views** | Тонкие structs; локальный UI-стейт в `@State` (раскрыт ли disclosure, текст поиска до подтверждения) | `@MainActor` (implicit) |
| **Stores** | `ProjectsStore`, `ChangeBoardStore`, `ReviewStore`, `RunStore` — единственный источник правды для UI, единственный писатель observed-состояния | `@Observable @MainActor` |
| **Services** | FS-watcher, subprocess runner, git-клиент, SQLite-проекция — side effects, I/O, парсинг | `actor` / `Sendable` struct |
| **Composition root** | `App`-struct (или `AppDependencies`): создаёт сервисы, собирает stores, кладёт в environment каждой сцены | — |

```swift
@main
struct FoundryApp: App {
    // Composition root: plain init injection в stores,
    // stores — в environment каждой сцены.
    @State private var deps = AppDependencies.live()

    var body: some Scene {
        Window("Foundry", id: "main") {
            MainWindow()
                .environment(deps.projectsStore)
                .environment(deps.runStore)
        }
    }
}
```

### Почему отклонены альтернативы

- **MVVM**: по-прежнему самый распространённый паттерн в индустрии (инерция,
  привычность команд) и он «не сломан». Но для этого проекта per-screen VM —
  чистый оверхед: дублирование состояния store→VM, синхронизация, лишний слой
  прокидывания. Дробить view на под-view дешевле, чем выделять VM.
- **TCA**: зрелый (1.x, `@ObservableState`), лучший в классе exhaustive-тестинг
  эффектов и первоклассная dependency-история. Против: перманентный churn API
  (опыт трёхлетних пользователей — «постоянное переучивание»), boilerplate,
  документированная «стена производительности» на большом едином дереве
  состояния, и главное — Observation закрыла большую часть проблем, ради
  которых существовала view-scoping-машинерия TCA. Вердикт сообщества: TCA —
  для больших команд, которые покупаются целиком. foundry-desktop — не тот
  случай.

### Когда всё-таки выделять отдельный слой

MV — не догма «никаких типов между store и view». Выделяйте объект, когда:

1. **Сложный локальный процесс с жизненным циклом**: state machine визарда,
   drag-сессия доски — `@Observable`-класс, которым view владеет через
   `@State` (это и есть «ViewModel», просто по необходимости, а не по шаблону).
2. **Дорогая деривация**: сортировка/группировка тысяч записей для конкретного
   экрана — вынести в store как precomputed-свойство или в отдельный
   projection-объект, но не считать в `body`.
3. **Переиспользуемый компонент с нетривиальной логикой** (autocomplete):
   логика едет с компонентом, а не в доменный store.

Критерий: слой добавляется под конкретную боль, а не заранее «для чистоты».

### DI-вердикт

**Plain init injection в stores + `@Entry` для view-уровня. Без
Factory/swift-dependencies.** Environment читается только внутри view —
store не может достать из него зависимость («chicken-and-egg»), поэтому stores
получают сервисы через `init` из composition root. Протокольные (или
closure-typed) сервисы дают мокабельность для тестов и превью без контейнера.
Factory или swift-dependencies добавляем, только если эргономика подмены в
тестах реально начнёт жать — сейчас не жмёт.

```swift
extension EnvironmentValues {
    @Entry var reviewService: ReviewService = .live
}
// View-уровень: @Environment(\.reviewService) var reviewService
```

---

## 3. Поток данных foundry-desktop

Источник правды — файлы `.foundry/` в дереве проекта. SQLite — **проекция**
(индекс для запросов/сортировок), не хранилище. UI никогда не пишет в SQLite
напрямую и никогда не читает файлы в `body`.

```
                        ┌────────────────────────────────────────────┐
                        │                ФАЙЛОВАЯ СИСТЕМА            │
                        │   .foundry/  (source of truth, git-friendly)│
                        └───────┬────────────────────────────────────┘
                                │ FSEvents (recursive, kernel-coalesced)
                                ▼
                    ┌───────────────────────┐
                    │  actor FoundryWatcher │  AsyncStream<FSEvent>
                    │  + debounce ~200 ms   │  (шторма от git/редакторов)
                    └───────┬───────────────┘
                            │ пути изменённых файлов
                            ▼
                ┌─────────────────────────────┐
                │  actor Reconciler           │  читает файлы off-main,
                │  parse → diff → патч модели │  пишет проекцию в SQLite
                └───────┬─────────────┬───────┘
                        │             │
        патч доменной   │             │ INSERT/UPDATE (GRDB)
        модели (Sendable)│             ▼
                        │      ┌──────────────────┐
                        │      │  SQLite-проекция │
                        │      │  (GRDB)          │
                        │      └───────┬──────────┘
                        │              │ ValueObservation (запросы: доска,
                        ▼              ▼  фильтры, счётчики)
              ┌────────────────────────────────────┐
              │  @Observable @MainActor stores     │   ProjectsStore /
              │  (единственный писатель UI-state)  │   ChangeBoardStore / …
              └───────────────┬────────────────────┘
                              │ per-property observation
                              ▼
                    SwiftUI views (@State — только локальный UI-стейт)

   Параллельная ветка (живой прогон):
   claude -p (subprocess) ── stdout AsyncSequence ──▶ actor RunService
        └─ батчинг 10–30 Гц, bulk-append ──▶ RunStore ──▶ лог-панель
```

Три правила, которые держат схему:

1. **Один писатель.** Observed-состояние мутирует только его store, только на
   `@MainActor`. Сервисы возвращают/стримят `Sendable`-значения.
2. **Reconcile, не reload.** По FSEvent перечитываются только затронутые файлы
   и в модель вносится diff — полный rescan дерева только при старте/ресете.
   Иначе каждый `git checkout` — перестройка всего UI.
3. **Debounce на входе обязателен.** Редакторы и git генерируют шторма событий;
   ~200 ms settle до реконсиляции. Для непрерывных потоков (stdout) — наоборот,
   throttle: гарантированные периодические флаши (§4).

SQLite-ветка: `ValueObservation` GRDB эмитит свежий результат запроса при любом
изменении задействованных таблиц — store подписывается один раз и складывает
результат в observed-свойство:

```swift
@Observable @MainActor
final class ChangeBoardStore {
    private(set) var cards: [BoardCard] = []
    @ObservationIgnored private var observationTask: Task<Void, Never>?

    func start(db: DatabaseReader, projectID: Project.ID) {
        observationTask = Task {
            let observation = ValueObservation.tracking { db in
                try BoardCard.filter(Column("projectID") == projectID)
                             .order(Column("position")).fetchAll(db)
            }
            for try await cards in observation.values(in: db) {
                self.cards = cards        // одна мутация → одна инвалидация
            }
        }
    }
}
```

(Альтернатива — SQLiteData/`@FetchAll` от Point-Free поверх GRDB, врапер
работает прямо в `@Observable`-моделях; для проекта достаточно голого GRDB.
Схема БД и детали FSEvents/Subprocess — в
[06-system-integration.md](06-system-integration.md).)

### Live-стрим подпроцесса: батчинг обязателен

**ЧТО**: stdout `claude -p` копится в actor-сервисе и флашится в store пачками
на 10–30 Гц; store делает `append(contentsOf:)`. **ПОЧЕМУ**: наивный
по-строчный append в observed-массив — это тысячи observation-транзакций и
layout-проходов в секунду; main thread захлёбывается. Пачка = одна транзакция.

```swift
actor RunService {
    func stream(_ run: RunConfig) -> AsyncStream<[LogLine]> {
        AsyncStream { continuation in
            let task = Task {
                var buffer: [LogLine] = []
                var lastFlush = ContinuousClock.now
                for await line in try await subprocessLines(run) {   // см. главу 06
                    buffer.append(line)
                    let now = ContinuousClock.now
                    if buffer.count >= 200 || now - lastFlush > .milliseconds(50) {
                        continuation.yield(buffer)
                        buffer.removeAll(keepingCapacity: true)
                        lastFlush = now
                    }
                }
                if !buffer.isEmpty { continuation.yield(buffer) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }   // cancel → SIGTERM
        }
    }
}

@Observable @MainActor
final class RunStore {
    private(set) var lines: [LogLine] = []
    static let maxLines = 20_000                     // ring buffer; полный лог — на диске

    func attach(_ service: RunService, run: RunConfig) -> Task<Void, Never> {
        Task {
            for await batch in await service.stream(run) {
                lines.append(contentsOf: batch)      // bulk: одна транзакция
                if lines.count > Self.maxLines {
                    lines.removeFirst(lines.count - Self.maxLines)
                }
            }
        }
    }
}
```

Правила потока: (1) bulk-append, никогда по одной строке; (2) ring buffer в
памяти, полный лог — на диске; (3) throttle, не debounce — стрим непрерывный,
пользователь должен видеть прогресс; (4) для по-настоящему тяжёлой лог-панели —
`NSTextView` (§7).

---

## 4. Swift 6.2 concurrency в SwiftUI

Подробно — в [02-swift-concurrency.md](02-swift-concurrency.md); здесь — стык
с UI.

### `@MainActor` по умолчанию

**ЧТО**: app-таргет собирается с default isolation = `MainActor`
(«Approachable Concurrency», Swift 6.2 / Xcode 26; новые таргеты Xcode 26 так
и создаются). Выход из изоляции — точечный: `nonisolated`, `@concurrent`,
actor-типы. **ПОЧЕМУ**: 90 % кода desktop-приложения — UI-центричный; режим
убирает шум `@MainActor`-аннотаций и большинство ложных data-race-ошибок.
Конкурентность вводится там, где её показал профайлер, а не по умолчанию.

- `@concurrent` — явная пометка «эта async-функция всегда уходит на глобальный
  executor» (парсинг, диффы, сканирование дерева).
- Все `View` — implicit `@MainActor` целиком (не только `body`) начиная со
  Swift 6. Stores помечаем `@MainActor` явно — они переживут смену настроек
  модуля.

### `.task` — жизненный цикл асинхронной работы view

**ЧТО**: потребление стримов, привязанных к экрану, — только через `.task` /
`.task(id:)`. **ПОЧЕМУ**: `.task` стартует при появлении view и
**автоматически отменяется** при исчезновении её identity — ручной
`onDisappear`-cleanup не нужен; `.task(id:)` перезапускается при смене id.

```swift
struct RunLogPane: View {
    @Environment(RunStore.self) private var store
    let runID: Run.ID
    var body: some View {
        LogView(lines: store.lines)
            .task(id: runID) {                 // смена прогона → cancel + restart
                await store.streamLog(for: runID)
            }
    }
}
```

Анти-правило: стримы времени жизни приложения (FS-watcher) в `.task` view не
живут — они стартуют один раз в store из composition root; `.task` — для
per-screen подписок.

### Стык store ↔ сервис без view: `Observations`

`Observations` (SE-0475) — реактивная связка «store изменился → сервис
пересчитал» без Combine: см. пример в §1. Транзакционная коалесценция
гарантирует, что серия синхронных мутаций даст одну эмиссию — идеально для
«фильтр доски изменился → перезапросить проекцию».

### Частые обновления без тормозов

Сводка (детали в §3): коалесценция off-main → флаш 10–30 Гц → bulk-мутация →
ring buffer → при необходимости AppKit-текст. Debounce — для bursty-источников
(FSEvents, поиск), throttle — для непрерывных (stdout).

---

## 5. Сцены и окна macOS

### Набор сцен

| Сцена | Для чего в foundry-desktop |
|---|---|
| `Window("Foundry", id: "main")` | Главный дашборд — ровно одно окно |
| `WindowGroup(for: Project.ID.self)` | Проект в отдельном окне: data-driven, SwiftUI гарантирует одно окно на значение |
| `WindowGroup(for: Review.ID.self)` | ReviewScreen в отдельном окне |
| `Settings` | Автоматически: пункт меню + ⌘, ; внутри `TabView` с панами |
| `MenuBarExtra` | Статус агентов в menu bar (опционально) |
| `UtilityWindow` | Плавающие панели (macOS 15+), если понадобятся |

```swift
WindowGroup(for: Review.ID.self) { $reviewID in
    if let reviewID { ReviewScreen(reviewID: reviewID) }
}
// Из любого view:
@Environment(\.openWindow) private var openWindow
Button("Open Review") { openWindow(value: review.id) }   // откроет или сфокусирует
```

Placement/поведение (WWDC24, macOS 15): `defaultSize`, `windowResizability`,
`defaultWindowPlacement { … }`, `restorationBehavior(.disabled)` для
transient-окон. Действия из environment: `openWindow`, `dismissWindow`,
`pushWindow`.

### Навигация: selection-driven, не stack-driven

**ЧТО**: `NavigationSplitView` (sidebar → detail), selection в store управляет
detail-панелью. **ПОЧЕМУ**: Mac-приложения не пушат стек, они меняют панели;
selection-модель естественно переживает многооконность и restoration. На
macOS 26 `NavigationSplitView` автоматически получает Liquid Glass sidebar.

```swift
NavigationSplitView {
    List(store.projects, selection: $store.selection) { ProjectRow(project: $0) }
} detail: {
    if let id = store.selection { ProjectDetail(projectID: id) }
    else { ContentUnavailableView("Select a Project", systemImage: "folder") }
}
```

`NavigationStack(path:)` — только внутри detail-колонки, где иерархия
настоящая (артефакт → файл → diff). Программная навигация = мутация
selection/path в store.

### Состояние между окнами и restoration

- **Общие stores создаются один раз** в composition root и инжектятся
  `.environment(...)` в *каждую* сцену — все окна видят одни данные.
- **Per-window состояние** — `@State`/`@SceneStorage` во view: у каждого окна
  свой selection, свой набор раскрытых секций. `@SceneStorage` даёт лёгкую
  restoration (выбранная вкладка, sidebar-selection) поверх штатного
  macOS-механизма восстановления окон.
- **Меню → активное окно**: `focusedSceneValue` + `@FocusedValue` — команды из
  `Commands` роутятся в состояние окна с фокусом.

---

## 6. Списки, таблицы, производительность

### Выбор контейнера

**ЧТО**: для больших данных — `List`; `LazyVStack` — только когда нужны
per-row-эффекты, недостижимые в List. **ПОЧЕМУ**: List использует recycling
ячеек (AppKit-класс механики), LazyVStack — чистый SwiftUI и **не освобождает
созданные view** до смерти контейнера.

> **⚠️ Устарело:** интуиция «Lazy = быстро, List = тяжёлый legacy» неверна.
> Замеры Fatbobman: прокрутка до конца большого списка — 5.5 с (List) против
> 52.3 с (LazyVStack); 4.6 против 78 подвисаний. Плюс macOS `List` получил
> большой прирост в цикле macOS 26 (~10k строк — «snappy», рабочий предел
> ~20k против прежних ~3k).

| Контейнер | Ниша в проекте | Предел |
|---|---|---|
| `List` | Sidebar, списки прогонов, ChangeBoard-колонки | ~20k строк (macOS 26) |
| `Table` | Табличные данные: артефакты, файлы, история | ок до ~10k; selection тупит к ~50k |
| `LazyVStack` в `ScrollView` | Карточные ленты со спецэффектами | сотни, не тысячи |
| `NSTableView` (representable) | >50k строк / тяжёлое per-cell-взаимодействие | — |

### `Table` на macOS

Сортировка — `KeyPathComparator` + биндинг `sortOrder` (сортирует **ваш код**,
таблица только сообщает порядок); selection — `Set<ID>`; контекстное меню —
`contextMenu(forSelectionType:)` **на самой Table**, а не на ячейках:

```swift
@State private var sortOrder = [KeyPathComparator(\Artifact.modifiedAt, order: .reverse)]
@State private var selected: Set<Artifact.ID> = []

Table(store.artifacts, selection: $selected, sortOrder: $sortOrder) {
    TableColumn("Name", value: \.name)
    TableColumn("Kind", value: \.kind.rawValue)
    TableColumn("Modified", value: \.modifiedAt) { Text($0.modifiedAt, style: .relative) }
}
.onChange(of: sortOrder) { _, order in store.sort(by: order) }
.contextMenu(forSelectionType: Artifact.ID.self) { ids in
    Button("Reveal in Finder") { store.reveal(ids) }
}
```

Известные острые углы: нет сортировки Bool-колонок; `.contextMenu` на
содержимом ячейки покрывает только ячейку; нет сигнала «меню открыто».

### Identity-дисциплина

**ЧТО**: стабильные `Identifiable`-id из домена. **ПОЧЕМУ**: identity — основа
диффинга; нестабильный id = пересоздание view, потеря `@State`, ломаные
анимации, утечки `.task`.

```swift
// ПЛОХО: новый id на каждый пересчёт body — строка «новая» всегда
ForEach(lines, id: \.self) { ... }            // для неуникальных строк лога
ForEach(items.indices, id: \.self) { ... }    // id меняется при вставке в середину

// ХОРОШО: доменный стабильный id
struct LogLine: Identifiable { let id: Int /* монотонный счётчик */; let text: String }
ForEach(lines) { LogRow(line: $0) }
```

Смежное: не плодить `AnyView` в горячих путях; помнить, что `if/else` в body
меняет *identity* ветки (сброс состояния и transition), а модификатор с
параметром — нет. Выбирать осознанно.

### `body` должен быть дёшев

Никакой фильтрации/сортировки/форматирования тысяч элементов в `body` — body
вызывается часто, всё дорогое precompute-ится в store при мутации. С
Observation мелкозернистая инвалидация делает бóльшую часть работы, ради
которой раньше городили `EquatableView`.

```swift
// ПЛОХО: сортировка при каждом пересчёте
var body: some View {
    List(store.cards.sorted { $0.position < $1.position }) { ... }
}
// ХОРОШО: store хранит уже отсортированное (или сортирует SQL-проекция)
var body: some View { List(store.cards) { ... } }
```

### Профилирование: Instruments (Xcode 26)

SwiftUI-инструмент переписан (WWDC25): треки **Update Groups**, **Long View
Body Updates**, **Long Representable Updates** и **cause-and-effect graph** —
показывает, какая мутация состояния инвалидировала какие body. Наконец-то
отвечает на «*почему* эта view обновилась». Workflow: профиль → длинные/лишние
апдейты → причина → фикс (сузить чтение observed-свойств, батчить мутации,
убрать работу из body). Быстрый дебаг-хак: `let _ = Self._printChanges()` в
body (только debug).

Типовые ловушки перерендера, по убыванию частоты:

1. Store-«бог», у которого все читают одно крупное свойство (например, целый
   массив), хотя строке нужен один элемент → передавать в строку элемент.
2. Форматирование/сортировка в body (выше).
3. Нестабильные id / `UUID()` в body.
4. `updateNSView` без диффа (§7) — трек Long Representable Updates.
5. По-строчные мутации из стрима вместо батчей (§3).

---

## 7. AppKit interop

### `NSViewRepresentable` + `Coordinator` — правила

**ЧТО**: `makeNSView` создаёт один раз; `updateNSView` **обязан диффить** —
пушить в NSView только реально изменившиеся значения. **ПОЧЕМУ**:
`updateNSView` вызывается при каждом обновлении SwiftUI-контекста; безусловная
запись свойств NSView = AppKit-работа (layout, invalidate) на каждый чих. Это
настолько частый источник подвисаний, что в Instruments есть отдельный трек.

```swift
struct LogTextView: NSViewRepresentable {
    let lines: [LogLine]

    func makeNSView(context: Context) -> NSScrollView {
        let view = NSTextView.scrollableTextView()
        let text = view.documentView as! NSTextView
        text.isEditable = false
        text.usesFindBar = true
        context.coordinator.textView = text
        return view
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Дифф: дописываем только новые строки, не переустанавливаем весь текст
        context.coordinator.append(newLines: lines)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator {
        weak var textView: NSTextView?
        private var renderedCount = 0
        func append(newLines: [LogLine]) {
            guard newLines.count > renderedCount, let tv = textView else { return }
            let chunk = newLines[renderedCount...].map(\.text).joined(separator: "\n")
            tv.textStorage?.append(NSAttributedString(string: chunk + "\n"))
            renderedCount = newLines.count
            tv.scrollToEndOfDocument(nil)
        }
    }
}
```

`Coordinator` — мост delegate/target-action обратно в SwiftUI (запись через
`@Binding` или closures). Representable-типы — `@MainActor`. Бонус macOS 26:
AppKit получил встроенный Observation-tracking (`NSView.updateProperties()`,
tracking в `layout`/`draw`) — обёрнутый AppKit-код может наблюдать
`@Observable`-модели напрямую, меньше ручной сантехники.

### Что ЕЩЁ требует AppKit (2026)

| Задача | Инструмент |
|---|---|
| Лог-панель / код / диффы (большие документы, append-scroll 100k+ строк) | `NSTextView` (TextKit 2) — планировать с первого дня для лог-пейна |
| Таблицы >50k строк с тяжёлым per-cell-взаимодействием | `NSTableView` / `NSOutlineView` |
| Точные события: локальные `NSEvent`-мониторы (pinch, клики с модификаторами), кастомные курсоры | AppKit через representable |
| Императивный доступ к `NSWindow` сверх SwiftUI-модификаторов | representable-хелпер |
| Интроспекция контекстного меню («меню открыто?») | AppKit |

### Что УЖЕ НЕ требует AppKit

> **⚠️ Устарело:** старые списки «SwiftUI на Mac не умеет…» сильно сжались.
> Больше не повод для AppKit: web-контент (`WebView`, macOS 26), базовый
> rich text (`TextEditor` + `AttributedString`, macOS 26), placement/стайлинг
> окон (WWDC24 API), reorder списков (`.reorderable()`, WWDC26),
> swipe actions в любом контейнере (WWDC26), видимость drag-сессии
> (`.onDragSessionUpdated`, WWDC26).

Стратегия проекта: «build in SwiftUI, reach into AppKit where needed» — и
каждое «where needed» перепроверять по текущему SDK, список тает ежегодно.

---

## 8. Previews

**ЧТО**: `#Preview` + `@Previewable` + `PreviewModifier` с mock-сторами; каждая
нетривиальная view получает превью. **ПОЧЕМУ**: MV-архитектура делает превью
дешёвыми — view зависит только от stores/environment, значит один trait
подменяет весь мир на моки. Это и есть практический аргумент за
environment-инъекцию против синглтонов.

> **⚠️ Устарело:** `struct X_Previews: PreviewProvider` — legacy; только макрос
> `#Preview` (и `#Preview("Name", traits:)`).

```swift
// Интерактивный биндинг без обёртки-view (Xcode 16+):
#Preview {
    @Previewable @State var query = ""
    SearchField(text: $query)
}

// Переиспользуемое кэшируемое mock-окружение:
struct MockStores: PreviewModifier {
    static func makeSharedContext() async throws -> AppDependencies {
        .mock()                         // in-memory SQLite, фейковые прогоны
    }
    func body(content: Content, context: AppDependencies) -> some View {
        content
            .environment(context.projectsStore)
            .environment(context.runStore)
    }
}

#Preview(traits: .modifier(MockStores())) {
    ChangeBoardView(projectID: .mock)
}
```

`makeSharedContext()` асинхронный и **кэшируется между превью** — идеален для
сидирования in-memory SQLite-проекции один раз на все превью экрана.

DI-вердикт (повтор из §2, потому что превью — главный потребитель): plain init
injection + `@Entry`; никакого DI-фреймворка ради превью не требуется.

---

## 9. Композиция и переиспользование

Иерархия инструментов переиспользования — от предпочтительного к тяжёлому:

1. **Мелкие view + `@ViewBuilder`-слоты** — контейнерные компоненты
   (kanban-колонка, review-карточка) принимают контент слотами:

```swift
struct BoardColumn<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading) {
            Text(title).font(.headline)
            ScrollView { LazyVStack(spacing: 8) { content } }
        }
    }
}
```

2. **`ViewModifier` + `View`-extension** — сквозная стилистика
   (`.cardStyle()`, `.panelBackground()`); модификаторы value-дёшевы, без
   аллокаций в `body(content:)`.

3. **Стили семантических контролов** — идиоматичный macOS-механизм:
   `ButtonStyle`/`PrimitiveButtonStyle`, `ToggleStyle`, `LabeledContentStyle`,
   `GroupBoxStyle`. Стиль задаётся один раз и распространяется вниз по
   иерархии как environment:

```swift
struct ToolbarChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
extension ButtonStyle where Self == ToolbarChipButtonStyle {
    static var toolbarChip: Self { .init() }
}
// Применение на всю панель: .buttonStyle(.toolbarChip)
```

4. **`@Entry` для темы** — семантические токены (цвета/отступы/типографика)
   как environment-значения, а не параметры инитов. На macOS 26 предпочитать
   системные материалы и semantic colors (Liquid Glass адаптируется сам);
   детали — в [05-ui-design.md](05-ui-design.md).

```swift
extension EnvironmentValues {
    @Entry var boardTheme: BoardTheme = .standard
}
```

5. **Custom `Layout`** (macOS 13+) — там, где встроенных layout нет: flow
   layout для тег-чипов, равноширокие kanban-колонки. Кэш — через associated
   type `Cache`; `AnyLayout` — для анимированного переключения layout.

6. **`containerValues`** (`@Entry` на `ContainerValues`, Xcode 16+) —
   метаданные per-child в кастомных контейнерах (колонка читает метаданные
   карточек-детей).

Скролл-поведение — только штатное: `scrollPosition`, `onScrollGeometryChange`
(macOS 15+), `defaultScrollAnchor(.bottom)` для auto-follow лог-панели.
Никакой introspection-магии.

---

## Чеклист ревью SwiftUI-кода

Вопросы для ревью кода (в т.ч. сгенерированного Claude). «Да» на левый столбец
= вернуть на доработку.

| # | Красный флаг | Норма |
|---|---|---|
| 1 | `ObservableObject`, `@Published`, `@StateObject`, `@ObservedObject`, `@EnvironmentObject` | `@Observable` + таблица враперов из §1 |
| 2 | Класс `FooViewModel` на экран, дублирующий store | View читает store напрямую; отдельный объект — только по критериям §2 |
| 3 | Store без `@MainActor` / мутация observed-свойств из фонового Task | `@Observable @MainActor`, один писатель |
| 4 | Сервис/синглтон дёргается прямо из view (`GitClient.shared.fetch()` в body/кнопке) | View → store → сервис; сервисы init-injected в store |
| 5 | `ForEach(items.indices, id: \.self)`, `id: \.self` на неуникальных данных, `UUID()` в body | Стабильные доменные `Identifiable`-id |
| 6 | Сортировка/фильтрация/форматирование коллекций в `body` | Precompute в store / SQL-проекции |
| 7 | По-элементные append из стрима в observed-массив | Батчинг 10–30 Гц + `append(contentsOf:)` + ring buffer |
| 8 | Стрим приложения (watcher) стартует в `.task` какой-то view; ручной cleanup в `onDisappear` | App-lifetime — в store из composition root; per-screen — `.task(id:)` |
| 9 | `updateNSView` безусловно переустанавливает состояние NSView | Дифф против coordinator-кэша |
| 10 | `LazyVStack` для тысяч строк; `Table` на 100k строк | `List` / `Table` по таблице пределов §6; сверх — `NSTableView` |
| 11 | `.contextMenu` на ячейках Table | `contextMenu(forSelectionType:)` на Table |
| 12 | `AnyView` в горячих путях, `if/else`-ветвление там, где хватает модификатора | Стабильная структура view |
| 13 | `PreviewProvider`; превью нет или оно требует живой БД/сети | `#Preview` + `PreviewModifier` с mock-сторами |
| 14 | `EnvironmentKey`-boilerplate; передача темы через все иниты | `@Entry` |
| 15 | Combine/`objectWillChange` для связки store→сервис | `Observations` (SE-0475) или AsyncStream |
| 16 | Хардкод цветов, кастомный chrome окна без нужды | Semantic colors, системные материалы (см. [05-ui-design.md](05-ui-design.md)) |
| 17 | Навигация push-стеком там, где Mac-паттерн — selection | `NavigationSplitView` + selection в store |

Сомнительный перерендер — не спорить, а профилировать: Instruments → SwiftUI →
cause-and-effect graph (§6).

---

## Источники

Состояние и Observation:

- [Apple: Migrating from ObservableObject to the Observable macro](https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro)
- [Donny Wals: @Observable in SwiftUI explained](https://www.donnywals.com/observable-in-swiftui-explained/)
- [nilcoalescing: Using @Observable in SwiftUI views](https://nilcoalescing.com/blog/ObservableInSwiftUI/)
- [Clive Liu: Observable vs ObservableObject](https://clive819.github.io/posts/observable-vs-observable-object-understanding-the-differences/)
- [SE-0475: Transactional Observation of Values (Observations)](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0475-observed.md)
- [Majid: Streaming changes with Observations](https://swiftwithmajid.com/2025/07/30/streaming-changes-with-observations/)
- [Use Your Loaf: Swift Observations AsyncSequence](https://useyourloaf.com/blog/swift-observations-asyncsequence-for-state-changes/)

Архитектура:

- [Thomas Ricouard: SwiftUI in 2025 — Forget MVVM](https://dimillian.medium.com/swiftui-in-2025-forget-mvvm-262ff2bbd2ed)
- [MV vs MVVM in SwiftUI (2025)](https://dev.to/yossabourne/mv-vs-mvvm-in-swiftui-2025-which-architecture-should-you-use-video-26nb)
- [Rod Schmidt: 3 years of TCA — experience report](https://rodschmidt.com/posts/composable-architecture-experience/)
- [swiftyplace: TCA performance analysis](https://www.swiftyplace.com/blog/the-composable-architecture-performance)
- [Lucas van Dongen: Dependency Injection in Swift/SwiftUI](https://lucasvandongen.dev/dependency_injection_swift_swiftui.php)

Поток данных:

- [SwiftToolkit: Reacting to file changes (AsyncStream + debounce)](https://www.swifttoolkit.dev/posts/file-monitor)
- [alexwlchan: Watching for file changes on macOS (2026)](https://alexwlchan.net/2026/watch-files-on-macos/)
- [Swift Forums: Consuming updates from actors on MainActor](https://forums.swift.org/t/what-would-be-the-go-to-pattern-consuming-updates-from-actors-from-mainactor/70909)
- [Swift Forums: Updating SwiftUI many times a second performantly](https://forums.swift.org/t/how-to-update-swiftui-many-times-a-second-while-being-performant/71249)
- [SQLiteData 1.0 (Point-Free, альтернатива для проекционной БД)](https://www.pointfree.co/blog/posts/184-sqlitedata-1-0-an-alternative-to-swiftdata-with-cloudkit-sync-and-sharing)

Concurrency в UI:

- [Donny Wals: Should you opt in to Swift 6.2 MainActor isolation](https://www.donnywals.com/should-you-opt-in-to-swift-6-2s-main-actor-isolation/)
- [SwiftLee: Default actor isolation in Swift 6.2](https://www.avanderlee.com/concurrency/default-actor-isolation-in-swift-6-2/)

Сцены и окна:

- [WWDC24: Work with windows in SwiftUI](https://developer.apple.com/videos/play/wwdc2024/10149/)
- [WWDC24: Tailor macOS windows with SwiftUI](https://developer.apple.com/videos/play/wwdc2024/10148/)
- [nilcoalescing: Scene types in a SwiftUI Mac app](https://nilcoalescing.com/blog/ScenesTypesInASwiftUIMacApp/)
- [DEV: SwiftUI Window, Scene & Multi-Window Architecture](https://dev.to/sebastienlato/swiftui-window-scene-multi-window-architecture-23mi)

Производительность:

- [Fatbobman: List or LazyVStack](https://fatbobman.com/en/posts/list-or-lazyvstack/)
- [Use Your Loaf: SwiftUI Tables quick guide](https://useyourloaf.com/blog/swiftui-tables-quick-guide/)
- [Fatbobman: Table in SwiftUI](https://fatbobman.com/en/posts/table_in_swiftui/)
- [TrozWare: SwiftUI for Mac 2025](https://troz.net/post/2025/swiftui-mac-2025/)
- [WWDC25: Optimize SwiftUI performance with Instruments](https://developer.apple.com/videos/play/wwdc2025/306/)
- [Apple: Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/Xcode/understanding-and-improving-swiftui-performance)

Interop, previews, композиция:

- [WWDC26: Use SwiftUI with AppKit and UIKit](https://developer.apple.com/videos/play/wwdc2026/272/)
- [philz.blog: Built-in Observable support in AppKit/UIKit (macOS 26)](https://philz.blog/built-in-support-for-swift-observable-in-appkit-and-uikit-on-macos-26-and-ios-26-3/)
- [pfandrade: A Mac-assed app update (June 2026)](https://pfandrade.me/blog/swiftui-mac-assed-wwdc27-update/)
- [SwiftLee: @Previewable macro](https://www.avanderlee.com/swiftui/previewable-macro-usage-in-previews/)
- [Majid: The power of previews in Xcode](https://swiftwithmajid.com/2024/11/26/the-power-of-previews-in-xcode/)
- [Majid: What is new in SwiftUI after WWDC26](https://swiftwithmajid.com/2026/06/08/what-is-new-in-swiftui-after-wwdc26/)
- [InfoQ: SwiftUI at WWDC26](https://www.infoq.com/news/2026/07/swiftui-wwdc26/)
