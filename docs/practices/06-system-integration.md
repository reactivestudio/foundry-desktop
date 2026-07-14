# 06 · Системная интеграция: подпроцессы, файлы, БД, WKWebView

> Серия practices · [оглавление](README.md)

Это ядро foundry-desktop. Приложение — не «SwiftUI поверх модели», а **оркестратор внешних процессов и файловой правды**: оно шеллит `foundry --plain`, стримит `claude -p`, следит за `.foundry/`-каталогами через FSEvents, дергает `git`, складывает проекцию в SQLite и рендерит ревью в WKWebView-островах. Каждая из этих подсистем имеет одну-две канонические ловушки, которые в macOS-разработке наступают все и всегда. Эта глава фиксирует выбранные решения, причины и анти-паттерны.

Версии, на которые рассчитан текст: **Swift 6.3 / Xcode 26**, **swift-subprocess 0.5.x**, **GRDB 7.x (7.11+)**, deployment target — macOS 15 Sequoia (все API главы доступны с macOS 14–15 — ветки `#available` не нужны). Проверено на состояние июля 2026.

Сквозная архитектура одним абзацем: события (FSEvents, exit-коды, stream-json) — только **подсказки**; правда — файлы `.foundry/` и git; SQLite — **перестраиваемая проекция** этой правды; SwiftUI наблюдает проекцию через `ValueObservation`. Любой сбой (пропущенные события, крэш, несовместимая схема) лечится одним и тем же путём — reconcile-сканом.

---

## 1. Подпроцессы: swift-subprocess (SF-0007)

### 1.1 Почему swift-subprocess, а не Process

**Правило: весь запуск внешних процессов — только через `swift-subprocess`. Legacy `Process` (NSTask) в кодовой базе запрещён.**

`swift-subprocess` — реализация пропозала SF-0007, вышла как отдельный SPM-пакет в сентябре 2025, актуальный релиз — **0.5.x** (пакет пре-1.0 — **пиновать версию** в `Package.swift`). Требует Swift 6.1+ / Xcode 16.3+. Под капотом `posix_spawn`, снаружи — полностью async/await.

| Проблема | `Process` (NSTask) | `swift-subprocess` |
|---|---|---|
| Deadlock на pipe-буфере | классика, см. §1.2 | невозможен: pull-based чтение |
| Backpressure | нет (`readabilityHandler` push-based) | встроен: ребёнок блокируется на `write(2)`, пока вы не читаете |
| Отмена → убийство процесса | вручную (`terminationHandler` + `terminate()`) | teardown-последовательность срабатывает автоматически при отмене `Task` |
| Зомби | легко (забыли `waitUntilExit`) | невозможны: `run()` всегда ждёт и reap'ит (structured concurrency) |
| Убийство дерева процессов | не выражается (нет доступа к pgid) | `PlatformOptions.createSession` / `.processGroupID` |
| workingDirectory | глобальный cwd-хак или свойство с гонками | параметр per-invocation |
| Swift 6 concurrency | `Sendable`-фрикция в хендлерах | Sendable-чистый API |

```swift
// Package.swift — пиновать: API пре-1.0
.package(url: "https://github.com/swiftlang/swift-subprocess", exact: "0.5.0")
```

### 1.2 ⚠️ Устарело: Process/NSTask и pipe-deadlock

Для чтения чужого кода и понимания, чего мы избегаем. Классический deadlock:

```swift
// ПЛОХО — зависает, как только ребёнок напишет > ~64 KB
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
p.arguments = ["log"]
let pipe = Pipe()
p.standardOutput = pipe
try p.run()
p.waitUntilExit()                                    // ← ребёнок заблокирован на write(2),
let data = pipe.fileHandleForReading.readDataToEndOfFile() // мы — на waitUntilExit. Deadlock.
```

Кернельный pipe-буфер ~64 KB. Ребёнок пишет, буфер заполняется, `write(2)` блокируется; родитель ждёт `waitUntilExit()` — оба стоят. Та же ловушка при чтении stdout до EOF, пока переполняется stderr-pipe. Правило для legacy-кода: **сначала конкурентно поднять чтение обоих потоков, потом ждать exit** (разбор от Quinn: developer.apple.com/forums/thread/690310). Прочие грабли `Process`:

- `readabilityHandler` — push-based, ставить **до** `run()`, EOF детектировать по пустому `availableData` и обнулять handler (иначе крутится вхолостую); хендлер бежит на приватной очереди — `Sendable`-боль в Swift 6.
- `FileHandle.bytes` итерирует **по байту** (медленно на МБ/с) и **не убивает процесс при отмене** — нужен свой `terminationHandler`.
- `terminate()` сигналит только прямого ребёнка; дерево (claude → node → MCP-серверы) остаётся жить.

Всё это в swift-subprocess отсутствует как класс.

### 1.3 Собранный запуск: контракт `foundry --plain`

`foundry` CLI — **protocol seam** приложения: стабильный машинный интерфейс (`--plain` — без цветов/спиннеров) с контрактом exit-кодов. GUI никогда не парсит человеческий вывод — только `--plain` + код.

| Exit-код | Смысл | Реакция GUI |
|---|---|---|
| `0` | успех | применить вывод |
| `1` | доменная ошибка (валидная ситуация: конфликт, невыполненное предусловие) | показать как состояние, не как сбой |
| `2` | ошибка выполнения | показать ошибку, предложить retry |
| `64` | usage-ошибка (`EX_USAGE`) | **баг интеграции** — лог + assert в DEBUG: GUI собрал неверные аргументы |

```swift
import Subprocess

enum FoundryOutcome: Sendable {
    case ok(String)
    case domainFailure(String)      // exit 1 — легитимное «нет»
    case runtimeError(String)       // exit 2
    case usageBug(String)           // exit 64 — чиним у себя
    case killed(Signal)
    case unexpected(code: Int32, stderr: String)
}

func runFoundry(_ arguments: [String], in projectDir: String) async throws -> FoundryOutcome {
    let result = try await run(
        .path(FilePath(try await ToolLocator.shared.path(for: .foundry))),
        arguments: Arguments(arguments + ["--plain"]),
        environment: .inherit.updating(["NO_COLOR": "1", "LC_ALL": "en_US.UTF-8"]),
        workingDirectory: FilePath(projectDir),          // per-invocation, никаких chdir
        output: .string(limit: 4 * 1024 * 1024),         // лимит: бросит, если foundry понесло
        error: .string(limit: 1024 * 1024)
    )
    let out = result.standardOutput ?? ""
    let err = result.standardError ?? ""
    switch result.terminationStatus {
    case .exited(0):  return .ok(out)
    case .exited(1):  return .domainFailure(out)
    case .exited(2):  return .runtimeError(err.isEmpty ? out : err)
    case .exited(64): assertionFailure("foundry usage error: \(err)"); return .usageBug(err)
    case .exited(let code): return .unexpected(code: code, stderr: err)
    case .unhandledException(let sig): return .killed(sig)
    }
}
```

