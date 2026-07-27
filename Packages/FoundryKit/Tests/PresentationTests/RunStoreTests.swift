import Application
import Domain
import Testing

@testable import Presentation

/// Раннер со скриптованными событиями — весь `claude -p` заменён массивом
/// доменных событий, так логика стора (сшивка дельт, привязка результата тула,
/// дедуп неизвестных, переходы фаз) проверяется без подпроцесса.
private struct ScriptedRunner: AgentRunner {
    let events: [AgentEvent]
    var error: Error?

    func stream(
        prompt: String,
        projectDirectory: String,
        permissionMode: PermissionMode
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            if let error { continuation.finish(throwing: error) } else { continuation.finish() }
        }
    }
}

/// Шпион порта открытия сессии: запоминает вызов вместо реального
/// `claude://resume`. Так проверяется ветка `opensSessionInViewer`, не поднимая
/// Claude Code Desktop.
@MainActor
private final class SpySessionOpener: AgentSessionOpening {
    private(set) var opened: (sessionID: String, projectDirectory: String)?
    private(set) var openedNowID: String?
    func openSession(sessionID: String, projectDirectory: String) async {
        opened = (sessionID, projectDirectory)
    }
    func openSessionNow(sessionID: String) { openedNowID = sessionID }
}

/// In-memory фейк порта настроек: тесты не трогают глобальный
/// `UserDefaults.standard` — флаг живёт только в этом словаре.
private final class InMemoryPreferences: PreferenceStore {
    private var store: [String: Bool] = [:]
    func bool(forKey key: String) -> Bool? { store[key] }
    func setBool(_ value: Bool, forKey key: String) { store[key] = value }
}

@MainActor
@Suite("RunStore")
struct RunStoreTests {

