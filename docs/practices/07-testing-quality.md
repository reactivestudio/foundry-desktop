# 07 · Тестирование и качество

> Серия practices · [оглавление](README.md)

Контекст: foundry-desktop — SwiftUI-приложение (Swift 6.2.x, Xcode 26.x, target macOS 15),
основной автор кода — AI-агент через CLI. Тесты — главный механизм, которым агент
проверяет собственную работу, поэтому весь стек качества обязан быть запускаемым
и парсируемым из терминала. Про сборку и CI — [глава 08](08-project-tooling-distribution.md).

## TL;DR

| Задача | Инструмент | Комментарий |
|---|---|---|
| Unit / integration | **Swift Testing** (`import Testing`) | Единственный фреймворк для нового кода |
| UI smoke | XCTest / `XCUIApplication` | ≤ 5 тестов, только smoke |
| Snapshot UI | pointfreeco/swift-snapshot-testing 1.19.x | `NSHostingView` + `.image`, пиннинг macOS в CI |
| Контракт с foundry CLI | golden-фикстуры + opt-in suite | Обязательство обоих репо (см. README) |
| Логи | `os.Logger` + `OSSignposter` | `swift-log` — только в извлекаемых библиотеках |
| Формат | bundled `swift format` | CLI-запуск, не build plugin |
| Lint (опц.) | SwiftLint, тонкий ruleset | Только CI/pre-commit |

---

## 1. Swift Testing — единственный фреймворк для нового кода

**Правило.** Весь новый юнит- и интеграционный код тестируется через Swift Testing
(`import Testing`). XCTest в новом коде запрещён, единственное исключение —
`XCUIApplication`-based smoke-тесты (§5) и `XCTMetric`-перфоманс, если он когда-нибудь
понадобится.

**Почему.** Swift Testing включён в тулчейн с Xcode 16, официально позиционируется
Apple как преемник XCTest, и к Swift 6.2/Xcode 26 закрыл последние пробелы (exit
tests, attachments). Он нативен для async/await, макросы `#expect`/`#require` дают
диагностические сообщения с развёрнутыми подвыражениями (агенту не надо угадывать,
что именно не совпало), а `swift test` в пакете гоняет его без Xcode вообще.

⚠️ Устарело: `XCTAssertEqual`-стиль, наследование от `XCTestCase`, `setUp/tearDown`
в новом коде. Для мигрируемых старых сьютов действует правило сообщества: переносить
**per-target, а не per-file**, и помнить, что Swift Testing параллелит тесты по
умолчанию и запускает их на произвольных потоках — латентные предположения о
последовательности всплывут.

### 1.1 Базовые макросы

```swift
import Testing
@testable import FoundryCore

@Test func versionParses() throws {
    let v = try #require(SemVer(string: "1.4.0"))   // throwing unwrap: nil → тест падает здесь
    #expect(v.major == 1)
    #expect(v.description == "1.4.0")
}
```

- `#expect(...)` — мягкая проверка: тест продолжается, все падения собираются.
- `#require(...)` — жёсткая: бросает и прерывает тест; заменяет `XCTUnwrap` и
  guard-цепочки в arrange-фазе.
- Ошибки: `#expect(throws: FoundryError.self) { try parser.parse(garbage) }`.

### 1.2 Параметризованные тесты

**Правило.** Табличные случаи — через `arguments:`, а не через цикл внутри теста.

**Почему.** Каждый аргумент — отдельный тест-кейс: отдельный репорт, отдельный
rerun, параллельное выполнение. Цикл же падает на первом кейсе и прячет остальные.

```swift
@Test(arguments: [
    ("build --json", FoundryCommand.build),
    ("check --json", .check),
    ("fmt",          .format),
])
func commandLineRoundtrips(input: String, expected: FoundryCommand) throws {
    #expect(try FoundryCommand(argv: input.split(separator: " ").map(String.init)) == expected)
}

// Матрица: два списка → декартово произведение; zip(...) — попарно
@Test(arguments: zip(Fixture.allProjects, Fixture.expectedTargetCounts))
func projectIndexCounts(fixture: Fixture, count: Int) async throws { ... }
```

Анти-пример:

```swift
// ПЛОХО: один тест, падение на втором кейсе скрывает третий
@Test func commandsParse() throws {
    for (input, expected) in cases { #expect(try parse(input) == expected) }
}
```

### 1.3 Traits