Замечания:

- `output: .string(limit:)` — всегда с лимитом. Собранный вывод без лимита — это OOM, отложенный до первого «а что если foundry задампит мегабайты».
- `workingDirectory:` — параметр вызова. `FileManager.changeCurrentDirectoryPath` — глобальное состояние процесса, гонки между параллельными вызовами гарантированы.

```swift
// ПЛОХО — cwd глобален, два параллельных вызова перетирают друг друга
FileManager.default.changeCurrentDirectoryPath(projectA)
try await run(.path(foundry), arguments: ["status", "--plain"], output: .string(limit: 1 << 20))

// ХОРОШО
try await run(.path(foundry), arguments: ["status", "--plain"],
              workingDirectory: FilePath(projectA), output: .string(limit: 1 << 20))
```

### 1.4 Teardown: SIGINT → SIGTERM → SIGKILL при отмене Task

**Правило: остановка любого долгоживущего ребёнка выражается отменой Swift `Task`; сам ребёнок конфигурируется teardown-последовательностью и собственной process group.**

Почему именно такая лестница сигналов:

- **SIGINT первым** — `claude` перехватывает его, успевает дописать финальный `result`-event и прибрать собственных детей. SIGTERM-first это теряет.
- **SIGTERM затем SIGKILL** — для тех, кто SIGINT игнорирует.
- **`createSession = true`** — ребёнок получает собственную сессию и process group (`setsid`); сигналы teardown-последовательности уходят **всей группе**, а не только прямому ребёнку. Без этого дерево claude (node, MCP-серверы, шеллы) переживает родителя.

```swift
var opts = PlatformOptions()
opts.createSession = true                              // своя группа ⇒ убьём всё дерево
opts.teardownSequence = [
    .send(signal: .interrupt, allowedDurationToNextStep: .seconds(3)),  // SIGINT: дать дописать result
    .gracefulShutDown(allowedDurationToNextStep: .seconds(5)),          // SIGTERM, затем SIGKILL
]
```

Ключевое свойство: **teardown срабатывает автоматически при отмене Task, оборачивающего `run(...)`**. Кнопка Stop в UI = `task.cancel()` — и всё. Отдельного «kill tree» API нет; если нужен ручной сигнал группе — `kill(-pgid, SIGTERM)` по pgid ребёнка.

Зомби: `run()` не возвращается, пока процесс не reaped. Утечь зомби через swift-subprocess нельзя — это структурная гарантия, а не дисциплина.

### 1.5 PATH: GUI-приложение не видит Homebrew

**Факт:** GUI-приложение, запущенное из Finder/Dock/Spotlight, наследует окружение от `launchd`, а не от шелла. Дефолтный PATH — `/usr/bin:/bin:/usr/sbin:/sbin` (иногда + `/usr/local/bin`). `~/.zshrc` не читается, `/opt/homebrew/bin` в PATH **нет**. Значит, `.name("claude")` (поиск по PATH) в GUI не найдёт ничего из Homebrew/nvm/volta.

Стратегия резолва (в порядке применения), реализуется одним актором `ToolLocator`:

1. **User override** из настроек (абсолютный путь) — всегда выигрывает, всегда виден в diagnostics-UI.
2. **Пробирование кандидатов** — быстро и детерминированно:

```swift
actor ToolLocator {
    static let shared = ToolLocator()
    private var cache: [Tool: String] = [:]

    enum Tool: String { case claude, foundry, git }

    private static let candidateDirs = [
        "/opt/homebrew/bin",                       // Apple Silicon Homebrew
        "/usr/local/bin",                          // Intel Homebrew / ручные установки
        "\(NSHomeDirectory())/.local/bin",
        "\(NSHomeDirectory())/.claude/local",      // native-инсталляция claude
        "\(NSHomeDirectory())/bin",
        "/usr/bin", "/bin",
    ]

    func path(for tool: Tool) async throws -> String {
        if let hit = cache[tool] { return hit }
        if let override = Settings.shared.binaryOverride(for: tool) { cache[tool] = override; return override }
        for dir in Self.candidateDirs {
            let p = "\(dir)/\(tool.rawValue)"
            if FileManager.default.isExecutableFile(atPath: p) {
                let resolved = URL(fileURLWithPath: p).resolvingSymlinksInPath().path // brew = симлинки в Cellar
                cache[tool] = resolved; return resolved
            }
        }
        if let p = try await loginShellProbe(tool.rawValue) { cache[tool] = p; return p }
        throw ToolError.notFound(tool)
    }
}
```

3. **Login-shell probe** — единожды при старте, кэшируется; ловит nvm/volta/asdf/mise-экзотику (тот же приём, что `resolveShellEnv` у VS Code):

```swift
private func loginShellProbe(_ name: String) async throws -> String? {
    let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    let result = try await run(.path(FilePath(shell)),
                               arguments: ["-l", "-c", "command -v \(name)"],
                               output: .string(limit: 64 * 1024))
    // login-шелл печатает мусор (motd, direnv) — берём только строки-абсолютные-пути
    return result.standardOutput?
        .split(separator: "\n").map(String.init)
        .last { $0.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: $0) }
}
```

Каверзы probe: nvm-init может стоить 500 мс+ — запускать вне main actor, тайм-боксить, кэшировать на процесс. Не использовать `launchctl setenv` / правку `/etc/paths` — это мутация машины пользователя.

И последнее: спавня `claude`, передавайте **дополненный PATH** в окружение (`.inherit.updating(["PATH": augmentedPATH])`) — claude сам шеллит node/git, и его дети наследуют окружение вашего GUI, а не терминала пользователя.

---

## 2. Стриминг `claude -p`

### 2.1 Флаги и формат

Проверенный набор флагов:

```
claude -p "<prompt>" --output-format stream-json --verbose --include-partial-messages
```

- `--output-format stream-json` — newline-delimited JSON: события `system` (init), `assistant`, `user` (tool results), `result`.
- `--include-partial-messages` — токен-уровневые `stream_event`-дельты (требует `--verbose`).
- Понадобится двунаправленная сессия — тот же парсер работает с `--input-format stream-json` (JSON-сообщения в stdin через `input:`), процесс становится персистентным.

### 2.2 Пайплайн: AsyncThrowingStream поверх run

