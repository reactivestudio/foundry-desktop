# 02 · Swift 6: конкурентность

> Серия practices · [оглавление](README.md)

Целевая версия: **Swift 6.3, Xcode 26**, Swift 6 language mode + семантика
Swift 6.2 «Approachable Concurrency». Это самая горячая зона устаревших паттернов:
LLM и статьи до 2025 года тащат догмы, которые **больше не верны** — они собраны
в §2 и помечены по тексту.

Язык и память вне конкурентности — [01-swift-language.md](01-swift-language.md).
SwiftUI-специфика (`.task`, `@Observable`) — [03-swiftui-architecture.md](03-swiftui-architecture.md).

---

## 1. Модель в одном абзаце

Swift 6 language mode делает data races **ошибками компиляции**. Код исполняется в
изоляционных доменах: конкретные акторы, глобальные акторы (`@MainActor` — главный)
и nonisolated. Всё, что пересекает границу изоляции, должно быть `Sendable` — либо
доказанно «отсоединено» region-based-анализом (SE-0414) или помечено `sending`
(SE-0430). Swift 6.2 развернул эргономику: **новые app-таргеты по умолчанию
`@MainActor` на весь модуль** (SE-0466), а `nonisolated async`-функции **исполняются
на акторе вызывающего** (SE-0461) — конкурентность стала opt-in, а не случайной.

---

## 2. Swift 6.2 «Approachable Concurrency» — новые дефолты

Два ортогональных build-сеттинга (Xcode 26 / SwiftPM):

| Сеттинг | Что делает | Кому включать |
|---|---|---|
| `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (SE-0466; SwiftPM: `.defaultIsolation(MainActor.self)`) | Каждая неаннотированная декларация модуля — неявно `@MainActor` | App-таргеты и UI-модули. **Не** для библиотек/доменных модулей |
| `SWIFT_APPROACHABLE_CONCURRENCY = YES` | Зонтик: `NonisolatedNonsendingByDefault` (SE-0461), `InferIsolatedConformances`, `InferSendableFromCaptures`… | Все таргеты, включая пакеты |

Новые проекты Xcode 26 получают оба по умолчанию; существующие проекты и пакеты —
нет (нужно включить руками).

**SE-0461, суть:** `nonisolated async`-функция теперь бежит на акторе **вызывающего**,
а не сваливается на глобальный конкурентный пул. Уйти с актора — только явно:

- **`@concurrent`** — «всегда исполняться на глобальном конкурентном executor»
  (требует `nonisolated`). Для CPU-тяжёлой работы: парсинг, диффы, крипто.
- **`nonisolated(nonsending)`** — явное написание нового дефолта; пишется редко
  (миграция, авторы API).

```swift
// Модуль app: default isolation = MainActor
@Observable
final class SessionViewModel {            // неявно @MainActor
    private(set) var transcript: [FoundryEvent] = []

    func append(_ raw: Data) async throws {
        let event = try await Self.decode(raw)   // ушли с main, вернулись — UI-state трогаем безопасно
        transcript.append(event)
    }