| Trait | Когда |
|---|---|
| `.enabled(if:)` / `.disabled("reason")` | Условный запуск (env-флаги, наличие бинаря) |
| `.timeLimit(.minutes(1))` | Страховка для интеграционных/subprocess-тестов |
| `.tags(.contract)` | Группировка: `swift test --filter` по тегам |
| `.bug("https://github.com/.../issues/42")` | Линковка регрессий |
| `.serialized` | Отключить параллелизм внутри сьюта |
| `.snapshots(record: ...)` | Suite-trait от snapshot-testing (§4) |

`.serialized` — не костыль «чтобы не флэйкало», а осознанная пометка сьютов,
работающих с общим внешним состоянием (реальная ФС, реальный CLI, keychain).
Юнит-тесты, которым нужен `.serialized`, обычно сигналят о скрытом глобальном
состоянии — чинить состояние, а не сериализовать.

```swift
extension Tag {
    @Tag static var contract: Self   // тесты против реального foundry CLI
    @Tag static var snapshot: Self
}

@Suite(.tags(.contract), .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["RUN_CONTRACT_TESTS"] != nil))
struct FoundryCLIContractTests { ... }
```

### 1.4 Exit tests (Swift 6.2+)

Для кода с `precondition`/`fatalError` — тело выполняется в дочернем процессе:

```swift
@Test func storeRefusesCorruptSchema() async {
    await #expect(processExitsWith: .failure) {
        _ = try! Store(schemaVersion: -1)   // ожидаем fatalError
    }
}
```

Полезно ровно для контрактов «этого не должно случиться»; не превращать в
основной стиль — обычные ошибки должны быть `throws`, а не трапами (см.
[главу 01](01-swift-language.md)).

### 1.5 Attachments (Swift 6.2+)

При падении интеграционного теста приложить сырой вывод — агент и человек читают
артефакт вместо реконструкции по логам:

```swift
@Test func indexerHandlesLargeProject() async throws {
    let result = try await runner.run("foundry", ["index", "--json"], cwd: fixtureDir)
    Attachment.record(result.stdoutText, named: "foundry-index-stdout.json")
    #expect(result.status == 0)
}
```

В `xcodebuild test` вложения попадают в `.xcresult`; в `swift test` — в
`--attachments-path`.

### 1.6 `confirmation` для callback-API

```swift
@Test func watcherFiresOnChange() async throws {
    try await confirmation("fs event delivered", expectedCount: 1) { fired in
        let watcher = FileWatcher(url: tmp) { _ in fired() }
        try touch(tmp.appendingPathComponent("a.swift"))
        try await watcher.drain()
    }
}
```

Замена `XCTestExpectation`. Для событий, которые *не должны* произойти —
`expectedCount: 0`.

---

## 2. Async-тесты, @Observable и акторы

**Правило.** Изоляция теста повторяет изоляцию SUT: тестируешь `@MainActor`-модель —
помечай тест `@MainActor`; тестируешь актор — `await` через границу.

**Почему.** Swift Testing запускает тесты на произвольных потоках. Без явной
аннотации main-actor-изолированная модель либо не скомпилируется в тесте (Swift 6
strict concurrency), либо спровоцирует ложные обходные пути (`MainActor.assumeIsolated`
в тестах — запах).

```swift
// Async: просто async-функция, никаких expectation
@Test func buildStreamCompletes() async throws {
    let events = try await Array(runner.buildEvents(for: .fixture))
    #expect(events.last == .finished(code: 0))
}

// @Observable-модель (стандартный SwiftUI VM, см. главу 03)
@Test @MainActor func sidebarSelectionUpdates() {
    let model = SidebarModel(projects: .previewList)
    model.select(id: model.projects[1].id)
    #expect(model.selection == model.projects[1].id)
}

// Актор: только await, никаких «дай мне синхронный доступ»
@Test func diskCacheEvictsOldest() async {
    let cache = DiskCache(limit: 2)      // actor
    await cache.store("a"); await cache.store("b"); await cache.store("c")
    #expect(await cache.count == 2)
    #expect(await cache.contains("a") == false)
}
```

Замечания:

- `@Observable`-модель — обычный класс: создали, помутировали, проверили состояние.
  Observation-машинерия в тестах не нужна. Если принципиально «а опубликовалось ли» —
  `withObservationTracking` + `confirmation`, но почти всегда достаточно assert'а
  post-state.