```swift
enum ClaudeEvent: Sendable {
    case system(SystemInit)
    case assistant(AssistantMessage)
    case streamDelta(StreamEvent)     // token-дельты
    case result(RunResult)
    case unknown(type: String, raw: String)   // ← обязательный кейс
}

func streamClaude(prompt: String, cwd: String, claudePath: String)
    -> AsyncThrowingStream<ClaudeEvent, Error>
{
    AsyncThrowingStream { continuation in
        let task = Task {
            var opts = PlatformOptions()
            opts.createSession = true
            opts.teardownSequence = [
                .send(signal: .interrupt, allowedDurationToNextStep: .seconds(3)),
                .gracefulShutDown(allowedDurationToNextStep: .seconds(5)),
            ]
            do {
                let result = try await run(
                    .path(FilePath(claudePath)),
                    arguments: ["-p", prompt, "--output-format", "stream-json",
                                "--verbose", "--include-partial-messages"],
                    workingDirectory: FilePath(cwd),
                    platformOptions: opts,
                    output: .sequence,
                    error: .sequence
                ) { execution, stdout, stderr in
                    async let _ = collectStderr(stderr)   // дренировать конкурентно — иначе stall на pipe
                    for try await line in stdout.lines(encoding: UTF8.self) {
                        guard !line.isEmpty else { continue }
                        continuation.yield(ClaudeEventDecoder.decode(line))
                    }
                }
                guard case .exited(0) = result.terminationStatus else {
                    throw ClaudeRunError.badExit(result.terminationStatus)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }  // UI перестал слушать ⇒ SIGINT ребёнку
    }
}
```

Что здесь несёт нагрузку:

- **`onTermination` → `task.cancel()`** — единственная точка остановки. Consumer бросил стрим (закрыл вкладку, нажал Stop) → отмена Task → teardown → SIGINT → claude дописывает `result` и умирает вместе со своим деревом.
- **stderr дренируется конкурентно** — иначе повторение pipe-deadlock из §1.2 в новой обёртке.

### 2.3 Line-splitting с carry-over

`.lines(encoding:)` у swift-subprocess делает разбиение за вас — но **выставьте щедрый лимит длины строки**: одна stream-json строка (полный assistant-message или result со всей беседой) бывает сотни КБ и до мегабайт. Если режете сырые `Buffer`-чанки сами, правило такое:

```swift
// Инвариант: границы чанков НЕ совпадают с границами строк.
var carry = Data()
for try await chunk in stdout {
    carry.append(contentsOf: chunk)
    while let nl = carry.firstIndex(of: UInt8(ascii: "\n")) {
        let lineData = carry[carry.startIndex..<nl]
        carry.removeSubrange(carry.startIndex...nl)
        // декодировать ТОЛЬКО полную строку; хвост ждёт следующего чанка
        handle(String(decoding: lineData, as: UTF8.self))  // lossy: U+FFFD вместо мусора — ок для логов
    }
}
```

Декодировать по чанку без carry-буфера — значит рвать JSON и UTF-8 последовательности посередине.

### 2.4 Толерантный декодинг

Claude Code добавляет типы событий между версиями. **Неизвестный тип не должен ронять ран.**

```swift
// ПЛОХО — обновление claude ломает приложение
let event = try JSONDecoder().decode(ClaudeEvent.self, from: data)  // throw на новом type

// ХОРОШО — ключуемся по полю type, неизвестное складываем в .unknown и логируем
enum ClaudeEventDecoder {
    static func decode(_ line: String) -> ClaudeEvent {
        guard let data = line.data(using: .utf8),
              let head = try? JSONDecoder().decode(TypeProbe.self, from: data) else {
            return .unknown(type: "?", raw: line)
        }
        switch head.type {
        case "system":       return (try? decodeSystem(data)).map(ClaudeEvent.system) ?? .unknown(type: head.type, raw: line)
        case "assistant":    return (try? decodeAssistant(data)).map(ClaudeEvent.assistant) ?? .unknown(type: head.type, raw: line)
        case "stream_event": return (try? decodeDelta(data)).map(ClaudeEvent.streamDelta) ?? .unknown(type: head.type, raw: line)
        case "result":       return (try? decodeResult(data)).map(ClaudeEvent.result) ?? .unknown(type: head.type, raw: line)
        default:             return .unknown(type: head.type, raw: line)
        }
    }
    private struct TypeProbe: Decodable { let type: String }
}
```

### 2.5 Коалессинг дельт перед SwiftUI

Pull-based стрим даёт естественный backpressure, но для токен-дельт нужна обратная стратегия: **читать быстро, обновлять UI редко**. Одно SwiftUI-обновление на токен — это сотни инвалидаций в секунду и лаг ввода. Дельты копятся в буфер вью-модели и сбрасываются с кадровой каденцией (~16 мс) — механика батчинга и `@Observable`-паттерн разобраны в [главе 03](03-swiftui-architecture.md); отмена и структурная привязка Task к жизни view — в [главе 02](02-swift-concurrency.md).

```swift
@MainActor @Observable
final class RunViewModel {
    private(set) var transcript = ""
    private var pending = ""
    private var flushScheduled = false

    func ingest(_ delta: String) {
        pending += delta
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(16))
            transcript += pending; pending = ""; flushScheduled = false
        }
    }
}
```

---

## 3. File watching: `.foundry/` во многих проектах

### 3.1 FSEvents — один стрим на все проекты

FSEvents спроектирован ровно под нашу задачу — пассивный мониторинг больших деревьев: детекция за 2–4 мс при пренебрежимой цене по батарее/SSD. Правила:

- **Один стрим, массив корней.** `pathsToWatch` принимает массив — все зарегистрированные проекты в одном стриме. Динамически добавлять пути нельзя — при изменении набора проектов стрим **пересоздаётся**.
- **⚠️ Устарело:** `FSEventStreamScheduleWithRunLoop` deprecated с macOS 13. Только `FSEventStreamSetDispatchQueue`.
- **Флаги создания:** `kFSEventStreamCreateFlagUseCFTypes` + `kFSEventStreamCreateFlagFileEvents` (per-file пути и флаги вместо «что-то поменялось в каталоге») + `kFSEventStreamCreateFlagNoDefer`; опционально `kFSEventStreamCreateFlagIgnoreSelf` — приложение само пишет в `.foundry/`, свои же события не нужны.
- **Latency = окно коалессинга ядра.** Для UI-driven refresh — **0.3 с** (наш дефолт): меньше wakeup'ов, события пачками. Поверх — ещё app-debounce (§3.4).
- **Catch-up:** вместо `kFSEventStreamEventIdSinceNow` можно передать персистентный `sinceWhen` event ID — журнал FSEvents переживает перезапуски. Но журнал имеет пределы, поэтому catch-up **всегда** дублируется reconcile-сканом на старте (§3.4) — и тогда `sinceWhen` становится оптимизацией, а не корректностью.
- **Обязательные к обработке флаги:** `MustScanSubDirs`, `UserDropped`, `KernelDropped` — ядро дропнуло события, поддерево обязано быть пересканировано; `RootChanged` — сам наблюдаемый каталог переехал/удалён.