    @concurrent
    nonisolated static func decode(_ raw: Data) async throws -> FoundryEvent {
        try JSONDecoder().decode(FoundryEvent.self, from: raw)   // off-main
    }
}
```

### ⚠️ Устарело: догмы, которые больше не верны

| Старая догма (до 6.2, всё ещё в статьях и в выдаче LLM) | Реальность под дефолтами 6.2+ |
|---|---|
| «`await` в nonisolated async-функции означает, что ты ушёл с main» | **Нет.** Она бежит на акторе вызывающего. Off-main — только `@concurrent` или actor |
| «Вынеси тяжёлую работу в nonisolated async func — она сама уйдёт в фон» | **Нет.** Вызванная с MainActor — исполнится на MainActor. Нужен `@concurrent` |
| «`Task.detached` — способ уйти с MainActor» | Легаси-приём: detached теряет priority/task-locals. Новый код — `@concurrent`-функции |
| «Помечай `@MainActor` каждый view model / каждый UI-метод» | В app-модуле с MainActor-default аннотации не нужны — это дефолт |
| «Sendable-ошибки чинят через `@unchecked Sendable`» | Сначала: region isolation / `sending` / `Mutex<T>` / actor. `@unchecked` — последнее средство |
| «`DispatchQueue.main.async { }` для хопа на main» | `Task { @MainActor in }` / `await MainActor.run { }` / аннотация функции |
| «Синглтон = `static let shared` + внутренние DispatchQueue-барьеры» | `actor`, или `final class` + `Mutex<T>`, или `@MainActor` |
| «`withTaskGroup(of: Foo.self)` обязателен» | Тип результата выводится (6.0+) |

### Рекомендованная конфигурация foundry-desktop

- **App-таргет**: `defaultIsolation = MainActor` + Approachable Concurrency = YES.
  UI, view models, оркестрация сессий — всё живёт на MainActor без аннотаций.
- **Фоновая работа** (парсинг JSON-стрима, диффы артефактов, файловый I/O):
  `@concurrent nonisolated`-функции или выделенные акторы (например,
  `actor ProcessSupervisor` для управления подпроцессами foundry/claude).
- **Пакеты/доменные модули** (если появятся): Approachable Concurrency = YES,
  но default isolation = `nonisolated` — MainActor-default в библиотеке меняет
  изоляцию её публичного API.

---

## 3. Sendable

`Sendable` = безопасно пересекает границы изоляции.

- Struct/enum из Sendable-частей — неявно Sendable внутри модуля; на public-типах
  объявлять явно.
- Класс — только `final` + все stored `let` Sendable-типов. С 6.2 (SE-0481) есть
  **`weak let`** — класс с weak-ссылкой может быть Sendable без `@unchecked`.
- `@unchecked Sendable` — «поверь, компилятор»: допустим только для типов с
  внутренней синхронизацией; в новом коде вместо самодельных локов — `Mutex<T>`:

```swift
import Synchronization