- **Время инжектится.** Код, зависящий от времени (debounce, retry, поллинг CLI),
  принимает `any Clock<Duration>`; тест подставляет мгновенный/ручной clock.
  `try await Task.sleep` в тесте — анти-паттерн: медленно и флэйкает.

```swift
// ПЛОХО
@Test func debounceWaits() async throws {
    model.type("f")
    try await Task.sleep(for: .milliseconds(350))   // флэйк + 350ms на каждый прогон
    #expect(model.searchFired)
}
```

---

## 3. Subprocess-тяжёлый код: seam, фейки, контракт с foundry CLI

foundry-desktop — по сути GUI над foundry CLI, поэтому это центральный раздел.
Тестовая стратегия — три слоя, от быстрого к дорогому.

### 3.1 Слой 1: protocol seam + FakeCommandRunner

**Правило.** Логика никогда не вызывает `Process`/`Subprocess` напрямую — только
через протокол.

```swift
public protocol CommandRunning: Sendable {
    func run(_ exe: String, _ args: [String],
             cwd: URL?, env: [String: String]?) async throws -> CommandResult
}

public struct CommandResult: Sendable {
    public let status: Int32
    public let stdout: Data
    public let stderr: Data
}
```

Продакшен-конформанс — на `swiftlang/swift-subprocess` (0.5, pre-1.0 — пиннинг
minor, см. [главу 08 §4](08-project-tooling-distribution.md)). В тестах —
скриптованный фейк:

```swift
struct FakeCommandRunner: CommandRunning {
    var responses: [[String]: CommandResult]   // args → result
    var recorded: LockIsolated<[[String]]> = .init([])

    func run(_ exe: String, _ args: [String], cwd: URL?, env: [String: String]?)
        async throws -> CommandResult {
        recorded.withValue { $0.append([exe] + args) }
        guard let r = responses[[exe] + args] else { throw TestError.unexpectedCommand }
        return r
    }
}
```

Парсеры вывода CLI тестируются на **фикстурах** — захваченных триплетах
stdout/stderr/exit-code, лежащих в тестовых ресурсах пакета:

```swift
// Package.swift (тестовый таргет)
.testTarget(name: "FoundryCLITests",
            dependencies: ["FoundryCLI"],
            resources: [.copy("Fixtures")])

// Тест
@Test func parsesBuildOutput() throws {
    let data = try #require(Bundle.module.url(
        forResource: "Fixtures/foundry-build-success", withExtension: "json"))
    let report = try FoundryBuildReport(json: Data(contentsOf: data))
    #expect(report.diagnostics.isEmpty)
}
```

### 3.2 Слой 2: фейковые исполняемые для реального раннера

Сам `SubprocessCommandRunner` (продакшен-конформанс) тоже нужно тестировать:
конструирование аргументов, прокидывание env и cwd, PATH-резолюция, захват потоков,
терминация. Для этого — крошечные shell-скрипты в тестовых ресурсах, помеченные
исполняемыми, с законсервированным выводом:

```bash
#!/bin/sh
# Tests/FoundryCLITests/Fixtures/bin/fake-foundry
echo '{"status":"ok"}'
echo 'warning: something' >&2
exit 0
```

```swift
@Test func runnerCapturesBothStreams() async throws {
    let exe = try #require(Bundle.module.url(forResource: "Fixtures/bin/fake-foundry",
                                             withExtension: nil)).path
    let r = try await SubprocessCommandRunner().run(exe, [], cwd: nil, env: nil)
    #expect(r.status == 0)
    #expect(String(data: r.stderr, encoding: .utf8)!.contains("warning"))
}
```

Это интеграционный тест раннера, но всё ещё быстрый и герметичный — реального
foundry не требует.

### 3.3 Слой 3: контракт-тесты против настоящего foundry CLI

**Правило.** Отдельный opt-in сьют гоняет реальный `foundry` и сверяет его вывод
с golden-файлами. **Это зафиксированное в README обязательство обоих репозиториев:**
foundry (CLI) не меняет машинный формат вывода без обновления фикстур, foundry-desktop
держит контракт-сьют зелёным против текущего CLI.

**Почему.** Фейки из §3.1 проверяют, что *наш парсер понимает наш снимок* вывода.
Дрейф формата на стороне CLI они не поймают по построению. Контракт-сьют ловит его
не флэйкая: в обычном прогоне он выключен, в CI включается отдельной джобой с
установленным foundry.

