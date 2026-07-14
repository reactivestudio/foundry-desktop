# 01 · Swift: язык и идиомы

> Серия practices · [оглавление](README.md)

Целевая версия: **Swift 6.3, Xcode 26** (язык — Swift 6 language mode, семантика тулчейна 6.2+).
Глава покрывает язык вне конкурентности; actors, async/await, Sendable — в главе
[02-swift-concurrency.md](02-swift-concurrency.md).

Аудитория: код пишет Claude, ревьюит senior Kotlin-инженер. Раздел
[«Kotlin → Swift»](#kotlin--swift-маппинг-и-ловушки) — основной инструмент ревьюера;
остальные разделы — нормы, на соответствие которым проверяется код.

---

## 1. API Design Guidelines

Канон — [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
(swift.org, актуален без изменений и в 2026). Ключевой принцип: **ясность в точке
вызова важнее краткости**. API проектируется от call site: сначала пишется вызов,
потом сигнатура.

### 1.1 Нейминг

| Правило | Пример |
|---|---|
| Опускать слова, дублирующие тип | `remove(at: index)`, не `removeElementAtIndex(_:)` |
| Именовать по роли, не по типу | `var greeting: String`, не `var string: String` |
| Mutating = глагол, nonmutating = причастие | `sort()` / `sorted()`, `append(_:)` / `appending(_:)` |
| Noun-based пары | `formUnion(_:)` (mutating) / `union(_:)` (nonmutating) |
| Bool читается как утверждение | `isEmpty`, `isRunning`, `canCancel`, `intersects(_:)` |
| Протокол-«что это» — существительное | `Collection`, `EventSource` |
| Протокол-«умеет» — `-able`/`-ing` | `Equatable`, `ProgressReporting` |
| Акронимы — единый регистр | `urlSession`, `userID`, `JSONDecoder`, `HTTPClient` |
| Вызов читается как английская фраза | `x.insert(y, at: z)` → "x, insert y at z" |

Регистр: `UpperCamelCase` для типов и протоколов, `lowerCamelCase` для всего остального.
Doc-комментарий на каждую публичную декларацию: если функцию нельзя описать одним
простым предложением — она, вероятно, спроектирована неверно.

### 1.2 Argument labels

Метки аргументов — часть имени функции (в отличие от Kotlin, где named args опциональны
на стороне вызова). Правила выбора:

```swift
// Аргументы неразличимы по смыслу → без меток
min(a, b)
zip(events, timestamps)

// Value-preserving конверсия → без первой метки
Int64(someInt32)
// Сужающая/lossy — метка называет потерю
UInt32(truncating: bits)

// Первый аргумент — часть предложной фразы → метка с предлога
events.removeAll(where: { $0.isStale })
session.write(data, to: pipe)

// Первый аргумент — часть грамматической фразы → без метки, слова в имя метода
view.addSubview(indicator)
runner.appendEvent(event)

// Иначе — метки на всё
func schedule(review: Artifact, reviewer: Agent, deadline: Date)
```

### 1.3 Прочие конвенции

- Методы и свойства предпочтительнее свободных функций. Свободные функции — только
  когда нет очевидного `self` (`min(x, y, z)`), для unconstrained generics (`print(_:)`)
  или устоявшейся нотации (`sin(x)`).
- Не перегружать по типу возврата — ломает вывод типов.
- Default-параметры вместо семейства методов-вариаций.
- Документировать сложность computed property, если она не O(1).
- Форматирование и стиль — enforce инструментами: **swift-format** (официальный, в
  тулчейне с Swift 6.0, интегрирован в Xcode 26) + SwiftLint. Стиль не обсуждается
  на ревью — он проверяется CI. Детали — в [08-project-tooling-distribution.md](08-project-tooling-distribution.md).

---

## 2. Value vs reference types

### 2.1 Правило: struct по умолчанию

**ЧТО:** новый тип — это `struct` (или `enum`), пока не доказана необходимость `class`.

**ПОЧЕМУ:** value-семантика исключает shared mutable state как класс ошибок, а в
Swift 6 ещё и радикально дешевле для конкурентности: struct из `Sendable`-полей
неявно `Sendable`; класс — почти никогда (только `final` + все stored `let`).

`class` оправдан, когда нужно:

1. **Identity** — важна «тот же самый объект» (`===`): контроллер подпроцесса,
   соединение, кэш.
2. **Разделяемое мутабельное состояние намеренно** — но в Swift 6 это обычно
   `actor` или `@MainActor`-класс, а не «голый» class (→ [02](02-swift-concurrency.md)).
3. **ObjC / framework interop** — NSObject-наследники, делегаты AppKit.
4. **Lifetime через deinit** — хотя для уникальных ресурсов `~Copyable` struct
   часто лучше (§5.4).
5. Очень большие данные, где копирование дорого и CoW неприменим — редкость,
   сначала измерить.

Классы — **`final` по умолчанию**; `final` снимается только там, где subclassing —
спроектированная точка расширения. Это и корректность (никто не переопределит
инвариант), и производительность (девиртуализация).

```swift
// ХОРОШО: доменное событие из JSON-стрима foundry — value type
struct FoundryEvent: Sendable, Codable, Equatable {
    let id: String
    let kind: Kind
    let timestamp: Date

    enum Kind: String, Codable, Sendable {
        case toolUse = "tool_use"
        case message
        case result
    }
}

// ПЛОХО: class без причины — не Sendable, identity не нужна
final class FoundryEventClass {
    var id: String = ""
    var kind: String = ""
}
```

### 2.2 Copy-on-write (CoW)

Коллекции stdlib (`Array`, `Dictionary`, `Set`, `String`, `Data`) — CoW: присваивание
O(1), реальная копия — при первой мутации. Передавать массив событий по значению —
дёшево; страх «оно же копирует» из Java/Kotlin-мира здесь неуместен.

Собственный CoW пишут только для больших кастомных value-типов над heap-хранилищем:

```swift
struct EventBuffer {
    private final class Storage { var events: [FoundryEvent]; init(_ e: [FoundryEvent]) { events = e } }
    private var storage: Storage

    mutating func append(_ event: FoundryEvent) {
        if !isKnownUniquelyReferenced(&storage) {      // триггер CoW
            storage = Storage(storage.events)
        }
        storage.events.append(event)
    }
}
```

Gotcha: `isKnownUniquelyReferenced` работает только на переменной класс-типа; CoW-тип,
лежащий внутри класса или экзистенциала, может всегда видеть «не уникально» из-за
лишних ссылок.

Для маленьких fixed-size буферов на горячем пути в Swift 6.2+ есть
**`InlineArray<N, T>`** (сахар `[5 of Int]`) — inline/stack-хранение без CoW и без
heap-аллокации (копируется жадно), и **`Span`** — безопасный borrowed-view над
непрерывной памятью, замена большинству `withUnsafeBufferPointer`-паттернов.
Для парсинга JSON-стрима из подпроцесса это редко нужно — сначала профилировать.

### 2.3 Equatable / Hashable / Codable

**ЧТО:** объявлять конформанс и давать компилятору синтезировать реализацию.

**ПОЧЕМУ:** ручные `==` / `hash(into:)` — фабрика багов (добавили поле — забыли
обновить). Синтез требует, чтобы все stored-поля (и payload'ы enum-кейсов) конформили.

- Кастомизация хеша — только через `hash(into:)`, никогда `hashValue`.
- `Codable` c нестандартными ключами — вложенный `enum CodingKeys: String, CodingKey`,
  а не ручные `encode(to:)` / `init(from:)`, если отличаются только имена:

```swift
struct SessionResult: Codable {
    let sessionID: String
    let totalCostUSD: Double

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case totalCostUSD = "total_cost_usd"
    }
}
```

- Конформанс — рядом с типом или в **same-file** extension (синтез работает только
  в том же файле, не cross-file).
- Retroactive-конформансы чужих типов требуют `@retroactive` (SE-0364) — последнее
  средство: сломается, когда библиотека добавит конформанс сама.
- `Identifiable` для всего, что попадает в SwiftUI-списки; ID — стабильный доменный,
  **не** `UUID()` в инициализаторе (регенерация ID ломает diffing при перезагрузке).
- Для классов `Equatable`/`Hashable` не синтезируются; NSObject живёт на
  `isEqual`/`hash` — не смешивать две системы.

---

## 3. Optionals: дисциплина

Иерархия предпочтений, сверху вниз:

1. **Не создавать optional.** Проектировать API так, чтобы возвращать non-optional;
   отсутствие со смыслом моделировать enum-кейсом, который говорит *почему* пусто.
2. **`guard let` для предусловий** — happy path без вложенности:

```swift
func parseEvent(_ line: String?) throws -> FoundryEvent {
    guard let line, !line.isEmpty else { throw StreamError.emptyLine }
    // line — non-optional до конца области видимости
    return try decoder.decode(FoundryEvent.self, from: Data(line.utf8))
}
```

3. **Shorthand `if let x` (Swift 5.7+, SE-0345)** — современный стиль:

```swift
// ХОРОШО
if let session { render(session) }

// ⚠️ Устарело: избыточная форма из туториалов до 2022
if let session = session { render(session) }
```

Shorthand — только для затенения того же имени; `if let name = session?.name`
по-прежнему пишется полностью.

4. **Chaining + `??`** для значений по умолчанию: `let count = events?.count ?? 0`.
   Цепочки глубже 2–3 уровней — запах Law of Demeter.
5. **`map`/`flatMap` на Optional** — умеренно; пирамиды `flatMap` хуже явного `if let`.

### Force unwrap (`!`)

Допустим **только когда nil — ошибка программиста, а не runtime-состояние**, т.е.
работает как assertion: ресурсы, гарантированные бандлом/сборкой; проверка, которую
система типов не видит (с комментарием почему). Если нужна диагностика — 
`guard let ... else { preconditionFailure("...") }`. В тестах вместо `!` —
`#require(...)` (Swift Testing): падает с сообщением, а не роняет раннер.
`try!` и `as!` — то же правило.

### Implicitly-unwrapped optionals (`T!`)

**В новом SwiftUI/CLI-коде оправданных применений нет.** Легаси-ниши (`@IBOutlet`,
двухфазная инициализация ObjC) в этом проекте не встречаются. `lateinit`-привычку
заменять инъекцией через `init`, `lazy var` или честным optional.

### Прочее

- `Bool?` как трёхзначная логика — анти-паттерн; моделировать enum'ом.
- `if x != nil` + `x!` ниже по коду — анти-паттерн; развернуть один раз через binding.
- `Optional` — это `enum { case none, some(Wrapped) }`; в `switch` идиоматичны
  паттерны `case .some(let x)` / `case let x?`.

---

## 4. Обработка ошибок

### 4.1 Инструменты и когда какой

| Механизм | Когда |
|---|---|
| `throws` (untyped) | **Дефолт** для всего, что может отказать по причинам, которые вызывающий захочет различать/показывать |
| `throws(E)` typed (SE-0413, Swift 6.0) | Закрытые стабильные домены ошибок; generic-проброс ошибки (замена `rethrows`); Embedded Swift. **Редко** — см. 4.2 |
| `Result<T, E>` | Хранение/передача исхода как значения (кэш результата, сбор исходов из TaskGroup). После async/await — **не для control flow**; на границе — `try result.get()` |
| Возврат `Optional` | У неудачи ровно одно очевидное неисключительное значение: «не найдено» / «не парсится» (`Int("abc")`). Если вызывающий спросит «а почему nil?» — надо `throw` |
| `fatalError` / `precondition` / `assert` | Ошибки программиста (нарушенные инварианты), никогда — ожидаемые runtime-условия. `assert` — только debug; `precondition` — и release; `fatalError` — всегда + noreturn |

### 4.2 Typed throws — когда да, когда нет

SE-0413 прямо говорит: **untyped `throws` остаётся дефолтом**. Ошибки обычно
пробрасываются и показываются, а не обрабатываются исчерпывающе, и их набор
меняется со временем — в отличие от типов.

Typed throws уместен, когда:

1. Набор ошибок **закрыт и стабилен**: тот же модуль/пакет, что и вызывающие,
   либо самостоятельная leaf-библиотека.
2. **Generic-код прозрачно пробрасывает** ошибку вызывающего — поэтому stdlib `map`
   теперь `throws(E)`; `rethrows` фактически легаси.
3. Embedded Swift / контексты без аллокаций (боксинг `any Error` недоступен).

Анти-guidance: **не** ставить typed throws на public API эволюционирующей библиотеки —
каждый новый кейс ломает исчерпывающие `catch`; теряется возможность обернуть
underlying-ошибку. Полезная алгебра: `throws(any Error)` ≡ `throws`,
`throws(Never)` ≡ не бросает.

```swift
// ХОРОШО: внутренний закрытый домен — парсер строк JSON-стрима foundry
enum StreamParseError: Error {
    case truncatedLine
    case unknownEventType(String)
}

func parseLine(_ line: String) throws(StreamParseError) -> FoundryEvent { ... }

do {
    let event = try parseLine(line)
} catch {
    // error выведен как StreamParseError — возможен исчерпывающий switch
    switch error {
    case .truncatedLine: buffer(line)
    case .unknownEventType(let t): log.warning("unknown event: \(t)")
    }
}
```

### 4.3 Дизайн типа ошибки: enum vs struct

- **enum** — дефолт для внутренних доменов модуля: исчерпывающий матчинг,
  associated values для контекста. Слабость: новый кейс — source-breaking для
  исчерпывающих `switch`.
- **struct** — для *расширяемых* ошибок публичных границ и для паттерна
  «обёрнутая причина» (аналог Kotlin `cause`), который enum'ы делают неуклюже:

```swift
struct ProcessError: Error {
    enum Code { case launchFailed, nonZeroExit(Int32), streamClosed }
    var code: Code
    var underlying: (any Error)?    // wrap-and-rethrow цепочка
    var command: String?
}
```

Рабочий паттерн 2025+: **enum + typed throws внутри модуля; struct или untyped
`any Error` на публичных границах.**

### 4.4 LocalizedError

Пользовательские (alert-worthy) ошибки конформят `LocalizedError` и реализуют
**`errorDescription`** (не `description`!), опционально `failureReason`,
`recoverySuggestion`. Без этого `error.localizedDescription` выдаёт бесполезное
"The operation couldn't be completed. (Module.Error error 0.)".

```swift
extension ProcessError: LocalizedError {
    var errorDescription: String? {
        switch code {
        case .launchFailed: String(localized: "Не удалось запустить foundry.")
        case .nonZeroExit(let c): String(localized: "foundry завершился с кодом \(c).")
        case .streamClosed: String(localized: "Поток событий неожиданно закрылся.")
        }
    }
}
```

Разделять **user-facing** (LocalizedError, алерты) и **диагностические** ошибки
(`CustomStringConvertible`, логи). Log-only ошибки не локализуются.

Никогда не гасить ошибку через `try?`, если её можно хотя бы залогировать.
Swift 6.4 добавляет предупреждение о молча выброшенной ошибке `Task` — компилятор
догоняет это правило (детали — [02](02-swift-concurrency.md)).

---

## 5. Современные фичи: что использовать и когда

### 5.1 Макросы (Swift 5.9+)

- **Потреблять устоявшиеся макросы свободно**: `@Observable` (вместо
  ObservableObject — лучше перф за счёт per-property tracking), `@Test`/`#expect`
  (Swift Testing), `#Predicate`.
- **Писать свой макрос** — только когда extension/protocol/generic не выражают
  задачу, а boilerplate реален (≥3 дублированных нетривиальных места).
- ⚠️ Устарело: «макросы убивают время сборки из-за swift-syntax» — Swift 6.2+
  поставляет **prebuilt swift-syntax** (6.3 расширил на shared macro libraries),
  худший clean-build-штраф ушёл.

### 5.2 Property wrappers

Инструмент для *политики хранения* (`@AppStorage`, кастомные `@Clamped`), но эпоха
энтузиазма прошла: макросы забрали главные кейсы.

⚠️ Устарело: `@Published` + `ObservableObject` — легаси-паттерн; новый код —
`@Observable` (макрос). Детали — [03-swiftui-architecture.md](03-swiftui-architecture.md).

Gotchas: wrapped property не может быть `lazy`; `$`-проекцию в публичных API —
умеренно.

### 5.3 Result builders

*Потреблять* DSL (SwiftUI, RegexBuilder, Swift Charts) — да. *Писать свой* — только
для настоящего декларативного под-языка. Худший инструмент для императивной логики;
диагностика внутри builder-замыканий до сих пор слабое место.

### 5.4 `~Copyable` (noncopyable types)

Compile-time «ровно один владелец» для уникальных ресурсов: файловые дескрипторы,
pipe подпроцесса, one-shot токены. `deinit` у struct выполняется при последнем
использовании; `consuming`/`borrowing` управляют передачей vs временным доступом.

```swift
struct ProcessHandle: ~Copyable {
    private let pid: pid_t
    consuming func terminate() { kill(pid, SIGTERM); discard self }
    deinit { kill(pid, SIGTERM) }   // страховка, если забыли terminate()
}
```

Практика: применять для resource handles и защиты API от misuse; **не** размазывать
по доменным моделям — копируемость и есть то, что делает value types удобными.
Массивов noncopyable-типов пока нет (кроме `InlineArray`).

### 5.5 Generics: `some` vs `any`

Лестница выбора: **конкретный тип → generic constraint / `some` → `any`**.

| | `some P` (opaque) | `any P` (existential) |
|---|---|---|
| Диспетчеризация | статическая | динамическая |
| Боксинг | нет | 3-word inline buffer, иначе heap |
| Гетерогенные коллекции | нет | да |
| Дефолт для | параметров и return-типов | type-erased хранения, плагинов |

- Swift 6 требует явный `any`: голое имя протокола как тип — ошибка (SE-0335).
- Экзистенциалы **авто-открываются** при передаче в generic-функции (SE-0352):
  хранить `[any EventHandler]`, обрабатывать через `func process(_ h: some EventHandler)` —
  компонуется хорошо.
- Primary associated types (`any Collection<Int>`, `some AsyncSequence<FoundryEvent, Never>`) —
  вместо обёрток-стирателей типов. ⚠️ Устарело: `AnyPublisher`-стиль
  type-erasure-обёрток — легаси вне Combine.
- Перф: existential-вызовы стоят динамической диспетчеризации + возможной
  heap-аллокации — в горячих циклах измеримо. Но читаемость первична: не
  выворачивать код ради бокса, срабатывающего 10 раз в минуту.

### 5.6 InlineArray / Span / Mutex (Swift 6.0–6.2)

- `InlineArray<N, T>` — fixed-size inline-хранение, без heap и CoW (§2.2).
- `Span` / `MutableSpan` — безопасные borrowed-views над непрерывной памятью;
  замена `withUnsafeBufferPointer`-паттернам.
- `Mutex<T>` (модуль `Synchronization`, Swift 6.0) — синхронный лок вокруг значения;
  правильный способ сделать класс `Sendable` без `@unchecked`:

```swift
final class EventCounter: Sendable {
    private let count = Mutex(0)
    func increment() -> Int { count.withLock { $0 += 1; return $0 } }
}
```

⚠️ Устарело: `NSLock` / `os_unfair_lock` / `DispatchQueue` как мьютекс + 
`@unchecked Sendable` — новый код использует `Mutex<T>`. Когда `Mutex`, а когда
`actor` — [02-swift-concurrency.md](02-swift-concurrency.md).

### 5.7 Parameter packs (`repeat each T`)

Фича библиотечных авторов (variadic generics). В app-коде почти не пишется —
достаточно узнавать синтаксис на ревью.

---

## 6. Память: ARC

### 6.1 Основы

ARC действует на классы, замыкания, акторы — не на struct/enum (кроме их полей
класс-типа). Retain cycle требует **двух** ссылок класс-типа друг на друга; лечится
превращением одной в `weak` или `unowned`:

- **`weak`** — optional, авто-nil. **Дефолт**, если нельзя доказать инвариант времени
  жизни. Цена — распаковка optional.
- **`unowned`** — non-optional, **trap** если объект умер. Только при гарантированном
  инварианте (child → parent, где parent владеет child). Краш `unowned` — это
  production-инцидент; экономия на распаковке его не окупает.
- Swift 6.2+ (SE-0481): **`weak let`** — иммутабельная weak-ссылка; предпочитать
  `weak var`, если не переприсваивается (заодно разблокирует `Sendable`).
- Делегаты: `weak var delegate: (any FooDelegate)?`, протокол с `AnyObject`-constraint —
  канон без изменений.

### 6.2 Capture lists

Ключевое отличие от Kotlin: замыкания захватывают **переменные по ссылке**, если
переменная не указана в capture list — а capture list **копирует в момент создания**
замыкания:

```swift
// Захват по ссылке — увидит финальное значение i
var handlers: [() -> Void] = []
for i in 0..<3 { handlers.append { print(i) } }        // тут ок: i — копия итерации

var total = 0
let f = { print(total) }   // по ссылке: увидит будущие изменения total
let g = { [total] in print(total) }  // копия на момент создания
```

Правила:

- Non-escaping замыкания (`map`, `filter`) захватывают `self` свободно — цикл
  невозможен, `[weak self]` там — шум.
- Escaping-замыкание, **сохранённое в self** и захватывающее `self`, — цикл;
  паттерн: `[weak self]` + `guard let self else { return }` (после распаковки
  `self.` можно опускать, Swift 5.8+).
- Часто лучше захватить только нужное: `[id = session.id]` вместо weak-self-танцев.

### 6.3 Task и `[weak self]` — где карго-культ, а где нужно

Уточнённые правила 2025–26 (важно: LLM и старые статьи ставят `[weak self]`
рефлекторно — это карго-культ):

1. **`Task` удерживает захваты до завершения** — это *временная* strong-ссылка,
   не цикл: Task отпускает замыкание по завершении. Для короткой one-shot задачи
   `[weak self]` меняет только то, умрёт ли `self` на сотни миллисекунд раньше.
   Обычно — шум.
2. **Цикл возникает, только если `self` хранит task** (`self.task = Task { ... self ... }`)
   **и task никогда не завершается.** Опасный случай — бесконечные циклы и вечное
   потребление AsyncSequence.
3. **Для долгоживущих for-await-циклов** — `[weak self]` с распаковкой **на каждой
   итерации** (не `guard let self` один раз сверху — это пришпилит self на всю жизнь
   цикла):

```swift
// ХОРОШО: подписка на стрим событий подпроцесса foundry
streamTask = Task { [weak self] in
    for await event in eventStream {
        guard let self else { return }   // проверка каждую итерацию
        self.apply(event)
    }                                    // между итерациями self не удерживается
}

// ПЛОХО: pin self на всю жизнь стрима
streamTask = Task { [weak self] in
    guard let self else { return }
    for await event in eventStream { self.apply(event) }
}
```

4. **Cancellation — инструмент управления памятью**: отмена task заставляет async-API
   бросить `CancellationError`, раскручивает замыкание и освобождает захваты.
   Хранить task и отменять в `deinit` / lifecycle-событии часто чище weak-self-гимнастики.
5. SwiftUI: view — структуры, capture-паранойя внутри `body` неуместна. Реальные
   риски — `@Observable`-классы, хранящие tasks/замыкания с `self`; таймеры;
   NotificationCenter. Предпочитать `.task {}`-модификатор (авто-отмена по
   исчезновению) вместо `Task {}` в `onAppear`.
6. Незарезюмленный `withCheckedContinuation` держит весь подвешенный стек — это
   утечка и подвисание одновременно (→ [02](02-swift-concurrency.md)).

Проверка: Memory Graph Debugger + deinit-логирование в debug; Instruments Leaks
не видит abandoned-but-reachable память. Именование задач (`Task(name:)`, 6.2)
делает утёкшие tasks видимыми в Instruments.

---

## 7. Организация кода

### 7.1 Extensions

Доминирующая конвенция — **один протокол-конформанс на extension**:

```swift
struct ReviewArtifact { /* stored properties + core init */ }

extension ReviewArtifact: Codable { }
extension ReviewArtifact: CustomStringConvertible {
    var description: String { "artifact \(id) (\(state))" }
}

// MARK: - Private helpers
private extension ReviewArtifact {
    func validatePaths() throws { ... }
}
```

Синтез `Equatable`/`Hashable`/`Codable` работает в same-file extension. Extensions
также выражают: группировку фич в больших типах, минимальный API на чужих типах,
constrained extensions (`extension Collection where Element: Numeric`).

**Критичный gotcha диспетчеризации** (см. также §8): метод, определённый в
protocol extension, но **не объявленный как requirement протокола**, диспетчеризуется
**статически** — реализация конформящего типа не будет вызвана через
протокол-типизированную ссылку. Все точки кастомизации объявлять requirements.

```swift
protocol EventSink {
    func handle(_ e: FoundryEvent)
    func flush()                       // requirement → динамическая диспетчеризация
}
extension EventSink {
    func flush() { }                   // default для requirement — ок
    func handleBatch(_ es: [FoundryEvent]) { es.forEach(handle) }  // НЕ requirement → статика!
}
```

### 7.2 Access control — самый узкий работающий

| Уровень | Область |
|---|---|
| `private` | Декларация **+ её extensions в том же файле** (правило после Swift 4 — поэтому `fileprivate` почти не нужен) |
| `fileprivate` | Весь файл; легитимен только для кооперации нескольких типов в одном файле |
| `internal` | Дефолт; весь модуль |
| `package` (SE-0386, 5.9) | Все модули **внутри одного SwiftPM-пакета** — ключевой инструмент мульти-модульных приложений: делить внутренности между `Domain` / `DomainTestSupport` без `public` |
| `public` | Виден извне модуля, subclass/override запрещены |
| `open` | + subclass/override извне; классы — `public final`, пока наследование не спроектировано |

- `private(set) var` для read-mostly состояния вместо отдельных геттеров.
- В библиотеках: явный модификатор на каждой публичной декларации;
  `internal import` (SE-0409) для не-протекающих зависимостей.

### 7.3 Файлы и структура

- Один основной тип на файл, файл по имени типа: `SessionRunner.swift`.
- Extension-файлы: `TypeName+Purpose.swift` (`FoundryEvent+Codable.swift`).
- Организация **по фичам, а не по видам**: `Features/Review/…` лучше, чем корзины
  `Models/ ViewModels/ Views/`. Масштабирование — мульти-таргетные SwiftPM-пакеты
  по слоям с `package`-ACL. Xcode 26 buildable folders синхронизированы с диском —
  старой боли groups-vs-folders больше нет.
- `// MARK: -` внутри файлов; ориентиры SwiftLint: file_length ~400–500,
  type_body_length — по дефолтам.
- Тесты зеркалят пути исходников; фреймворк нового кода — **Swift Testing**
  (`@Test`, `#expect`), не XCTest (→ [07-testing-quality.md](07-testing-quality.md)).

---

## 8. Kotlin → Swift: маппинг и ловушки

Раздел для ревью Swift-кода глазами Kotlin-инженера: слева — привычная конструкция,
справа — эквивалент и чем он коварен.

### 8.1 Таблица соответствий

| Kotlin | Swift | Ловушка / примечание |
|---|---|---|
| `data class` | `struct` + synthesized `Equatable`/`Hashable`/`Codable` | **Value-семантика!** `var b = a; b.x = 1` не трогает `a`; `copy()` не нужен. `componentN` нет — деструктуризация через кортежи/паттерны |
| `class` (final by default) | `final class` | Оба final-by-default. Swift `open` ≈ Kotlin `open`, но только cross-module |
| `sealed class` / `sealed interface` | `enum` с associated values | Исчерпывающий `switch` ≈ исчерпывающий `when`. Payload: `case success(Data)` → `case .success(let d)`. Sealed-иерархия с общими полями и подтипами → enum + computed properties |
| `object` (singleton) | caseless `enum` + statics, или `static let shared` | `static let` — lazy и потокобезопасен (как `by lazy`). Мутабельные statics в Swift 6 обязаны быть isolated/Sendable |
| `companion object` | `static` члены | `static func` / `static let` прямо на типе |
| `interface` с default-методами | `protocol` + protocol extension | **Ловушка №1**: не-requirement методы extension диспетчеризуются статически; Kotlin default-методы — всегда виртуальны (§7.1) |
| `fun interface` / лямбды | замыкания | Trailing closure ≈ trailing lambda. Вместо `it` — `$0` |
| Extension functions | `extension Type { }` | Разрешение статическое в обоих языках. Extensions могут добавлять конформансы; stored-свойств — нет |
| `T?` / `null` | `Optional<T>` / `T?` | `!!` → `!` (см. §3 — почти всегда запрещён); элвис `?:` → `??`; `lateinit var` → **не** `T!`, а инъекция через init |
| `when` | `switch` (+ `where`, кортежи, диапазоны) | Swift `switch` исчерпывающий **всегда** (Kotlin — только для выражений). Fallthrough по умолчанию нет. Паттерн-матчинг богаче |
| unchecked exceptions | `throws` — «checked-ish» | `try` обязателен на call site, `throws` — часть сигнатуры. Untyped по умолчанию; typed `throws(E)` — опционально (§4.2) |
| `Result<T>` | `Result<T, E: Error>` | Типизирован по ошибке; на границах, не для control flow |
| `suspend fun` | `async func` | `await` **обязателен у каждой** точки подвешивания — Kotlin прячет suspension points, Swift маркирует. Подробно — [02](02-swift-concurrency.md) |
| `CoroutineScope` + `launch` | `async let` / `TaskGroup`; unstructured — `Task { }` | Scope-объекта нет — структура из синтаксиса. `viewModelScope.launch` ≈ хранить `Task` + отмена в deinit, или `.task {}` в SwiftUI |
| `Dispatchers.Main` | `@MainActor` | Изоляция **декларируется на API/типах**, а не выбирается в точке вызова — главный ментальный сдвиг |
| `Dispatchers.Default/IO` | `@concurrent` async funcs / actors | Пул один, кооперативный. **Никогда не блокировать** в async-коде — `runBlocking`-эквивалента нет |
| `Mutex` / `synchronized` | `actor` (async) или `Mutex<T>` (sync) | **Ловушка №2**: actor ≠ `Mutex.withLock` — reentrancy на каждом `await` (→ [02](02-swift-concurrency.md)) |
| `Flow` (cold) | `AsyncSequence` | `collect` ≈ `for await`. Операторы — swift-async-algorithms |
| `StateFlow` / `SharedFlow` (hot) | `@Observable` + `Observations` / `AsyncStream` | `AsyncStream` — **single-consumer** (SharedFlow — multicast!) |
| `callbackFlow` | `AsyncStream { continuation in }` | `awaitClose { }` ≈ `continuation.onTermination = { }` — забыть = утечка продьюсера в обоих мирах |
| `Job.cancel()` / `ensureActive()` | `task.cancel()` / `try Task.checkCancellation()` | Оба кооперативны. `CancellationError` не глотать — как и `CancellationException` |
| `withTimeout` | нет в stdlib | Гонка через `TaskGroup` или пакет — известный пробел |
| `by lazy` | `lazy var` | **`lazy var` НЕ потокобезопасен** (Kotlin-дефолт — безопасен). `static let` — потокобезопасно-lazy |
| Delegation `by` | нет фичи языка | Ручной форвардинг, protocol extensions, макросы. `by observable` → property wrappers / `@Observable` + `didSet` |
| Named/default args | default parameter values | **Метки аргументов — часть имени функции**, обязательны по умолчанию (у Kotlin — опция вызывающего) |
| `inline fun` + `reified` | генерики reified-ish из коробки | **Стирания нет**: `T.self`, `is T` работают без `reified`. Но `any P` боксится, а динамические касты — медленный путь |
| `"$x"` шаблоны | `"\(x)"` | Интерполяция расширяема (`ExpressibleByStringInterpolation`) |
| `listOf` / `mapOf`, `List` vs `MutableList` | литералы `Array`/`Dictionary` | **Все коллекции — value types** (CoW). Мутабельность — из `let` vs `var`, а не из типа |
| `?.let { }` | `if let` / chaining | `x?.let { use(it) }` → `if let x { use(x) }`. Для side effects — явный `if let`, не `map` |
| `apply`/`also`/`run`/`with` | нет | Scope-функций нет; идиоматично — обычные statements, `var`-копии. Не тащить `then`-пакеты |
| `@JvmStatic` и т.п. | атрибуты `@objc`, `@inlinable`… | Макросы (`@Observable`) ≈ KSP-кодогенерация, но проверяются компилятором |

### 8.2 Что кусает Kotlin-инженера сильнее всего

1. **Value-семантика везде.** `var b = a` для struct/массива/словаря — *копия*.
   И наоборот: `let order = order` замораживает **все** `var`-поля структуры —
   в отличие от Kotlin `val`, держащего мутабельный объект. Инстинкт «пошарить
   мутабельный list» превращается в «передавай копии или заведи reference
   type/actor осознанно».

```swift
let events = [e1, e2]
// events.append(e3)         // не компилируется: let-массив глубоко иммутабелен

struct Config { var retries: Int }
let config = Config(retries: 3)
// config.retries = 5        // не компилируется: let замораживает var-поля
```

2. **`mutating`-методы** — методы struct не могут мутировать `self` по умолчанию;
   на `let`-значении их не вызвать. Аналога в Kotlin нет.
3. **Подвешивание видно, изоляция декларируется.** Каждая точка interleaving — явный
   `await`; *где* исполняется код — свойство декларации (`@MainActor`, actor,
   `@concurrent`), а не точки вызова (`withContext`). Под дефолтами Swift 6.2
   app-модуль исполняется на main actor, пока не сказано иное (→ [02](02-swift-concurrency.md)).
4. **Actor reentrancy** — методы actor могут interleave на каждом `await`;
   `Mutex.withLock` в Kotlin так не делает. После каждого `await` перепроверять
   инварианты (→ [02](02-swift-concurrency.md)).
5. **Диспетчеризация protocol extensions** статична для не-requirements (§7.1) —
   источник багов «почему мой override не вызвался». Kotlin default-методы всегда
   виртуальны.
6. **`@unknown default`** для non-frozen enums из библиотек — исчерпывающий
   `switch` по чужому enum требует его (как sealed `else`, но с подсказкой компилятора).
7. **Ошибка в `Task` не роняет ничего** — она молча сохраняется в task (до warning
   в 6.4). Kotlin: uncaught в `launch` падает по умолчанию. Всегда
   `try await task.value` или обработка внутри (→ [02](02-swift-concurrency.md)).
8. **Генерики не стёрты.** `func f<T>(_ t: T)` умеет `T.self`, массивы `T`;
   разрешение перегрузок — на компиляции. Но `any P` боксится — §5.5.
9. **Инициализация строгая**: definite initialization, двухфазный init классов,
   `convenience`/`designated`. `lateinit`-паттерны перепроектировать, а не
   эмулировать через `T!`.
10. **Строки**: `String` — value type над grapheme clusters. `count` — O(n),
    `s[0]` не компилируется. UTF-16-индексные привычки не переносятся; для
    парсинга байтового стрима работать с `Data`/`UTF8View`, не `String`-индексами.

### 8.3 Чек «запахов Kotlin-акцента» в Swift-коде

На ревью это маркеры того, что код писался «по-котлински»:

- class там, где хватило бы struct; отсутствие `final` у классов.
- `T!` как замена `lateinit`.
- Своя обёртка `Result` в сигнатурах async-функций вместо `throws`.
- Getter-методы `getFoo()` вместо computed property `foo`.
- Пропущенные argument labels («positional» вызовы через `_`-метки без причины).
- `if x != nil { use(x!) }` вместо `if let`.
- Эмуляция scope-функций (`apply`-подобные обёртки).
- `class Constants { companion ... }`-стиль вместо caseless `enum` или statics.
- Ручные `equals`/`hashCode`-аналоги там, где работает синтез.

---

## Чеклист ревью

- [ ] Новые типы — `struct`/`enum`? Каждый `class` обоснован (identity, interop,
  deinit-lifetime) и помечен `final`?
- [ ] Имена следуют API Design Guidelines: вызов читается как фраза, метки аргументов
  расставлены по правилам, Bool — утверждение, mutating/nonmutating пары корректны?
- [ ] `Equatable`/`Hashable`/`Codable` синтезированы, а не написаны руками? Кастомные
  ключи — через `CodingKeys`, а не ручной `encode`/`decode`?
- [ ] `Identifiable`-ID стабильный доменный, не `UUID()` в init?
- [ ] Нет `!`, `try!`, `as!`, `T!` без комментария-обоснования «nil = баг программиста»?
- [ ] `guard let` для предусловий, shorthand `if let x`, нет `if x != nil` + `x!`?
- [ ] Ошибки: untyped `throws` по умолчанию; typed `throws(E)` только для закрытых
  внутренних доменов? Нет `try?`, глотающего ошибку, которую стоило залогировать?
- [ ] User-facing ошибки конформят `LocalizedError` с `errorDescription`?
- [ ] `some` предпочтён `any`, где нет нужды в гетерогенности? Все экзистенциалы
  помечены явным `any`?
- [ ] `weak` vs `unowned`: `unowned` только с доказанным инвариантом времени жизни?
- [ ] `[weak self]` не карго-культ: в one-shot Task его нет; в вечных for-await-циклах
  есть и распаковывается на каждой итерации?
- [ ] Точки кастомизации протоколов объявлены requirements (не только в extension)?
- [ ] Access control — самый узкий; `package` для кросс-модульных внутренностей пакета;
  `private(set)` для read-mostly?
- [ ] Один конформанс на extension; файлы по фичам; `TypeName+Purpose.swift`?
- [ ] Нет «Kotlin-акцента» из §8.3?
- [ ] Конкурентность (Task, actor, Sendable, изоляция) — проверена по чеклисту
  [02-swift-concurrency.md](02-swift-concurrency.md)?

---

## Источники

- [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
- [Choosing between structures and classes](https://developer.apple.com/documentation/swift/choosing-between-structures-and-classes) — Apple
- [Swift 6.2 released](https://www.swift.org/blog/swift-6.2-released/) · [Swift 6.3 released](https://www.swift.org/blog/swift-6.3-released/) — swift.org
- [SE-0413 Typed throws](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0413-typed-throws.md)
- [SE-0345 `if let` shorthand](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0345-if-let-shorthand.md)
- [SE-0335 Existential `any`](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0335-existential-any.md)
- [SE-0390 Noncopyable structs and enums](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0390-noncopyable-structs-and-enums.md)
- [Designing APIs with typed throws](https://www.donnywals.com/designing-apis-with-typed-throws-in-swift/) — Donny Wals
- [Type-safe and user-friendly error handling in Swift 6](https://theswiftdev.com/2025/type-safe-and-user-friendly-error-handling-in-swift-6/) — The.Swift.Dev
- [Protocols as existential types vs generic constraints](https://yakovmanshin.com/2025/12/protocols-as-existential-types-vs-generic-constraints/) — Yakov Manshin
- [Noncopyable types in Swift](https://nilcoalescing.com/blog/NoncopyableTypesInSwift/) — Nil Coalescing
- [How to use weak self in Swift concurrency tasks](https://www.donnywals.com/how-to-use-weak-self-in-swift-concurrency-tasks/) — Donny Wals
- [Memory management when using async/await](https://www.swiftbysundell.com/articles/memory-management-when-using-async-await/) — Swift by Sundell
- [Async tasks memory management](https://tanaschita.com/swift-async-tasks-memory-management/) — tanaschita
- [When do you really need weak self](https://www.swiftwithvincent.com/blog/when-do-you-really-need-to-use-weak-self) — Vincent Pradeilles
- [Kotlin-Swift interopedia](https://github.com/kotlin-hands-on/kotlin-swift-interopedia)
- [Interop: coroutines ↔ Swift](https://kt.academy/article/interop-coroutines-swift) — Kt. Academy
