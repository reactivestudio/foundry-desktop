import Domain
import Foundation
import Observation

/// Стор одного рана: MV-паттерн, @Observable без ViewModel'ей (practices 03).
/// Сборку ленты держит доменный агрегат `Transcript`; стор — тонкий слой между
/// потоком событий раннера и вью: переводит транспортные события в мутации
/// транскрипта, коалессирует токен-дельты с кадровой каденцией (~16 мс, одна
/// SwiftUI-инвалидация на кадр — practices 06, пункт 2.5) и держит фазу рана.
@MainActor @Observable
public final class RunStore {

    enum Phase: Equatable {
        case idle
        case running
        case finished
        case failed(String)

        var isRunning: Bool { self == .running }
    }

    private(set) var phase: Phase = .idle

    /// Транскрипт рана — единственный источник ленты/сессии/результата.
    /// Наблюдается как единое целое: любая его мутация инвалидирует вью.
    private var transcript = Transcript()

    /// Живая лента элементов для вью.
    var feed: [TranscriptItem] { transcript.items }
    /// Старт сессии текущего рана (nil до `sessionStarted`).
    var session: SessionStart? { transcript.session }
    /// Финальный результат рана (nil до `finished`).
    var result: RunResult? { transcript.result }

    var prompt = ""
    var permissionMode: PermissionMode = .acceptEdits
    /// Импортировать сессию во внешний просмотрщик рана (сегодня — Claude Code
    /// Desktop, deep link claude://resume — docs/ccd-visibility.md; какой именно
    /// просмотрщик — деталь адаптера `AgentSessionOpening`). Пишется в
    /// durable-настройки через порт, а не в `UserDefaults.standard` напрямую.
    var opensSessionInViewer: Bool {
        didSet { preferences.setBool(opensSessionInViewer, forKey: Self.viewerPreferenceKey) }
    }

    /// Строковый ключ настройки неизменен (persisted-значение — миграции нет),
    /// хотя Swift-символ уже вендор-нейтрален.
    private static let viewerPreferenceKey = "openInClaudeDesktop"

    // Зависимости, не состояние: из наблюдения исключены (практики 03).
    @ObservationIgnored private let runner: AgentRunner
    @ObservationIgnored private let sessionOpener: AgentSessionOpening
    @ObservationIgnored private let preferences: PreferenceStore
    private var runTask: Task<Void, Never>?

    /// Кадровая каденция коалессинга дельт (~60 Гц): одна SwiftUI-инвалидация на
    /// кадр, не на токен (practices 06, пункт 2.5).
    private static let deltaFlushInterval = Duration.milliseconds(16)

    private var pendingDelta = ""
    private var flushScheduled = false

    /// Все зависимости инъектируются корнем композиции (`Configuration`):
    /// раннер, опенер сессии и хранилище настроек — это порты `Domain`, за
    /// которыми стоят вендор/инфра-адаптеры. Конкретики-дефолтов НЕТ: UI-слой (этот
    /// модуль) не знает ни одной реализации и зависит только от абстракций
    /// (правило зависимостей). Тест подставляет фейки/шпионов.
    public init(
        runner: AgentRunner,
        sessionOpener: AgentSessionOpening,
        preferences: PreferenceStore
    ) {
        self.runner = runner
        self.sessionOpener = sessionOpener
        self.preferences = preferences
        // Дефолт — включено: смысл фичи в наблюдении рана из просмотрщика.
        // Инициализирующее присваивание не будит didSet — обратной записи дефолта
        // в хранилище нет.
        opensSessionInViewer = preferences.bool(forKey: Self.viewerPreferenceKey) ?? true
    }

    func start(projectDirectory: String) {
        guard !phase.isRunning else { return }
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !projectDirectory.isEmpty else { return }

        phase = .running
        transcript.reset()
        pendingDelta = ""

        let stream = runner.stream(
            prompt: prompt,
            projectDirectory: projectDirectory,
            permissionMode: permissionMode
        )
        runTask = Task { [weak self] in
            do {
                for try await event in stream {
                    self?.ingest(event)
                }
                self?.finishIfStillRunning()
            } catch is CancellationError {
                self?.markStopped()
            } catch {
                self?.fail(error)
            }
        }
    }

    func stop() {
        // Отмена consumer-задачи рвёт стрим → onTermination → SIGINT ребёнку.
        runTask?.cancel()
        runTask = nil
        markStopped()
    }

    /// Открыть завершённую сессию результата в Claude Code Desktop (кнопка на
    /// карточке результата). Идёт через тот же порт, что и автоимпорт при старте, —
    /// вью не знает про deep link, а инфраструктура остаётся за одной границей.
    func openResultInDesktop() {
        guard let sessionID = result?.sessionID else { return }
        sessionOpener.openSessionNow(sessionID: sessionID)
    }

    // MARK: - ingest

    /// Перевод одного транспортного события в мутации транскрипта плюс побочные
    /// эффекты уровня стора (автоимпорт сессии, фаза). Бизнес-правил сборки здесь
    /// нет — они в `Transcript`; текст записей чеканит `RunStrings`.
    private func ingest(_ event: AgentEvent) {
        switch event {
        case .sessionStarted(let start):
            transcript.beginSession(start)
            transcript.append(.info, body: RunStrings.sessionStarted(id: start.sessionID, model: start.model))
            if opensSessionInViewer {
                Task { [sessionOpener] in
                    await sessionOpener.openSession(
                        sessionID: start.sessionID, projectDirectory: start.projectDirectory)
                }
            }

        case .blockStarted(.thinking):
            flushPendingDelta()
            transcript.append(.thinking, body: "")

        case .blockStarted(.text):
            flushPendingDelta()
            transcript.append(.text, body: "")

        case .thinkingDelta(let delta), .textDelta(let delta):
            bufferDelta(delta)

        case .toolUse(let name, let inputSummary):
            flushPendingDelta()
            transcript.append(.tool(name: name), body: inputSummary)

        case .toolResult(let summary, let isError):
            transcript.attachToolResult(
                summary, isError: isError, emptyPlaceholder: RunStrings.emptyToolResult)

        case .finished(let runResult):
            flushPendingDelta()
            transcript.complete(runResult)
            phase = runResult.isError ? .failed(RunStrings.agentReturnedError) : .finished

        case .unknown(let type):
            if transcript.noteUnknownType(type) {
                transcript.append(.info, body: RunStrings.unknownEvent(type: type))
            }
        }
    }

    // MARK: - коалессинг дельт

    private func bufferDelta(_ delta: String) {
        pendingDelta += delta
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.deltaFlushInterval)
            self?.flushPendingDelta()
        }
    }

    private func flushPendingDelta() {
        flushScheduled = false
        guard !pendingDelta.isEmpty else { return }
        transcript.appendDelta(pendingDelta)
        pendingDelta = ""
    }

    // MARK: - завершение

    private func finishIfStillRunning() {
        flushPendingDelta()
        guard phase.isRunning else { return }
        // Стрим закрылся без result-события — считаем ран прерванным.
        phase = .failed(RunStrings.streamEndedWithoutResult)
    }

    private func markStopped() {
        flushPendingDelta()
        guard phase.isRunning else { return }
        phase = .failed(RunStrings.stopped)
    }

    private func fail(_ error: Error) {
        flushPendingDelta()
        phase = .failed(error.localizedDescription)
    }
}