```swift
@Suite(.tags(.contract), .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["RUN_CONTRACT_TESTS"] != nil),
       .timeLimit(.minutes(2)))
struct FoundryCLIContractTests {
    @Test func buildJSONShapeIsStable() async throws {
        let r = try await SubprocessCommandRunner()
            .run("foundry", ["build", "--json"], cwd: Fixture.sampleProject, env: nil)
        let report = try FoundryBuildReport(json: r.stdout)
        // golden-сверка структуры, не байтов: .dump игнорирует нестабильные поля
        assertSnapshot(of: report.normalizedForGolden, as: .dump)
    }
}
```

Дисциплина golden-файлов:

- Голдены записываются стратегиями `.dump`/`.json` из swift-snapshot-testing —
  тот же механизм, что и для картинок, но для структур.
- Перед сверкой отчёт **нормализуется**: пути, тайминги, версии инструментов
  вырезаются/маскируются — голден должен переживать чужую машину.
- Перезапись — только осознанно (`SNAPSHOT_TESTING_RECORD=all` или
  `.snapshots(record: .all)` локально) и отдельным коммитом с указанием версии
  CLI, под которую перезаписано.
- В CI контракт-джоба пиннит версию foundry и падает с внятным диффом — это и есть
  сигнал «CLI уехал, обнови парсер и фикстуры».

---

## 4. Snapshot-тесты SwiftUI

**Правило.** Визуальная регрессия ловится snapshot-тестами
(pointfreeco/swift-snapshot-testing **1.19.x**, активно сопровождается),
а не XCUITest-скриншотами.

**Почему.** Snapshot-тест — обычный быстрый тест: рендерит view в `NSHostingView`
и сравнивает `NSImage` с эталоном. XCUITest для этого — на порядки медленнее и
флэйковее. Превью-фикстуры из [главы 03](03-swiftui-architecture.md)
(`Model.preview`, `.previewList`) используются здесь повторно — одна инвестиция,
два потребителя.

```swift
import SnapshotTesting
import Testing

@Suite(.tags(.snapshot), .snapshots(record: .missing))
@MainActor
struct SidebarSnapshotTests {
    @Test func sidebarDefault() {
        let view = NSHostingView(rootView:
            Sidebar(model: .preview)
                .frame(width: 320, height: 600)          // фиксированный размер обязателен
                .environment(\.colorScheme, .light))     // явная appearance
        assertSnapshot(of: view, as: .image)
    }
}
```

Правила стабильности:

| Правило | Причина |
|---|---|
| Фиксированный `.frame` | Авторазмер зависит от окружения рендера |
| Явный `colorScheme` (+ отдельные тесты на dark) | Иначе снапшот зависит от системной темы |
| **Пиннинг версии macOS в CI** (`runs-on: macos-26`, без «latest») | Рендеринг текста/материалов различается между мажорными macOS |
| Голдены пишутся на той же платформе, где сверяются | Локальный мак ≠ CI-раннер; источник истины — CI-раннер либо одинаковая версия ОС |
| Никаких снапшотов view с живыми таймерами/анимациями | Недетерминизм по построению |

Анти-пример: снапшотить целое окно приложения. Диффы становятся нечитаемыми, любой
чих ломает всё. Снапшотить надо компоненты и характерные состояния (empty, loading,
error, длинные строки).

---

## 5. XCUITest на macOS: минимальный smoke

**Правило.** UI-автоматизация — отдельный XCTest-бандл, ≤ 5 тестов уровня
«приложение запускается, главное окно появляется, ключевой флоу прокликивается».
Вся содержательная UI-логика покрывается юнит-тестами вью-моделей (§2) и
снапшотами (§4).

**Почему.** XCUITest на macOS работает (accessibility-driven, out-of-process),
но медленный и исторически более флэйковый, чем на iOS. Его ценность — поймать
«приложение не стартует / окно пустое», то, чего юнит-слой не видит в принципе.

```swift
final class SmokeTests: XCTestCase {   // единственное легальное место XCTest
    @MainActor func testAppLaunchesAndShowsProjects() {
        let app = XCUIApplication()
        app.launchEnvironment["FOUNDRY_UI_TEST"] = "1"   // фиктивный runner внутри
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.outlines["sidebar.projects"].exists)
        app.typeKey("n", modifierFlags: .command)         // меню/шорткаты автоматизируемы
    }
}
```

- **Accessibility identifiers обязательны** на всём, что трогает smoke:
  `.accessibilityIdentifier("sidebar.addButton")`. Это одновременно реальная
  accessibility-гигиена, а не только тестовая обвязка.