final class EventLog: Sendable {
    private let lines = Mutex<[String]>([])
    func append(_ line: String) { lines.withLock { $0.append(line) } }
}
```

- **`sending`** (SE-0430): параметр/результат «передаётся, вызывающий теряет
  владение» — позволяет non-Sendable значениям пересекать границы. Встречается в
  `Task.init`, `AsyncStream.Continuation.yield`. Предпочитать `sending` вместо
  навешивания `Sendable` на всё подряд при передаче владения.
- **Region-based isolation** (SE-0414): компилятор отслеживает «регионы» — свежесозданное
  non-Sendable значение без других ссылок можно отправить через границу без Sendable.
  Явно не вызывается, но объясняет, почему `let parser = Parser(); await actor.use(parser)`
  компилируется, а тот же код с второй ссылкой на `parser` — нет (вторая ссылка
  «сливает регионы» и блокирует отправку).

---

## 4. Акторы

### 4.1 Когда актор

`actor` — reference type с сериализованным доступом к мутабельному состоянию;
внешние вызовы — через `await`. Использовать для **действительно разделяемого
мутабельного состояния как сервиса**: реестр запущенных подпроцессов, кэш, менеджер
соединений. **Не** делать актором всё подряд: каждый вызов — hop с латентностью,
плюс реентерабельность.

Выбор инструмента для shared state:

| Состояние | Инструмент |
|---|---|
| UI / оркестрация | `@MainActor` (в app-модуле — дефолт) |
| Сервис с async-операциями | `actor` |
| Маленькое sync-состояние (счётчик, кэш-словарь) | `final class` + `Mutex<T>` |
| Подсистема из многих типов с одним доменом сериализации | кастомный `@globalActor` (нужен ≤1 на приложение) |

### 4.2 Реентерабельность — баг №1 реальных акторов

На **каждом `await` внутри метода актора** другие вызовы могут проникнуть и изменить
состояние. Актор защищает от data races, **не** от interleaving.

```swift
actor ProcessSupervisor {
    private var running: [SessionID: ProcessHandle] = [:]

    // ПЛОХО: между guard и записью — await; второй вызов launch(id) для того же id
    // пройдёт guard и запустит второй процесс
    func launch(_ id: SessionID) async throws {
        guard running[id] == nil else { return }
        let handle = try await Process.start(foundryCommand(for: id))   // точка interleaving!
        running[id] = handle
    }

    // ХОРОШО: инвариант фиксируется ДО await — in-flight Task как placeholder
    private var launching: [SessionID: Task<ProcessHandle, Error>] = [:]
    func launchDeduped(_ id: SessionID) async throws -> ProcessHandle {
        if let handle = running[id] { return handle }
        if let inFlight = launching[id] { return try await inFlight.value }
        let task = Task { try await Process.start(foundryCommand(for: id)) }
        launching[id] = task                       // синхронно, до первого await
        defer { launching[id] = nil }
        let handle = try await task.value
        running[id] = handle
        return handle
    }
}
```

Правила: перепроверять инварианты после каждого `await`; выносить критические
секции в синхронные методы без `await`; для кэшей — дедупликация через in-flight `Task`.

**Для Kotlin-инженера:** это главное отличие от `Mutex.withLock` — Kotlin-лок держится
через suspension, актор — нет. Актор ближе к single-threaded confinement с
кооперативной многозадачностью внутри.

### 4.3 @MainActor и nonisolated

- `@MainActor` — глобальный актор главного потока: UI, view models, всё, что трогает
  AppKit/SwiftUI. Применяется к типам, членам, замыканиям, целым модулям (6.2).
- `nonisolated` выводит член из изоляции типа — для чистых функций и доступа к
  иммутабельному (например, конформанс `@MainActor`-типа к `Codable`/`Hashable`).
  С 6.1 (SE-0449) применяется к целым типам и extensions.
- **Isolated conformances** (SE-0470, 6.2): `extension Model: @MainActor Equatable` —
  конформанс, доступный только на MainActor. Решает старую боль «@MainActor-тип
  не может конформить синхронный протокол».

---

## 5. Структурированная конкурентность

### 5.1 async let — фиксированное число независимых детей

```swift
async let transcript = loadTranscript(sessionID)
async let artifacts = loadArtifacts(sessionID)
let review = try await ReviewContext(transcript: transcript, artifacts: artifacts)
// оба ребёнка awaited; при throw — авто-отмена второго
```

### 5.2 TaskGroup — динамический fan-out

```swift
let diffs = try await withThrowingTaskGroup { group in   // тип результата выводится (6.0+)
    for artifact in artifacts {
        group.addTask { try await computeDiff(artifact) } // дети наследуют priority, НЕ изоляцию
    }
    var out: [ArtifactDiff] = []
    for try await diff in group { out.append(diff) }      // в порядке завершения!
    return out
}
```

- Результаты приходят **в порядке завершения**, не подачи — если порядок важен,
  возвращать `(index, result)`.
- Ограничение параллелизма — «sliding window»: добавить N задач, дальше по одной
  на каждый `group.next()`.
- `withThrowingDiscardingTaskGroup` — для fire-and-forget-серверных нагрузок без сбора.

### 5.3 Иерархия предпочтений

**Structured > unstructured > detached:**

| | Наследует | Lifetime |
|---|---|---|
| `async let` / TaskGroup | priority, task-locals, cancellation, изоляцию контекста | не переживает scope |
| `Task { }` | изоляцию актора, priority, task-locals | **твоя ответственность** |
| `Task.detached { }` | **ничего** | твоя ответственность |

⚠️ Устарело: `Task.detached` для «уйти в фон» — в новом коде это `@concurrent`-функция.
Detached остаётся для крайне редкого «не наследовать вообще ничего».

`Task { }` легитимен как **мост из синхронного мира в async** (обработчик кнопки,
делегат) — но см. §6 про хранение и §9 про проглоченные ошибки.

---

## 6. Task: lifecycle и cancellation

- Отмена **кооперативна**: ничего не останавливается само. Проверять
  `try Task.checkCancellation()` (бросает `CancellationError`) или `Task.isCancelled`
  на границах итераций / перед дорогими фазами. Async-API stdlib/Foundation
  (URLSession, `Task.sleep`) проверяют сами.
- Дети структурированных scope отменяются автоматически при выходе/throw scope.
- Свои unstructured tasks — **хранить и отменять**:

```swift
@Observable
final class StreamController {                  // @MainActor через дефолт модуля
    private var streamTask: Task<Void, Never>?

    func start(_ stream: AsyncStream<FoundryEvent>) {
        streamTask?.cancel()
        streamTask = Task(name: "foundry-stream") { [weak self] in   // имя — видно в Instruments (6.2)
            for await event in stream {
                guard let self else { return }
                self.apply(event)
            }
        }
    }

