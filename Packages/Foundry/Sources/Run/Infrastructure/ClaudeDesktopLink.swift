import AppKit
import SparkIoC

/// Продакшн-адаптер порта `AgentSessionOpening` над `ClaudeDesktopLink` —
/// реальное открытие сессии в CCD за портом. Публичен: его конструирует
/// bootstrap (`Bootstrap`) и внедряет за порт.
/// `@Component` — скан выведет закрываемый контракт из цепочки наследования
/// (`ClaudeDesktopSessionOpener: AgentSessionOpening`) сам.
@Component
public struct ClaudeDesktopSessionOpener: AgentSessionOpening {
    public init() {}

    public func openSession(sessionID: String, projectDirectory: String) async {
        await ClaudeDesktopLink.openSessionWhenTranscriptExists(
            sessionID: sessionID, projectDirectory: projectDirectory)
    }

    public func openSessionNow(sessionID: String) {
        ClaudeDesktopLink.openSession(sessionID: sessionID)
    }
}

/// Импорт CLI-сессии в Claude Code Desktop через недокументированный
/// deep link `claude://resume?session=<id>` (см. docs/ccd-visibility.md).
/// Единственная точка связи с CCD: сломается роут — сломается только она,
/// ран и live-лента приложения не зависят от неё.
enum ClaudeDesktopLink {
    /// Бюджет ожидания появления транскрипта на диске: 50 проб по 200 мс ≈ 10 с.
    private static let transcriptPollAttempts = 50
    private static let transcriptPollInterval = Duration.milliseconds(200)

    static func openSession(sessionID: String) {
        var components = URLComponents()
        components.scheme = "claude"
        components.host = "resume"
        components.queryItems = [URLQueryItem(name: "session", value: sessionID)]
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }

    /// Импорт сразу после system/init гоняется с созданием транскрипта:
    /// CCD ответит «transcript missing». Ждём появления файла на диске
    /// (обычно < 1 с), потом открываем.
    static func openSessionWhenTranscriptExists(sessionID: String, projectDirectory: String) async {
        let path = transcriptPath(sessionID: sessionID, projectDirectory: projectDirectory)
        for _ in 0..<transcriptPollAttempts where !FileManager.default.fileExists(atPath: path) {
            try? await Task.sleep(for: transcriptPollInterval)
        }
        openSession(sessionID: sessionID)
    }

    /// Путь транскрипта в общем хранилище Claude Code:
    /// `~/.claude/projects/<projectDirectory c '/' и '.' → '-'>/<sessionID>.jsonl`.
    static func transcriptPath(sessionID: String, projectDirectory: String) -> String {
        let escapedProjectDirectory = String(projectDirectory.map { $0 == "/" || $0 == "." ? "-" : $0 })
        return NSHomeDirectory() + "/.claude/projects/\(escapedProjectDirectory)/\(sessionID).jsonl"
    }
}
