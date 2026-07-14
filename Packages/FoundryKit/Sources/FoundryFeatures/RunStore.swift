import Foundation
import FoundryCLI
import FoundryCore
import Observation

/// Элемент live-ленты рана. Дельты одного контент-блока копятся в одном
/// элементе; новый блок (blockStarted) открывает новый элемент.
public struct FeedItem: Identifiable, Sendable {
    public enum Kind: Sendable, Equatable {
        case info
        case thinking
        case text
        case tool(name: String)
    }

    public let id: Int
    public let kind: Kind
    public var body: String
    /// Для тулов: результат вызова (появляется позже).
    public var detail: String?
    public var isError = false
}

/// Стор одного рана: MV-паттерн, @Observable без ViewModel'ей (practices 03).
/// Токен-дельты коалессируются с кадровой каденцией (~16 мс) — одна
/// SwiftUI-инвалидация на кадр, не на токен (practices 06 §2.5).
@MainActor @Observable
public final class RunStore {

    public enum Phase: Equatable {
        case idle
        case running
        case finished
        case failed(String)

        public var isRunning: Bool { self == .running }
    }

    public private(set) var phase: Phase = .idle
    public private(set) var session: SessionInit?
    public private(set) var feed: [FeedItem] = []
    public private(set) var result: RunResult?

    public var prompt = ""
    public var permissionMode: PermissionMode = .acceptEdits
    /// Импортировать сессию в Claude Code Desktop при старте рана
    /// (claude://resume — docs/ccd-visibility.md).
    public var openInClaudeDesktop: Bool {
        didSet { UserDefaults.standard.set(openInClaudeDesktop, forKey: Self.openInCCDKey) }
    }

    private static let openInCCDKey = "openInClaudeDesktop"

    private let runner = ClaudeRunner()
    private var runTask: Task<Void, Never>?
    private var nextItemID = 0

    private var pendingDelta = ""
    private var flushScheduled = false
    private var reportedUnknownTypes: Set<String> = []

    public init() {
        // Дефолт — включено: смысл фичи в наблюдении рана из CCD.
        openInClaudeDesktop = UserDefaults.standard.object(forKey: Self.openInCCDKey) as? Bool ?? true
    }

    public func start(projectDirectory: String) {
        guard !phase.isRunning else { return }
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !projectDirectory.isEmpty else { return }

        phase = .running
        session = nil
        result = nil
        feed = []
        pendingDelta = ""
        reportedUnknownTypes = []

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

    public func stop() {
        // Отмена consumer-задачи рвёт стрим → onTermination → SIGINT ребёнку.
        runTask?.cancel()
        runTask = nil
        markStopped()
    }

    // MARK: - ingest

    private func ingest(_ event: ClaudeEvent) {
        switch event {
        case .sessionStarted(let info):
            session = info
            append(.info, body: "Сессия \(info.sessionID) · \(info.model)")
            if openInClaudeDesktop {
                Task {
                    await ClaudeDesktopLink.openSessionWhenTranscriptExists(
                        id: info.sessionID,
                        cwd: info.cwd
                    )
                }
            }

        case .blockStarted(.thinking):
            flushPendingDelta()
            append(.thinking, body: "")

        case .blockStarted(.text):
            flushPendingDelta()
            append(.text, body: "")

        case .thinkingDelta(let delta), .textDelta(let delta):
            bufferDelta(delta)

        case .toolUse(let name, let inputSummary):
            flushPendingDelta()
            append(.tool(name: name), body: inputSummary)

        case .toolResult(let summary, let isError):
            attachToolResult(summary, isError: isError)

        case .finished(let runResult):
            flushPendingDelta()
            result = runResult
            phase = runResult.isError ? .failed("claude вернул ошибку") : .finished

        case .unknown(let type):
            guard reportedUnknownTypes.insert(type).inserted else { return }
            append(.info, body: "Неизвестное событие: \(type)")
        }
    }

    private func append(_ kind: FeedItem.Kind, body: String) {
        nextItemID += 1
        feed.append(FeedItem(id: nextItemID, kind: kind, body: body))
    }

    /// Результат тула привязывается к последнему tool-элементу без результата.
    private func attachToolResult(_ summary: String, isError: Bool) {
        guard let index = feed.lastIndex(where: {
            if case .tool = $0.kind { return $0.detail == nil }
            return false
        }) else { return }
        feed[index].detail = summary.isEmpty ? "✓" : summary
        feed[index].isError = isError
    }

    // MARK: - коалессинг дельт

    private func bufferDelta(_ delta: String) {
        pendingDelta += delta
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(16))
            self?.flushPendingDelta()
        }
    }

    private func flushPendingDelta() {
        flushScheduled = false
        guard !pendingDelta.isEmpty else { return }
        if feed.isEmpty {
            // Дельта без открытого блока — стартуем текстовый блок сами.
            append(.text, body: pendingDelta)
        } else {
            feed[feed.count - 1].body += pendingDelta
        }
        pendingDelta = ""
    }

    // MARK: - завершение

    private func finishIfStillRunning() {
        flushPendingDelta()
        guard phase.isRunning else { return }
        // Стрим закрылся без result-события — считаем ран прерванным.
        phase = .failed("Ран завершился без result-события")
    }

    private func markStopped() {
        flushPendingDelta()
        guard phase.isRunning else { return }
        phase = .failed("Остановлено")
    }

    private func fail(_ error: Error) {
        flushPendingDelta()
        phase = .failed(error.localizedDescription)
    }
}
