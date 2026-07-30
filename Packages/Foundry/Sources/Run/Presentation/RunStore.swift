import Foundation
import Observation
import Setting
import SparkIoC

/// Стор одного рана: MV-паттерн, @Observable без ViewModel'ей (practices 03).
/// Тонкий: держит наблюдаемое состояние экрана (фаза + проекция транскрипта),
/// принимает интенты вью и делегирует их сценарию `RunService`. Сборку ленты
/// держит доменный агрегат `Transcript`; оркестрацию рана — `RunService`. Сам
/// стор — это сток `RunOutput`: сценарий толкает сюда события и терминалы, а стор
/// применяет их к транскрипту, коалессируя токен-дельты с кадровой каденцией
/// (~16 мс — одна SwiftUI-инвалидация на кадр, practices 06, пункт 2.5).
///
/// `@Store` — стереотип бина слоя Presentation (наш аналог `@Controller`): контейнер собирает стор
/// сам, внедряя `RunService` и `ToolService`. Singleton (одно окно на процесс). Как `@MainActor` —
/// ленив и строится через `MainActor.assumeIsolated` при resolve на главном акторе (в `FoundryApplication`).
@MainActor
@Observable
@Store
public final class RunStore: RunOutput {

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
    /// Финальный результат рана (nil до `finished`).
    var result: RunResult? { transcript.result }

    var prompt = ""
    var permissionMode: PermissionMode = .acceptEdits
    /// Импортировать сессию во внешний просмотрщик рана (сегодня — Claude Code
    /// Desktop, deep link claude://resume — docs/ccd-visibility.md; какой именно
    /// просмотрщик — деталь адаптера `AgentSessionOpening`). Изменение уходит в
    /// durable-настройки через сценарий `ToolService`, а не в
    /// `UserDefaults.standard` напрямую.
    var opensSessionInViewer: Bool {
        didSet { toolSetting.setOpensSessionInViewer(enabled: opensSessionInViewer) }
    }

    // Зависимости, не состояние: из наблюдения исключены (практики 03).
    @ObservationIgnored private let runService: RunService
    @ObservationIgnored private let toolSetting: ToolService
    private var runTask: Task<Void, Never>?

    /// Кадровая каденция коалессинга дельт (~60 Гц): одна SwiftUI-инвалидация на
    /// кадр, не на токен (practices 06, пункт 2.5).
    private static let deltaFlushInterval = Duration.milliseconds(16)

    private var pendingDelta = ""
    private var flushScheduled = false

    /// Все зависимости инъектируются bootstrap'ом (`Bootstrap`): сценарий
    /// рана и служба настроек инструментов. Конкретики-дефолтов НЕТ: UI-слой (этот
    /// модуль) не знает ни одной реализации портов и зависит только от абстракций
    /// (правило зависимостей). Тест подставляет сценарий с фейковым раннером/шпионом
    /// и службу с in-memory репозиторием настроек.
    public init(runService: RunService, toolSetting: ToolService) {
        self.runService = runService
        self.toolSetting = toolSetting
        // Начальное значение — снимок настроек (дефолт живёт в `Tool`).
        // Инициализирующее присваивание не будит didSet — обратной записи в
        // хранилище нет.
        opensSessionInViewer = toolSetting.current().opensSessionInViewer
    }

    // MARK: - интенты вью

    /// Готов ли ран стартовать: есть каталог проекта и непустой (по сути) промпт.
    /// Единый предикат пригодности — им гейтится кнопка старта во вью и защищается
    /// сам старт здесь (defense-in-depth), чтобы правило жило в одном месте.
    func canStart(projectDirectory: String) -> Bool {
        !projectDirectory.isEmpty
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func start(projectDirectory: String) {
        guard !phase.isRunning, canStart(projectDirectory: projectDirectory) else { return }
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        phase = .running
        transcript.reset()
        pendingDelta = ""

        runTask = runService.run(
            command: RunCommand(
                prompt: prompt,
                projectDirectory: projectDirectory,
                permissionMode: permissionMode,
                opensSessionInViewer: opensSessionInViewer
            ),
            into: self
        )
    }

    func stop() {
        // Отмена задачи потребления рвёт стрим → onTermination → SIGINT ребёнку.
        runTask?.cancel()
        runTask = nil
        runCancelled()
    }

    /// Открыть завершённую сессию результата в Claude Code Desktop (кнопка на
    /// карточке результата) — через сценарий, вью не знает про deep link.
    func openResultInDesktop() {
        guard let sessionID = result?.sessionID else { return }
        runService.openResult(sessionID: sessionID)
    }

    // MARK: - RunOutput: применение прогресса рана к транскрипту

    /// Перевод одного события потока в мутации транскрипта плюс фаза. Бизнес-правил
    /// сборки здесь нет — они в `Transcript`; текст записей чеканит `RunStrings`.
    public func receive(event: AgentEvent) {
        switch event {
        case .sessionStarted(let start):
            transcript.beginSession(start: start)
            transcript.append(
                kind: .info, body: RunStrings.sessionStarted(id: start.sessionID, model: start.model))

        case .blockStarted(.thinking):
            flushPendingDelta()
            transcript.append(kind: .thinking, body: "")

        case .blockStarted(.text):
            flushPendingDelta()
            transcript.append(kind: .text, body: "")

        case .thinkingDelta(let delta), .textDelta(let delta):
            bufferDelta(delta)

        case .toolUse(let name, let inputSummary):
            flushPendingDelta()
            transcript.append(kind: .tool(name: name), body: inputSummary)

        case .toolResult(let summary, let isError):
            transcript.attachToolResult(
                summary: summary, isError: isError, emptyPlaceholder: RunStrings.emptyToolResult)

        case .finished(let runResult):
            flushPendingDelta()
            transcript.complete(runResult: runResult)
            phase = runResult.isError ? .failed(RunStrings.agentReturnedError) : .finished

        case .unknown(let type):
            if transcript.noteUnknownType(type: type) {
                transcript.append(kind: .info, body: RunStrings.unknownEvent(type: type))
            }
        }
    }

    public func runEndedWithoutResult() {
        flushPendingDelta()
        guard phase.isRunning else { return }
        // Стрим закрылся без result-события — считаем ран прерванным.
        phase = .failed(RunStrings.streamEndedWithoutResult)
    }

    public func runCancelled() {
        flushPendingDelta()
        guard phase.isRunning else { return }
        phase = .failed(RunStrings.stopped)
    }

    public func runFailed(error: Error) {
        flushPendingDelta()
        phase = .failed(error.localizedDescription)
    }

    // MARK: - коалессинг дельт (кадровая каденция — забота UI-слоя)

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
        transcript.appendDelta(delta: pendingDelta)
        pendingDelta = ""
    }
}
