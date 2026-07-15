import AppKit

/// Импорт CLI-сессии в Claude Code Desktop через недокументированный
/// deep link `claude://resume?session=<id>` (см. docs/ccd-visibility.md).
/// Единственная точка связи с CCD: сломается роут — сломается только она,
/// ран и live-лента приложения не зависят от неё.
enum ClaudeDesktopLink {
    static func openSession(id: String) {
        var components = URLComponents()
        components.scheme = "claude"
        components.host = "resume"
        components.queryItems = [URLQueryItem(name: "session", value: id)]
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }

    /// Импорт сразу после system/init гоняется с созданием транскрипта:
    /// CCD ответит «transcript missing». Ждём появления файла на диске
    /// (обычно < 1 с), потом открываем.
    static func openSessionWhenTranscriptExists(id: String, cwd: String) async {
        let path = transcriptPath(sessionID: id, cwd: cwd)
        for _ in 0..<50 where !FileManager.default.fileExists(atPath: path) {
            try? await Task.sleep(for: .milliseconds(200))
        }
        openSession(id: id)
    }

    /// Путь транскрипта в общем хранилище Claude Code:
    /// `~/.claude/projects/<cwd c '/' и '.' → '-'>/<id>.jsonl`.
    static func transcriptPath(sessionID: String, cwd: String) -> String {
        let munged = String(cwd.map { $0 == "/" || $0 == "." ? "-" : $0 })
        return NSHomeDirectory() + "/.claude/projects/\(munged)/\(sessionID).jsonl"
    }
}