    deinit { streamTask?.cancel() }
}
```

- Отмена — ещё и инструмент управления памятью: раскручивает замыкание, освобождает
  захваты (правила `[weak self]` — [01 §6.3](01-swift-language.md)).
- В SwiftUI — модификатор `.task(id:)`: авто-отмена при исчезновении view и смене id;
  убирает бо́льшую часть ручного хранения задач ([03](03-swiftui-architecture.md)).
- `withTaskCancellationHandler(operation:onCancel:)` — мост к некооперативной работе
  (отмена URLSessionTask, kill подпроцесса). Handler может выполниться **немедленно**
  (в т.ч. до начала operation, если уже отменено).
- Приоритет задаётся при создании (`Task(priority: .userInitiated)`); эскалация
  происходит автоматически, когда высокоприоритетная задача ждёт вашу.
- Не глотать `CancellationError` — как `CancellationException` в Kotlin: пробрасывать,
  не логировать как сбой.

---

## 7. AsyncSequence / AsyncStream

### 7.1 Потребление

`for try await x in seq { }`. Цикл по бесконечной последовательности — обязательство
на весь lifetime задачи и retention захватов: `[weak self]` + распаковка на итерации
([01 §6.3](01-swift-language.md)).

### 7.2 AsyncStream — мост из callback-мира

Канонический паттерн проекта — стрим JSON-событий из stdout подпроцесса:

```swift
func events(from process: Process, pipe: Pipe) -> AsyncStream<FoundryEvent> {
    AsyncStream(bufferingPolicy: .unbounded) { continuation in   // политику выбрать осознанно!
        pipe.fileHandleForReading.readabilityHandler = { handle in
            for line in handle.availableData.splitLines() {
                if let event = try? FoundryEvent(jsonLine: line) {
                    continuation.yield(event)
                }
            }
        }
        process.terminationHandler = { _ in continuation.finish() }
        continuation.onTermination = { _ in                       // ВСЕГДА реализовывать
            pipe.fileHandleForReading.readabilityHandler = nil
            if process.isRunning { process.terminate() }
        }
    }
}
```

Железные правила:

1. **`onTermination` — всегда** (срабатывает на cancel и на `break` из цикла);
   забыть = утечка продьюсера. Аналог `awaitClose` в `callbackFlow`.
2. **Buffering policy — осознанно**: unbounded-дефолт — memory-риск при быстром
   продьюсере; для «последнее состояние» — `.bufferingNewest(1)`.
3. **Single-consumer ловушка**: голый `AsyncStream` — НЕ broadcast. Второй
   `for await` по тому же стриму молча получает лишь часть элементов (значения
   разбираются потребителями наперегонки). **Для Kotlin-инженера:** это не
   `SharedFlow`; multicast — через `share()` из swift-async-algorithms (2025) или
   actor-fan-out.
4. Элементы стрима держать `Sendable` — non-Sendable элементы из другой изоляции
   дают самые невнятные `sending`-ошибки.

### 7.3 Операторы и Observations

- **swift-async-algorithms** — штатный набор 2026: `debounce`, `merge`, `zip`,
  `combineLatest`, `chain`, `share`. Не писать операторы руками.
  ⚠️ Устарело: Combine для новых реактивных пайплайнов.
- **`Observations`** (SE-0475, 6.2): async-последовательность транзакционных
  изменений `@Observable`-состояния — `Observations { model.status }` — современная
  замена KVO/`objectWillChange`. Ближайший аналог `StateFlow`-подписки.

---

## 8. Continuations — мост из completion-handler API

```swift
func waitForExit(_ process: Process) async -> Int32 {
    await withCheckedContinuation { continuation in
        process.terminationHandler = { p in
            continuation.resume(returning: p.terminationStatus)
        }
    }
}
```

Железные правила:

- **Resume ровно один раз на каждом пути.** Классика тихого зависания — путь
  `(nil, nil)` из ObjC-бриджей: обрабатывать явно.
- **Только checked-варианты** (`withCheckedContinuation` / `withCheckedThrowingContinuation`):
  double-resume — trap, утечка — warning. `withUnsafe...` — лишь когда профайлер
  доказал стоимость проверки (почти никогда).
- Незарезюмленный continuation = утечка всего подвешенного стека + вечный `await`.
- Отменяемость — оборачивать в `withTaskCancellationHandler`, resume с
  `CancellationError` из handler'а ровно один раз (флаг под `Mutex`, если callback
  может гоняться с отменой).
- Kotlin-маппинг: `suspendCancellableCoroutine` ≈ `withCheckedThrowingContinuation`
  + `withTaskCancellationHandler`.

---

## 9. Kotlin → Swift: конкурентность

| Kotlin | Swift | Ловушка |
|---|---|---|
| `suspend fun` | `async func` | `await` обязателен у **каждой** точки подвешивания — interleaving видно глазами |
| `CoroutineScope` / `launch` | `async let` / `TaskGroup`; `Task { }` | Scope-объекта нет; структура — из синтаксиса. Task в 6.2 наследует изоляцию контекста |
| `viewModelScope` | хранимый `Task` + cancel в deinit; в SwiftUI `.task {}` | `.task` — авто-отмена, предпочитать |
| `withContext(Dispatchers.Main)` | `@MainActor` на декларации / `await MainActor.run { }` | Изоляция — свойство **декларации**, не точки вызова |
| `Dispatchers.Default/IO` | `@concurrent` async funcs / actors | Пул один и кооперативный: **блокировка в async-коде может задедлочить всё**; `runBlocking`-эквивалента нет намеренно |
| `Mutex.withLock` | `actor` — **НЕ эквивалент** | Актор реентерабелен на каждом `await` (§4.2); Kotlin-лок держится через suspension. Sync-критические секции — `Mutex<T>` |
| `Flow` (cold) | `AsyncSequence` | `collect` ≈ `for await`; операторы — swift-async-algorithms |
| `StateFlow` | `@Observable` + `Observations` | Прямого аналога нет; состояние — `@Observable`, поток изменений — `Observations` |
| `SharedFlow` (multicast) | `AsyncStream` — **НЕТ**, он single-consumer | Multicast — `share()` из AsyncAlgorithms или actor-fan-out (§7.2) |
| `callbackFlow` + `awaitClose` | `AsyncStream` + `onTermination` | Забытый `onTermination` = утечка (§7.2) |
| `ensureActive()` / `isActive` | `try Task.checkCancellation()` / `Task.isCancelled` | Оба кооперативны; `CancellationError` не глотать |
| `supervisorScope` | нет прямого аналога | Ошибка ребёнка группы отменяет остальных; «не ронять соседей» — собирать `Result` в группе |
| `withTimeout` | нет в stdlib | Гонка двух задач в группе или пакет |
| uncaught exception в `launch` **роняет** приложение | ошибка `Task` **молча сохраняется** в task | **Самая коварная разница.** Никто не сделал `try await task.value` → ошибка исчезла. Warning появился только в 6.4 |

Проглоченные ошибки — анти-пример:

```swift
// ПЛОХО: launch-привычка из Kotlin; throw внутри исчезает бесследно
Task { try await session.start() }