- Под UI-тестом приложение получает env-флаг и подменяет `CommandRunning` на фейк —
  smoke не должен зависеть от установленного foundry.

---

## 6. Логи и диагностика

### 6.1 os.Logger — в приложении, swift-log — в извлекаемых библиотеках

**Правило.** Весь app-код логирует через `os.Logger` c subsystem = bundle id и
категорией на подсистему. `swift-log` — только если таргет задуман переносимым
(Linux); тогда его бэкендом на маке всё равно ставится OSLog-handler.

**Почему.** Unified logging — zero-config, почти бесплатен при выключенном уровне,
интегрирован с Console.app, Instruments и sysdiagnose. Для десктоп-приложения это
строго лучше самописных файлов и print.

```swift
import os

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier!  // "dev.foundry.desktop"
    static let ui      = Logger(subsystem: subsystem, category: "ui")
    static let process = Logger(subsystem: subsystem, category: "process")
    static let store   = Logger(subsystem: subsystem, category: "store")
}

Logger.process.info("spawn \(exe, privacy: .public) args=\(args.joined(separator: " "), privacy: .public)")
Logger.store.error("migration failed: \(error.localizedDescription, privacy: .public)")
Logger.ui.debug("open path \(path, privacy: .private(mask: .hash))")   // коррелируем, не светим
```

Ключевые факты:

- Интерполяции **приватны по умолчанию** (в чужом Console — `<private>`).
  Диагностику помечать `.public`, пользовательские пути/данные —
  `.private(mask: .hash)`.
- Персистентность уровней: `.debug` — только память, `.info` — не пишется на диск
  по умолчанию; `.notice`/`.error`/`.fault` — персистятся. Всё, что захочется
  увидеть с машины пользователя постфактум, — `.error` и выше.
- Чтение (и агентом тоже):

```bash
log stream --predicate 'subsystem == "dev.foundry.desktop"' --level debug
log show --last 30m --predicate 'subsystem == "dev.foundry.desktop"' --info --debug
```

- `OSLogStore(scope: .currentProcessIdentifier)` позволяет приложению экспортировать
  собственные свежие логи — пункт меню «Copy Diagnostics» для dev-тула почти
  обязателен и дешев.

### 6.2 OSSignposter для горячих путей

⚠️ Устарело: `os_signpost` — legacy API. Современный — `OSSignposter`:

```swift
let sp = OSSignposter(subsystem: "dev.foundry.desktop", category: "perf")
let state = sp.beginInterval("indexProject")
defer { sp.endInterval("indexProject", state) }
```

Интервалы видны в Instruments (Points of Interest). Ставить на: запуск/парсинг
foundry-команд, индексацию, миграции GRDB, первый рендер тяжёлых списков.

### 6.3 Крэши

MetricKit на macOS — усечённый и в процессе редизайна; сам по себе недостаточен.
Позиция проекта: телеметрии нет; при репорте бага пользователь прикладывает
`~/Library/Logs/DiagnosticReports/Foundry-*.ips` и экспорт `log show`.
Если когда-нибудь захочется автоматики — Sentry (opt-in, `beforeSend`-скраббинг),
не раньше.

---

## 7. Формат и линт

### 7.1 Bundled `swift format` — единственный форматтер

**Правило.** Форматирование — только тулчейновым `swift format` (bundled с Xcode
начиная с 16; в Xcode 26 — swift-format 603.x). Агент прогоняет его после каждой
правки; CI проверяет `--strict`.

```bash
swift format --in-place --recursive Packages App     # локально / агентом
swift format lint --strict --recursive Packages App  # CI-гейт
```

Конфиг — закоммиченный `.swift-format` (JSON):

```json
{
  "version": 1,
  "lineLength": 120,
  "indentation": { "spaces": 4 }
}
```

**Почему.** Ноль зависимостей, версия форматтера жёстко связана с тулчейном →
детерминированные диффы. Для кода, который пишет AI, один канонический форматтер —
это гигиена диффов и отсутствие споров о стиле в принципе.

Анти-примеры: два форматтера одновременно (swift-format + SwiftFormat Ника
Локвуда) — гарантированная война правок; форматтер как build plugin — замедляет
каждую сборку и добавляет sandbox-трение плагинов.

### 7.2 SwiftLint — опционально и тонко

Если добавлять (не обязательно), то:

- только correctness-ish правила: `empty_count`, `force_unwrapping`,
  `unowned_variable_capture`, `sorted_imports`; стилевые — выключить, стиль уже
  закрывает swift-format;