    @Test("Старт сессии с opensSessionInViewer открывает её через порт")
    func opensSessionThroughPortWhenEnabled() async {
        let opener = SpySessionOpener()
        let store = RunStore(
            runService: RunService(
                runner: ScriptedRunner(events: [
                    .sessionStarted(
                        SessionStart(sessionID: "s1", model: "opus", projectDirectory: "/tmp/project")),
                    .finished(.ok()),
                ]),
                sessionOpener: opener
            ),
            preferences: InMemoryPreferences()
        )
        store.opensSessionInViewer = true
        store.prompt = "промпт"
        store.start(projectDirectory: "/tmp/project")
        // Ждём и терминальной фазы, и записи вызова: опенер зовётся из отдельной Task.
        for _ in 0..<400 where store.phase.isRunning || opener.opened == nil {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(opener.opened?.sessionID == "s1")
        #expect(opener.opened?.projectDirectory == "/tmp/project")
    }

    @Test("Без opensSessionInViewer порт не зовётся")
    func doesNotOpenSessionWhenDisabled() async {
        let opener = SpySessionOpener()
        let store = RunStore(
            runService: RunService(
                runner: ScriptedRunner(events: [
                    .sessionStarted(
                        SessionStart(sessionID: "s1", model: "opus", projectDirectory: "/tmp/project")),
                    .finished(.ok()),
                ]),
                sessionOpener: opener
            ),
            preferences: InMemoryPreferences()
        )
        store.opensSessionInViewer = false
        store.prompt = "промпт"
        store.start(projectDirectory: "/tmp/project")
        for _ in 0..<400 where store.phase.isRunning {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(opener.opened == nil)
    }

    @Test("Кнопка «открыть результат в CCD» идёт через порт немедленным вызовом")
    func openResultInDesktopGoesThroughPort() async {
        let opener = SpySessionOpener()
        let store = RunStore(
            runService: RunService(
                runner: ScriptedRunner(events: [
                    .sessionStarted(
                        SessionStart(sessionID: "s7", model: "opus", projectDirectory: "/tmp/project")),
                    .finished(.ok()),
                ]),
                sessionOpener: opener
            ),
            preferences: InMemoryPreferences()
        )
        store.opensSessionInViewer = false  // отсекаем автоимпорт — проверяем ручной
        store.prompt = "промпт"
        store.start(projectDirectory: "/tmp/project")
        for _ in 0..<400 where store.phase.isRunning {
            try? await Task.sleep(for: .milliseconds(5))
        }
        store.openResultInDesktop()
        #expect(opener.openedNowID == "s1")  // sessionID из result (.ok())
        #expect(opener.opened == nil)  // автоимпорт не сработал
    }

    /// Гоняет ран до терминальной фазы. Стрим отдаёт события синхронно, но
    /// потребляются они в отдельной Task — уступаем ей управление, пока фаза не
    /// перестанет быть `.running` (с потолком, чтобы тест не завис).
    private func run(_ events: [AgentEvent], error: Error? = nil) async -> RunStore {
        let store = RunStore(
            runService: RunService(
                runner: ScriptedRunner(events: events, error: error),
                sessionOpener: SpySessionOpener()
            ),
            preferences: InMemoryPreferences())
        store.opensSessionInViewer = false  // без побочного открытия сессии в CCD
        store.prompt = "промпт"
        store.start(projectDirectory: "/tmp/project")
        for _ in 0..<400 where store.phase.isRunning {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return store
    }

    @Test("Дельты одного блока сшиваются в один элемент ленты")
    func coalescesDeltasIntoOneItem() async {
        let store = await run([
            .blockStarted(.text), .textDelta("Прив"), .textDelta("ет"),
            .finished(.ok()),
        ])
        #expect(store.feed.count == 1)
        #expect(store.feed.first?.body == "Привет")
        #expect(store.phase == .finished)
    }

    @Test("Результат тула привязывается к последнему tool-элементу без результата")
    func attachesToolResult() async {
        let store = await run([
            .toolUse(name: "Read", inputSummary: "file_path: /a"),
            .toolResult(summary: "ok", isError: false),
            .finished(.ok()),
        ])
        #expect(store.feed.count == 1)
        #expect(store.feed.first?.toolResult == "ok")
        #expect(store.feed.first?.isError == false)
    }

    @Test("Пустой результат тула помечается галочкой")
    func emptyToolResultBecomesCheck() async {
        let store = await run([
            .toolUse(name: "Bash", inputSummary: "command: ls"),
            .toolResult(summary: "", isError: false),
            .finished(.ok()),
        ])
        #expect(store.feed.first?.toolResult == "✓")
    }

    @Test("Неизвестные события одного типа схлопываются в один элемент")
    func deduplicatesUnknownTypes() async {
        let store = await run([
            .unknown(type: "telemetry"), .unknown(type: "telemetry"),
            .unknown(type: "other"), .finished(.ok()),
        ])
        let infoItems = store.feed.filter { $0.kind == .info }
        #expect(infoItems.count == 2)
    }

    @Test("result с is_error → фаза failed")
    func errorResultFailsPhase() async {
        let store = await run([.finished(.error())])
        if case .failed = store.phase {} else { Issue.record("ожидалась .failed, а не \(store.phase)") }
        #expect(store.result?.isError == true)
    }

    @Test("Стрим закрылся без result-события → фаза failed")
    func streamWithoutResultFails() async {
        let store = await run([.blockStarted(.text), .textDelta("хвост")])
        if case .failed = store.phase {} else { Issue.record("ожидалась .failed, а не \(store.phase)") }
    }

    @Test("Ошибка стрима переводит ран в failed")
    func streamErrorFails() async {
        struct Boom: Error {}
        let store = await run([], error: Boom())
        if case .failed = store.phase {} else { Issue.record("ожидалась .failed, а не \(store.phase)") }
    }

    @Test("Пустой промпт не стартует ран")
    func emptyPromptDoesNotStart() {
        let store = RunStore(
            runService: RunService(
                runner: ScriptedRunner(events: []),
                sessionOpener: SpySessionOpener()
            ),
            preferences: InMemoryPreferences())
        store.prompt = "   "
        store.start(projectDirectory: "/tmp/project")
        #expect(store.phase == .idle)
    }

    @Test("Пустой каталог проекта не стартует ран")
    func emptyProjectDirectoryDoesNotStart() {
        let store = RunStore(
            runService: RunService(
                runner: ScriptedRunner(events: []),
                sessionOpener: SpySessionOpener()
            ),
            preferences: InMemoryPreferences())
        store.prompt = "промпт"
        store.start(projectDirectory: "")
        #expect(store.phase == .idle)
    }
}

extension RunResult {
    fileprivate static func ok() -> RunResult {
        RunResult(
            text: "Готово", isError: false, durationMilliseconds: 1000, costUSD: 0.01, turns: 1,
            sessionID: "s1")
    }
    fileprivate static func error() -> RunResult {
        RunResult(text: "", isError: true, durationMilliseconds: 500, costUSD: nil, turns: 0, sessionID: "s1")
    }
}