// ХОРОШО: обработать на месте…
Task {
    do { try await session.start() }
    catch { log.error("session start failed: \(error)"); self.presentError(error) }
}
// …или сохранить task и дождаться значения там, где ошибку есть кому обработать
```

---

## 10. Миграционные паттерны (конденсат 2025–26)

1. Модуль за модулем: `-strict-concurrency=targeted` → `complete` (warnings) →
   Swift 6 mode (errors). В Xcode 26 — пофичевые migration fix-its.
2. Включить Approachable Concurrency везде; MainActor-default — на app/UI-таргетах.
3. Аннотировать реальность: UI-смежные классы → `@MainActor` (или дефолт модуля).
4. Мутабельные синглтоны → `actor` | `final class` + `Mutex` | `@MainActor`.
5. `@preconcurrency import` для не-аннотированных third-party модулей — вместо
   оборачивания чужих типов в `@unchecked Sendable`.
6. Делегатские колбэки с неизвестных потоков → `AsyncStream` или `Task { @MainActor in }`.
   ⚠️ Устарело: `DispatchQueue.main.async` в новом коде.
7. `nonisolated(unsafe)` — это новый `!`: только для глобалов под внешними
   инвариантами (однократно регистрируемые C-колбэки).
8. Протокол + `@MainActor`-тип → isolated conformances (6.2) или `nonisolated`-члены,
   а не `@MainActor` на весь протокол.

---

## Чеклист ревью

- [ ] App-таргет собран с MainActor-default + Approachable Concurrency? Нет лишних
  `@MainActor`-аннотаций, дублирующих дефолт модуля?
- [ ] CPU-тяжёлая работа помечена `@concurrent nonisolated` (не «надеемся, что
  nonisolated async сам уйдёт в фон» и не `Task.detached`)?
- [ ] Нет `@unchecked Sendable` и `nonisolated(unsafe)` без комментария-обоснования?
  Sync-состояние — `Mutex<T>`, а не NSLock/DispatchQueue?
- [ ] В методах акторов: инварианты перепроверяются после каждого `await`? Нет
  check-then-act через `await` (реентерабельность)? Дедупликация in-flight операций
  там, где нужна?
- [ ] Structured (async let / TaskGroup) предпочтено `Task { }` для параллелизма
  внутри операции?
- [ ] Каждый unstructured `Task` — либо хранится и отменяется, либо осознанно
  fire-and-forget с обработкой ошибок **внутри**? Нет `Task { try await ... }` с
  молча исчезающей ошибкой?
- [ ] Долгие задачи именованы (`Task(name:)`)?
- [ ] Отмена: длинные циклы проверяют `Task.checkCancellation`? `CancellationError`
  пробрасывается, а не глотается/логируется как сбой?
- [ ] Каждый `AsyncStream` имеет `onTermination` и осознанную buffering policy?
  Нигде нет второго потребителя одного стрима (single-consumer)? Multicast — через
  `share()`?
- [ ] Continuations: только checked-варианты; resume ровно один раз на всех путях,
  включая `(nil, nil)`; отменяемость через `withTaskCancellationHandler`?
- [ ] Операторы потоков — из swift-async-algorithms, не самописные? Не появился
  новый Combine-код?
- [ ] Нет `DispatchQueue.main.async`, `Task.detached` для фона, `@Published`+
  ObservableObject в новом коде (⚠️ устаревшие паттерны)?
- [ ] `[weak self]` в задачах — по правилам [01 §6.3](01-swift-language.md), не карго-культ?

---

## Источники

- [SE-0466 Control default actor isolation](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0466-control-default-actor-isolation.md)
- [SE-0461 Run nonisolated async functions on the caller's actor](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md)
- [SE-0414 Region-based isolation](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0414-region-based-isolation.md)
- [SE-0413 Typed throws](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0413-typed-throws.md)
- [Swift 6.2 released](https://www.swift.org/blog/swift-6.2-released/) · [Swift 6.3 released](https://www.swift.org/blog/swift-6.3-released/) — swift.org
- [Approachable Concurrency in Swift 6.2: a clear guide](https://www.avanderlee.com/concurrency/approachable-concurrency-in-swift-6-2-a-clear-guide/) — Antoine van der Lee
- [Default actor isolation in Swift 6.2](https://www.avanderlee.com/concurrency/default-actor-isolation-in-swift-6-2/) — Antoine van der Lee
- [Exploring concurrency changes in Swift 6.2](https://www.donnywals.com/exploring-concurrency-changes-in-swift-6-2/) — Donny Wals
- [Should you opt in to Swift 6.2's main actor isolation?](https://www.donnywals.com/should-you-opt-in-to-swift-6-2s-main-actor-isolation/) — Donny Wals
- [Approachable Concurrency in Swift packages](https://useyourloaf.com/blog/approachable-concurrency-in-swift-packages/) — Use Your Loaf
- [Concurrency glossary](https://www.massicotte.org/concurrency-glossary/) — Matt Massicotte
- [How to use weak self in Swift concurrency tasks](https://www.donnywals.com/how-to-use-weak-self-in-swift-concurrency-tasks/) — Donny Wals
- [Async tasks memory management](https://tanaschita.com/swift-async-tasks-memory-management/) — tanaschita
- [Interop: coroutines ↔ Swift](https://kt.academy/article/interop-coroutines-swift) — Kt. Academy
- [Swift 6 strict concurrency meets Kotlin coroutines in KMP](https://dev.to/software_mvp-factory/swift-6-strict-concurrency-meets-kotlin-coroutines-in-kmp-148c)