- запуск **CLI в CI/pre-commit, не build plugin**: `swiftlint --strict --reporter json`
  агент запускает и парсит сам;
- любое новое правило — с обоснованием в PR.

---

## 8. Вердикт: петли обратной связи для AI-агента

Двухуровневый цикл (подробно о сборке — [глава 08 §3](08-project-tooling-distribution.md)):

**Inner loop — секунды, гонять постоянно:**

```bash
cd Packages/FoundryKit && swift test          # весь пакет, ~95% кода
swift test --filter FoundryCLITests          # точечно
```

**Integration loop — перед коммитом и в CI:**

```bash
set -o pipefail && xcodebuild test \
  -project Foundry.xcodeproj -scheme Foundry \
  -destination 'platform=macOS,arch=arm64' \
  -resultBundlePath .build/Tests.xcresult \
  | xcbeautify

# Машиночитаемый итог — парсить это, а не скрести логи:
xcrun xcresulttool get test-results summary --path .build/Tests.xcresult
xcrun xcresulttool get test-results tests   --path .build/Tests.xcresult
```

`set -o pipefail` обязателен при пайпе в форматтер — иначе падение xcodebuild
маскируется успехом xcbeautify. На macOS нет симуляторов — тесты идут на хосте,
что делает CLI-прогон детерминированнее, чем на iOS.

Контракт-сьют (§3.3) — третья, редкая петля: `RUN_CONTRACT_TESTS=1 swift test
--filter FoundryCLIContractTests` локально при работе над парсерами и отдельной
джобой в CI.

---

## Чеклист ревью

- [ ] У новой логики есть тесты; тесты на Swift Testing (`import Testing`), не XCTest.
- [ ] XCTest встречается только в XCUITest-бандле smoke-тестов.
- [ ] Изменился парсинг вывода foundry → фикстуры/голдены контракт-тестов обновлены
      (и версия CLI, под которую перезаписаны, указана в коммите).
- [ ] Новый вызов внешнего процесса идёт через `CommandRunning`, не через
      Process/Subprocess напрямую.
- [ ] Табличные случаи — `@Test(arguments:)`, а не цикл в теле теста.
- [ ] Тесты `@MainActor`-моделей помечены `@MainActor`; нет `assumeIsolated` в тестах.
- [ ] Нет `Task.sleep` для ожиданий — время через инжектированный `Clock`,
      колбэки через `confirmation`.
- [ ] `.serialized` появился → в PR объяснено, каким внешним состоянием он вызван.
- [ ] Новые/изменённые view-состояния покрыты снапшотами; снапшоты с фиксированным
      frame и явной colorScheme; голдены перезаписаны осознанно.
- [ ] Новые интерактивные контролы имеют `accessibilityIdentifier`.
- [ ] Логирование — `os.Logger` с категорией; пользовательские данные не помечены
      `.public`; ошибки уровня `.error`+.
- [ ] `swift format lint --strict` проходит; ручных отступлений от форматтера нет.

## Источники

- Swift Testing: exit tests — https://github.com/swiftlang/swift-evolution/blob/main/proposals/testing/0008-exit-tests.md, https://www.theswift.dev/posts/swift-testing-exit-tests-fatalerror/
- Swift Testing: attachments в Xcode 26 — https://dev.to/arshtechpro/xcode-26-swift-testing-attachments-2lcf
- Swift Testing vs XCTest — https://blakecrosley.com/blog/swift-testing-vs-xctest
- Миграция на Swift Testing (форумы Swift) — https://forums.swift.org/t/what-you-need-to-know-before-migrating-to-swift-testing/81005
- Изоляция акторов в тестах — https://pixelper.com/blog/ios-actor-testing, https://helpmetest.com/blog/swift-concurrency-testing/
- swift-snapshot-testing — https://github.com/pointfreeco/swift-snapshot-testing
- swift-subprocess — https://github.com/swiftlang/swift-subprocess, https://blog.jacobstechtavern.com/p/swift-subprocess
- XCUITest — https://bitrise.io/guides/xcuitest
- Запуск тестов из терминала — https://mokacoding.com/blog/running-tests-from-the-terminal/
- os.Logger / unified logging — https://www.avanderlee.com/debugging/oslog-unified-logging/, https://developer.apple.com/documentation/os/oslogprivacy
- swift-format — https://troz.net/post/2024/swift_format/, https://nshipster.com/swift-format/