```swift
final class FSEventsWatcher: Sendable {
    struct Event: Sendable { let path: String; let flags: FSEventStreamEventFlags; let id: FSEventStreamEventId }

    static func events(paths: [String], latency: TimeInterval = 0.3,
                       queue: DispatchQueue) -> AsyncStream<[Event]> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1024)) { continuation in
            final class Box { let yield: ([Event]) -> Void; init(_ y: @escaping ([Event]) -> Void) { yield = y } }
            let box = Box { continuation.yield($0) }
            var ctx = FSEventStreamContext()
            ctx.info = Unmanaged.passRetained(box).toOpaque()

            let callback: FSEventStreamCallback = { _, info, count, pathsPtr, flags, ids in
                let box = Unmanaged<Box>.fromOpaque(info!).takeUnretainedValue()
                let paths = Unmanaged<CFArray>.fromOpaque(pathsPtr).takeUnretainedValue() as! [String]
                box.yield((0..<count).map { Event(path: paths[$0], flags: flags[$0], id: ids[$0]) })
            }
            let stream = FSEventStreamCreate(nil, callback, &ctx,
                paths as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                latency,
                FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes
                    | kFSEventStreamCreateFlagFileEvents
                    | kFSEventStreamCreateFlagNoDefer))!
            FSEventStreamSetDispatchQueue(stream, queue)     // run-loop вариант deprecated
            FSEventStreamStart(stream)
            continuation.onTermination = { _ in
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                Unmanaged<Box>.fromOpaque(ctx.info!).release()
            }
        }
    }
}
```

Своя обёртка — ~150 строк и ноль зависимостей; из готовых живы FSEventsWrapper (Frizlab) и FSWatcher (okooo5km), оба тонкие.

### 3.2 DispatchSource (kqueue) — для одиночных файлов

Когда важен один конкретный файл с мгновенной реакцией (например, `state.json`, который приложение «тейлит») — `DispatchSource.makeFileSystemObjectSource(fileDescriptor:eventMask:queue:)` по открытому fd, маска `.write/.delete/.rename/.extend`. Не рекурсивен, стоит один fd на объект.

**Ловушка atomic save:** редакторы, git и почти все писатели state-файлов пишут во временный файл и делают `rename(2)` поверх цели. Ваш открытый fd теперь указывает на **старый, unlink-нутый inode**: приходит `.rename`/`.delete` — и дальше тишина навсегда.

```swift
// ПЛОХО — после первого atomic save источник наблюдает мёртвый inode
let fd = open(path, O_EVTONLY)
let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write], queue: q)
src.setEventHandler { reload() }
src.activate()

// ХОРОШО — на rename/delete: закрыть, переоткрыть путь, перевзвести источник
src.setEventHandler { [weak self] in
    let ev = src.data
    if ev.contains(.rename) || ev.contains(.delete) {
        self?.rearm(path: path)      // cancel → close(fd) → open(path) → новый source
    } else {
        self?.reload()
    }
}
```

С FSEvents та же запись выглядит как `ItemRenamed` (часто пара: temp-путь + целевой путь) — правило: **rename-событие на интересующем пути = «перечитай путь»**, а не «примени дельту».

Выбор: много деревьев, рекурсивно, с коалессингом → FSEvents; один файл, мгновенно → DispatchSource + reopen-танец.

### 3.3 ⚠️ NSFilePresenter — не использовать

`NSFilePresenter` видит только изменения, сделанные **через `NSFileCoordinator`** другими кооперирующими процессами (его design center — iCloud/документы). CLI-инструменты, git, claude, обычные редакторы не координируются — **нотификаций не будет вообще**. Плюс задокументированные годами баги и блокирующие сценарии. Для `.foundry/` — непригоден, точка.

### 3.4 Шторма событий, debounce и парадигма reconcile

Checkout, rebase, claude, редактирующий десятки файлов — это тысячи событий за секунды. Оборона в три слоя:

1. **FSEvents latency 0.3 с** — коалессинг на уровне ядра.
2. **Фильтрация путей до debounce:** игнорировать `.git/**` целиком, кроме крошечного allowlist (`HEAD`, `refs/**`, `index` — дёшево детектирует смену ветки/коммита, см. §5); игнорировать редакторские temp-паттерны (`~`, `.swp`, `.tmp`, vim'овский `4913`).
3. **App-debounce ~300 мс:** изменённые пути копятся в `Set`, обработка — после периода тишины (trailing debounce на `Task.sleep` или `debounce` из swift-async-algorithms).

И главный принцип, на котором держится вся подсистема:

> **События — подсказки. Правда — файлы.** Consumer устроен как «dirty-set → reconcile»: проснулись — stat/скан затронутых путей — diff против SQLite-проекции — запись расхождений. Никогда не «проиграть каждое событие по очереди».

Что это даёт: пропущенные события (`KernelDropped`), catch-up после запуска приложения и кнопка «Refresh» — **один и тот же код**. Система, которая доверяет событиям, а не файлам, расходится с реальностью тихо и навсегда; система «события лишь будят реконсайлер» самовосстанавливается при любом сбое.

```swift
actor FoundryReconciler {
    private var dirty = Set<String>()
    private var debounceTask: Task<Void, Never>?

    func mark(_ paths: some Sequence<String>) {
        dirty.formUnion(paths)
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))     // trailing debounce
            guard !Task.isCancelled else { return }
            await reconcile(paths: consumeDirty())
        }
    }
    private func consumeDirty() -> Set<String> { defer { dirty.removeAll() }; return dirty }

    private func reconcile(paths: Set<String>) async {
        // 1. перечитать затронутые файлы .foundry/ (правда)
        // 2. при затронутом .git-allowlist — git status --porcelain=v2 -z (§5)
        // 3. diff против проекции → батч-запись в GRDB (§4)
    }

    func fullReconcile() async { await reconcile(paths: allRegisteredRoots()) } // старт, Refresh, Dropped-флаги
}
```

---

## 4. SQLite-проекция: GRDB 7.x

### 4.1 Почему GRDB

**GRDB 7.x** (7.11+ на середину 2026; Swift 6+/Xcode 16.3+, macOS 10.15+) — активно сопровождается, Sendable-аудит всего API — заголовочная фича седьмой версии. Для проекционной БД, питающей SwiftUI, попадание точное:

| Требование | Механизм GRDB |
|---|---|
| Писатель (reconciler) не блокирует чтения UI | `DatabasePool` + WAL: один сериализованный writer, N snapshot-читателей, без `SQLITE_BUSY` внутри процесса |
| БД → SwiftUI реактивно | `ValueObservation` на любой запрос; в GRDB 7 колбэки **`@MainActor` по умолчанию**; `observation.values(in:)` — AsyncSequence для `.task {}` |
| Эволюция схемы | `DatabaseMigrator`: именованные append-only миграции; `eraseDatabaseOnSchemaChange = true` в DEBUG |
| Проекционная «высота» | записи — plain structs (`Codable` + `FetchableRecord`/`PersistableRecord`), сырой SQL первоклассен (`SQL`-интерполяция), upsert/bulk — без ORM-борьбы |

```swift
// Setup — один DatabasePool на приложение, инжектируется
let dbURL = try FileManager.default
    .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    .appending(path: Bundle.main.bundleIdentifier!, directoryHint: .isDirectory)
    .appending(path: "projection.sqlite")
var config = Configuration()
config.busyMode = .timeout(5)
let pool = try DatabasePool(path: dbURL.path, configuration: config)   // WAL — дефолт пула

var migrator = DatabaseMigrator()
#if DEBUG
migrator.eraseDatabaseOnSchemaChange = true
#endif
migrator.registerMigration("v1") { db in
    try db.create(table: "project") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("path", .text).notNull().unique()
        t.column("lastScanAt", .datetime)
    }
    try db.create(table: "task") { t in
        t.autoIncrementedPrimaryKey("id")
        t.belongsTo("project", onDelete: .cascade)
        t.column("slug", .text).notNull()
        t.column("status", .text).notNull()
        t.column("updatedAt", .datetime).notNull()
    }
}
try migrator.migrate(pool)
```

```swift
// БД → SwiftUI: ValueObservation как AsyncSequence, доставка на main actor
@MainActor @Observable
final class ProjectTasksModel {
    private(set) var tasks: [TaskRow] = []
    func observe(projectId: Int64, in pool: DatabasePool) async throws {
        let observation = ValueObservation.tracking { db in
            try TaskRow.filter(Column("projectId") == projectId)
                       .order(Column("updatedAt").desc).fetchAll(db)
        }
        for try await rows in observation.values(in: pool) { tasks = rows }
    }
}
```

### 4.2 БД — кэш, а не источник правды

Проекция производна от `.foundry/`-файлов и git. Следствия:

- Живёт в `~/Library/Application Support/<bundle-id>/` (рядом `-wal`/`-shm`); можно пометить `isExcludedFromBackup` — перестраиваемое не стоит churn'а Time Machine.
- Хранить `projectionVersion` (user pragma или таблица meta). Несовместимый бамп → **удалить файл и перестроить** через `fullReconcile()`, а не писать сложные data-миграции. `DatabaseMigrator` — для дешёвых структурных случаев.
- Ни одно поле не должно быть «только в БД»: если данные нельзя восстановить из файлов/git — им место не в проекции, а в файлах (§8.3).

```swift
// ПЛОХО — уникальное состояние в кэше: снос БД = потеря данных пользователя
try db.execute(sql: "UPDATE task SET userNote = ? WHERE id = ?", arguments: [note, id])

// ХОРОШО — заметка едет в .foundry/ (правда), reconciler занесёт её в проекцию
try noteStore.write(note, for: taskSlug, in: projectDir)   // файл в .foundry/
await reconciler.mark([projectDir])
```

### 4.3 ⚠️ Почему не SwiftData

SwiftData к 2026 дозрел эволюционно, но остаётся Core-Data-производным object-graph-фреймворком — «data is an object» против нужного нам «data is a database». Дисквалификаторы для проекции:

- нет низкоуровневого SQL / upsert-heavy bulk-rebuild пути (проекция = частый truncate/rebuild от внешней правды);
- миграции ограничены (и заперты на lightweight, если когда-либо включится CloudKit);
- наблюдение — по object identity, а не по запросу; `ValueObservation`-эквивалента нет;
- на macOS сохраняются шероховатости, на bulk-записях — стабильные жалобы на перфоманс.

Показательно, что **SQLiteData / SharingGRDB (Point-Free)** существует именно как «SwiftData replacement built on GRDB» — если захочется `@Query`-стиля property wrapper'ов поверх GRDB, это готовая альтернатива (как и GRDBQuery). SQLite.swift жив, но без observation и с более слабой concurrency-историей; raw C API — только если нужно три запроса и ноль зависимостей.

---

## 5. Git: шелл к CLI, а не libgit2

### 5.1 Прецедент индустрии

GitHub Desktop (bundled git + dugite), Fork, Tower, Sublime Merge, VS Code — все драйвят **git CLI** и парсят машинные форматы. Заметное исключение — GitUp на libgit2, и он периодически страдает от дрейфа поведения относительно современного git.

### 5.2 ⚠️ Почему не SwiftGit2/libgit2

- SwiftGit2 сопровождается **спорадически** (длинные паузы, SPM/Apple-Silicon-фрикция породила форки — SwiftGit3, sharplet/swift-git).
- libgit2 отстаёт от git по фичам (sparse checkout, fsmonitor, новые семантики config) и — критично — **не читает конфигурацию пользователя так, как git CLI**: credential helpers, ssh-настройки, includeIf. Клиент, который ведёт себя иначе, чем git в терминале того же пользователя, — фабрика багов.
- Пришлось бы шипить и патчить libgit2 + libssh2 + openssl самостоятельно.

У приложения уже есть первоклассный subprocess-слой (§1) — git обязан ехать через него.

### 5.3 Правила вызова

- Резолв бинаря: user override → `/usr/bin/git` (CLT-шим есть всегда; **но** при отсутствующем CLT шим показывает диалог установки — сначала проверить `xcode-select -p`) → Homebrew git.
- `git -C <repoPath> …` вместо workingDirectory, где удобно.
- Гигиена окружения фоновых вызовов: `GIT_TERMINAL_PROMPT=0` (никаких интерактивных запросов пароля из GUI), `GIT_OPTIONAL_LOCKS=0` (фоновый status **не имеет права** брать локи и мешать пользовательскому git), `LC_ALL=C` (стабильный парсинг).

```swift
func gitStatus(repo: String) async throws -> GitStatus {
    let result = try await run(
        .path(FilePath(gitPath)),
        arguments: ["-C", repo, "status", "--porcelain=v2", "-z",
                    "--branch", "--untracked-files=all"],
        environment: .inherit.updating([
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_OPTIONAL_LOCKS": "0",
            "LC_ALL": "C",
        ]),
        output: .string(limit: 16 * 1024 * 1024)
    )
    guard case .exited(0) = result.terminationStatus else { throw GitError.status(result) }
    return GitStatusParser.parse(porcelainV2Z: result.standardOutput ?? "")
}
```

### 5.4 Парсинг: только машинные форматы

- **`--porcelain=v2 -z`** — задокументированный формат со **стабильностью, гарантированной git**: заголовки `# branch.head` / `# branch.ab` (ahead/behind), типы записей `1` (изменён) / `2` (rename/copy) / `u` (unmerged) / `?` / `!`. `-z` (NUL-терминация) снимает весь класс проблем с quoting/escaping путей — пробелы, кавычки, юникод.
- Диффы: `git diff --no-color --no-ext-diff -U3`, парсить unified-ханки (`@@ -a,b +c,d @@`) — формат стабилен; `-M -C` для rename/copy; списки файлов — `--name-status -z`. Word-level подсветку делать **на клиенте** (Myers/diff-match-patch по строкам ханка), а не парсить `--word-diff`.
- Лог: кастомные NUL-форматы `git log --format=%H%x00%P%x00%an%x00%aI%x00%s%x00 -z` — надёжнее любого парсинга дефолтного вывода.
- Триггер повторного status — FSEvents-allowlist из §3.4: `.git/HEAD` + `.git/refs/**` (+ `index`).

```swift
// ПЛОХО — человеческий вывод: локали, конфиги, столбцы, quoting
let out = try await git(["status"])                    // "On branch master\nnothing to commit…"

// ХОРОШО — стабильный контракт
let out = try await git(["status", "--porcelain=v2", "-z", "--branch"])
```

---

## 6. WKWebView-остров: markdown и diff-ревью

### 6.1 Почему не native

`AttributedString(markdown:)` — инлайн-стили, ссылки, базовые списки; **нет таблиц, подсветки кода, картинок по умолчанию, HTML** — годится для однострочных саммари, не для GitHub-уровня рендера. Native-стек `swift-markdown-ui` + `Highlightr`/`Splash` дотягивает read-only markdown-панели. Но **line-anchored ревью** — gutter-комментарии, per-line hover, word-level diff-раскраска, sticky-заголовки ханков, виртуализация 10k-строчных диффов — это ровно то, что HTML/CSS/JS делает хорошо, а SwiftUI мучительно.

**Вердикт:** WKWebView-острова для markdown-с-кодом и diff-ревью; native SwiftUI для всего структурного (списки, сайдбары, тулбары, статусы).

### 6.2 Load-once shell через WKURLSchemeHandler + CSP

Три способа загрузки локального контента и наш выбор:

| Способ | Оценка |
|---|---|
| `loadHTMLString(_:baseURL: nil)` | null origin, максимальная изоляция; но перезагрузка всей строки на каждое обновление — расточительно |
| `loadFileURL(_:allowingReadAccessTo:)` | работает, но file://-origin с причудами и реальный файловый scope |
| **`WKURLSchemeHandler`** | кастомная схема `foundry-asset://`: свой origin, ноль файлового доступа, полный контроль, дружит с CSP — **наш вариант** |

Форма решения: **один статический HTML-shell на тип острова** (markdown-view, diff-view), грузится **однажды** через scheme handler; все обновления контента — по JS-мосту. Никогда не перегружать HTML на каждое сообщение.

```swift
final class FoundryAssetHandler: NSObject, WKURLSchemeHandler {
    private let payloads = PayloadStore()   // uuid → Data, для pull больших диффов (§6.3)

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let (data, mime): (Data, String) = switch url.host {
        case "shell":   (bundledAsset(url.path), mimeType(url.path))       // JS/CSS/шрифты из бандла
        case "payload": (payloads.take(url.lastPathComponent), "application/json")
        default:        (Data(), "text/plain")
        }
        var headers = ["Content-Type": mime, "Content-Length": "\(data.count)"]
        headers["Content-Security-Policy"] =
            "default-src 'none'; script-src foundry-asset:; " +
            "style-src foundry-asset: 'unsafe-inline'; img-src foundry-asset: data:; connect-src foundry-asset:"
        task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                        headerFields: headers)!)
        task.didReceive(data)
        task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

// Регистрация — строго ДО создания webview
let config = WKWebViewConfiguration()
config.setURLSchemeHandler(FoundryAssetHandler(), forURLScheme: "foundry-asset")
```

Строгий CSP — вторая линия обороны: даже если в markdown от claude/диффа просочится активный контент, ему некуда экфильтровать (`default-src 'none'`, сеть закрыта — наружу схема не резолвится).

### 6.3 Мост Swift ⇄ JS

**Swift → JS: только `callAsyncJavaScript`.** Аргументы передаются словарём и маршалятся как JSON — **класс багов со string-escaping не существует**:

```swift
// ПЛОХО — конкатенация: кавычка/бэктик/U+2028 в markdown ломает или инжектит скрипт
webView.evaluateJavaScript("renderMarkdown('\(markdown)')")

// ХОРОШО — аргументы без эскейпинга, результат по await, целевой content world
try await webView.callAsyncJavaScript(
    "return renderMarkdown(payload, opts)",
    arguments: ["payload": markdownString, "opts": ["theme": "dark"]],
    contentWorld: .page)
```

**JS → Swift: `WKScriptMessageHandlerWithReply`** — `postMessage` возвращает Promise, резолвящийся из Swift; request/response для «клик по строке 42 → Swift ставит якорь комментария»:

```swift
final class BridgeHandler: NSObject, WKScriptMessageHandlerWithReply {
    func userContentController(_ ucc: WKUserContentController,
                               didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return (nil, "bad message") }
        switch action {
        case "lineClicked":
            let anchor = await ReviewModel.shared.addAnchor(line: body["line"] as? Int ?? 0)
            return (["anchorId": anchor.id], nil)
        default: return (nil, "unknown action \(action)")
        }
    }
}
config.userContentController.addScriptMessageHandler(BridgeHandler(), contentWorld: .page, name: "bridge")
// JS: const {anchorId} = await window.webkit.messageHandlers.bridge.postMessage({action:"lineClicked", line:42})
```

Мостовой glue-код держите в отдельном `WKContentWorld` (`.defaultClient` или кастомном), чтобы page-world скрипты (сторонний highlighter) не могли трогать/спуфить хендлеры; DOM-манипулирующий рендер живёт в `.page`.

**Большие payload'ы — pull вместо push.** `callAsyncJavaScript` спокойно тянет сотни КБ (один IPC-месседж). Для многомегабайтных диффов — инверсия: Swift кладёт payload в `PayloadStore`, JS забирает `fetch("foundry-asset://payload/<uuid>")` через scheme handler и парсит инкрементально. Стриминг claude-вывода в остров — батчами: один `appendChunk`-вызов на ≥16 мс накопленных дельт (§2.5).

### 6.4 Dark mode, навигация, пул

- **Dark mode наследуется**: WKWebView резолвит `prefers-color-scheme` из effective appearance окна — `@media (prefers-color-scheme: dark)` работает, включая живое переключение. Для акцентного цвета — пушить CSS custom properties из Swift (`NSColor.controlAccentColor` → `--accent`) в `viewDidChangeEffectiveAppearance`. Белую вспышку при загрузке убирает `webView.setValue(false, forKey: "drawsBackground")` (давний, всё ещё актуальный приём) или macOS 12+ `underPageBackgroundColor` + фон в CSS шелла.
- **Навигация запрещена**: `decidePolicyFor` — `.allow` только своей схеме и `about:blank`; http(s)-ссылки → `NSWorkspace.shared.open`. `allowsBackForwardNavigationGestures = false`. Контекстное меню — сабкласс WKWebView, `willOpenMenu(_:with:)`: оставить Copy, выкинуть Reload/Open Link (поддерживаемого конфиг-флага нет, override — стандартный путь).
- **Пул 2–4 webview.** WebKit многопроцессен; каждый web content process — ~30–80 МБ. Общий `WKProcessPool` на одной разделяемой `WKWebViewConfiguration`; острова **переиспользуются** (recycle офскринных), никогда не по одному на строку списка. `webView.isInspectable = true` в DEBUG — Safari Web Inspector.

---

## 7. Sandbox: вердикт — OFF

### 7.1 Что сломала бы песочница

Всё ядро приложения:

- **Дети наследуют песочницу** (`com.apple.security.inherit`): `claude`, `foundry`, `git`, `node` запустились бы внутри нашего контейнера — без доступа к `~/.claude`, `~/.gitconfig`, ssh-ключам, каталогам проектов, Homebrew-путям. Практический итог: **произвольные пользовательские CLI из sandboxed-приложения не работают.** Единственный санкционированный MAS-паттерн — `NSUserUnixTask`-скрипты в `~/Library/Application Scripts/` — неприемлем для core loop.
- Наблюдение произвольных каталогов потребовало бы security-scoped bookmarks per-project с ре-резолвом каждый запуск — UX-налог «выдай грант на каждый проект», ломается на переименованиях.

### 7.2 Что делают аналоги, и что делаем мы

Tower, Fork, VS Code, GitHub Desktop, iTerm2, GitUp — **все non-sandboxed, Developer ID + notarization, вне Mac App Store** (Tower ушёл из MAS именно из-за песочницы). Наш пакет:

- **Developer ID signing + notarization (`notarytool`) + Hardened Runtime** (обязателен для нотаризации; спавну подпроцессов и файловому доступу не мешает). Опасные hardened-runtime-исключения не нужны: WKWebView JIT'ует в своём out-of-process — `com.apple.security.cs.allow-unsigned-executable-memory` держать **OFF**.
- **TCC всё равно действует**: первый доступ к `~/Desktop`, `~/Documents`, `~/Downloads`, сетевым томам — per-app consent-промпт (usage-descriptions в Info.plist). Проекты под `~/Projects`-подобными путями не промптят ничего. Full Disk Access не запрашиваем.
- Обновления — Sparkle 2.x. Детали подписи, нотаризации и дистрибуции — [глава 08](08-project-tooling-distribution.md).

---

## 8. Разное: login item, listener для hooks, секреты

### 8.1 SMAppService (macOS 13+)

`SMAppService` заменил `SMLoginItemSetEnabled`/`SMJobBless`. Launch at login: `SMAppService.mainApp.register()` / `.unregister()`. Пункт появляется в System Settings → Login Items, **пользователь может выключить его там** — поэтому:

```swift
// ПЛОХО — свой кэшированный bool расходится с System Settings
@AppStorage("launchAtLogin") var launchAtLogin = false

// ХОРОШО — правда всегда в .status
var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }
// .requiresApproval → SMAppService.openSystemSettingsLoginItems()
```

Дефолт — **выключено**; регистрировать только по явному opt-in. Отдельный launchd-агент (plist в `Contents/Library/LaunchAgents/`, `SMAppService.agent(plistName:)`) на старте не нужен — menu-bar-capable основное приложение покрывает «держать проекции свежими».

### 8.2 NWListener для hooks-коллбеков Claude Code

Hooks Claude Code коллбечат приложение по HTTP. Правила листенера:

```swift
let params = NWParameters.tcp
params.allowLocalEndpointReuse = true
params.requiredLocalEndpoint = NWEndpoint.hostPort(
    host: .ipv4(.loopback),     // 127.0.0.1 ТОЛЬКО — никогда 0.0.0.0
    port: .any)                 // порт 0 ⇒ эфемерный от ОС, ноль коллизий с dev-серверами
let listener = try NWListener(using: params)
listener.stateUpdateHandler = { state in
    if case .ready = state, let port = listener.port {
        CallbackConfig.shared.publish(port: port.rawValue, token: Self.perLaunchToken)
    }
}
listener.newConnectionHandler = { conn in handleHTTP(conn) }  // один POST-endpoint: ~50 строк парсинга
listener.start(queue: .main)
```

Модель безопасности — два слоя:

1. **Loopback-only binding** — граница от внешней сети.
2. **Per-launch bearer token**: случайный токен генерируется при старте листенера и уезжает **в окружение спавненных процессов** — `FOUNDRY_APP_CALLBACK=http://127.0.0.1:<port>`, `FOUNDRY_APP_TOKEN=<token>` (hooks наследуют env); запросы без токена — 401. Это закрывает классический класс атак «другой локальный пользователь / cross-origin на localhost». TLS для loopback с токеном не нужен.

Эфемерный порт лучше фиксированного, потому что hook-эмиттеры спавним **мы** — актуальный порт всегда инжектируется. Если разрастётся до роутинга/keep-alive — FlyingFox (async/await SPM HTTP-сервер); Vapor/Hummingbird — оверкилл. Non-sandboxed ⇒ entitlement не нужен; Local Network privacy-промпты macOS 15+ к loopback не применяются.

### 8.3 Keychain и конфиги

- **Keychain — только для секретов самого приложения** (например, токен телеметрии). `kSecClassGenericPassword` + **`kSecUseDataProtectionKeychain: true`** — data-protection keychain вместо legacy file-based с его ACL-диалогами «MyApp wants to use your confidential information». **`claude` управляет своим auth сам** (свой keychain item / `~/.claude`) — приложение не трогает Anthropic-креды вообще: подпроцесс наследует логин пользователя.
- Секретам не место в UserDefaults (plaintext plist, читается любым процессом пользователя на unsandboxed-машине).
- Правило размещения не-секретов: тумблер → UserDefaults/`@AppStorage`; структурное/версионируемое (список проектов, per-project настройки — JSON c `version`) → `~/Library/Application Support/<bundle-id>/`; производный кэш → `~/Library/Caches/`; настройки, которые должны ехать с проектом → `.foundry/` в репозитории. App groups для однопроцессного unsandboxed-приложения не нужны вовсе.

---

## Чеклист ревью

Вопросы к любому PR, трогающему интеграционный слой:

**Подпроцессы**
- [ ] Запуск через swift-subprocess? (`Process`/NSTask — реджект)
- [ ] Долгоживущий ребёнок: задан `teardownSequence` (SIGINT → SIGTERM → SIGKILL) и `createSession = true`? Отмена внешнего `Task` действительно доходит до `run(...)`?
- [ ] Собранный вывод — с `limit:`? Стримовый stderr дренируется конкурентно со stdout?
- [ ] `workingDirectory:` per-invocation, без `changeCurrentDirectoryPath`?
- [ ] Бинарь резолвится через `ToolLocator` (override → probe → login-shell), а не `.name()`/захардкоженный путь?
- [ ] Exit-коды foundry маппятся по контракту 0/1/2/64; код 64 трактуется как наш баг?

**Стриминг claude**
- [ ] Line-splitting с carry-over буфером / `.lines()` с щедрым лимитом длины строки?
- [ ] Неизвестный тип события падает в `.unknown`, а не роняет ран?
- [ ] `onTermination` стрима отменяет Task с процессом? SIGINT — первым?
- [ ] Токен-дельты коалессируются перед SwiftUI (не по обновлению на токен)?

**File watching**
- [ ] `FSEventStreamSetDispatchQueue`, не run-loop вариант?
- [ ] Обрабатываются `MustScanSubDirs`/`UserDropped`/`KernelDropped` (→ рескан) и `RootChanged`?
- [ ] Debounce ~300 мс поверх latency 0.3 с? Фильтрация `.git/**` (кроме allowlist) и temp-файлов — до debounce?
- [ ] Consumer — «dirty-set → reconcile», а не проигрывание событий? Старт/Refresh/Dropped идут тем же reconcile-путём?
- [ ] DispatchSource-вотчер переоткрывает fd после rename/delete? NSFilePresenter нигде не появился?

**БД**
- [ ] БД используется как перестраиваемый кэш — ни одного поля, невосстановимого из файлов/git?
- [ ] Несовместимая схема → снос и rebuild, а не героическая миграция? `projectionVersion` проверяется?
- [ ] Записи батчатся в write-транзакции пула; UI читает через `ValueObservation`, не поллит?

**Git**
- [ ] Только машинные форматы (`--porcelain=v2 -z`, NUL-форматы log), никакого парсинга человеческого вывода?
- [ ] Фоновые вызовы: `GIT_OPTIONAL_LOCKS=0`, `GIT_TERMINAL_PROMPT=0`, `LC_ALL=C`?

**WKWebView**
- [ ] Shell грузится один раз через scheme handler; обновления — через `callAsyncJavaScript` со словарём аргументов (не конкатенация строк)?
- [ ] CSP строгий (`default-src 'none'`)? Многомегабайтные payload'ы — pull через scheme handler?
- [ ] Навигация запрещена, внешние ссылки → NSWorkspace? Webview берётся из пула, не создаётся на элемент списка?

**Listener / секреты / login item**
- [ ] Listener: только `.loopback`, порт 0, per-launch token в env спавненных процессов, 401 без токена?
- [ ] Keychain (`kSecUseDataProtectionKeychain`) — только для app-собственных секретов; auth claude не трогаем?
- [ ] Login-item UI читает `SMAppService.mainApp.status`, не кэширует bool?

---

## Источники

- swift-subprocess: https://github.com/swiftlang/swift-subprocess · SF-0007: https://github.com/swiftlang/swift-foundation/blob/main/Proposals/0007-swift-subprocess.md · обзоры: https://mjtsai.com/blog/2025/10/30/swift-6-2-subprocess/ · https://blog.jacobstechtavern.com/p/swift-subprocess · ревью: https://forums.swift.org/t/review-3rd-sf-0007-subprocess/78078
- Process/pipe-deadlock (Quinn): https://developer.apple.com/forums/thread/690310 · NSTask-internal deadlock: https://developer.apple.com/forums/thread/695702 · Swift 6 + readabilityHandler: https://forums.swift.org/t/swift-6-concurrency-nspipe-readability-handlers/59834
- GUI PATH / launchd: https://gist.github.com/riaf/cf662d965ebd1b8b47453dd79cdd5578 · https://www.bounga.org/tips/2020/04/07/instructs-mac-os-gui-apps-about-path-environment-variable/
- claude headless / stream-json: https://code.claude.com/docs/en/headless · https://backgroundclaude.com/blog/stream-json
- FSEvents: https://alexwlchan.net/2026/watch-files-on-macos/ · https://developer.apple.com/documentation/coreservices/1443980-fseventstreamcreate · https://github.com/Frizlab/FSEventsWrapper · https://github.com/okooo5km/FSWatcher
- NSFilePresenter/координация: https://developer.apple.com/documentation/foundation/nsfilepresenter · https://khanlou.com/2019/03/file-coordination/ · https://www.objc.io/issues/10-syncing-data/icloud-document-store/
- GRDB: https://github.com/groue/GRDB.swift · https://github.com/groue/GRDB.swift/blob/master/Documentation/GRDB7MigrationGuide.md · https://swiftpackageindex.com/groue/GRDB.swift/v7.6.1/documentation/grdb/swiftconcurrency · SharingGRDB vs SwiftData: https://swiftpackageindex.com/pointfreeco/sharing-grdb/0.1.0/documentation/sharinggrdb/comparisonwithswiftdata
- SwiftData-оценка: https://fatbobman.com/en/posts/key-considerations-before-using-swiftdata/ · https://brightdigit.com/articles/swiftdata-considerations/
- Git porcelain v2: https://git-scm.com/docs/git-status#_porcelain_format_version_2 · SwiftGit2: https://github.com/SwiftGit2/SwiftGit2
- WKWebView: https://www.hackingwithswift.com/articles/112/the-ultimate-guide-to-wkwebview · scheme handler: https://www.gfrigerio.com/custom-url-schemes-in-a-wkwebview/ · dark mode: https://useyourloaf.com/blog/supporting-dark-mode-in-wkwebview/ · content worlds: https://www.sobyte.net/post/2022-02/ios-wkwebview/
- Sandbox/дистрибуция: https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox · https://www.appcoda.com/mac-app-sandbox/ · https://gist.github.com/rsms/929c9c2fec231f0cf843a1a746a416f5 · https://blog.xojo.com/2024/08/22/macos-apps-from-sandboxing-to-notarization-the-basics/
- SMAppService: https://nilcoalescing.com/blog/LaunchAtLoginSetting/ · https://theevilbit.github.io/posts/smappservice/
- NWListener: http://www.alwaysrightinstitute.com/network-framework/ · https://developer.apple.com/forums/thread/706865
