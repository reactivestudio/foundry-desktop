import Foundation
import SparkIoC
import Subprocess

#if canImport(System)
    import System
#endif

/**
 Продакшн-адаптер порта `ToolGateway`: ищет инструмент на диске и спрашивает у него версию.
 Знание «какой файл стоит за инструментом» живёт здесь и только здесь — домен оперирует id.

 GUI-приложение НЕ наследует PATH шелла (та же грабля, что у `ClaudeRunner.locateClaude`),
 поэтому каталоги перебираются явно: домашние каталоги менеджеров пакетов, Homebrew,
 `/usr/local/bin` — и уже потом то, что всё-таки досталось в PATH.

 Версию спрашиваем самым распространённым флагом `--version` и берём из вывода первое
 похожее на версию слово: формат строки у каждого CLI свой, и разбирать его целиком —
 значит зависеть от чужого текста. Не ответил или ответил невнятно — инструмент всё равно
 установлен, просто без версии.
 */
@Component
public struct CommandLineToolGateway: ToolGateway {
    public init() {}

    public func inspect(tool: ToolId) async -> Installation {
        switch tool {
        case ToolId.claudeCode:
            await executable(named: "claude")
        case ToolId.codexCli:
            await executable(named: "codex")
        case ToolId.geminiCli:
            await executable(named: "gemini")
        case ToolId.foundryCli:
            await executable(named: "foundry")
        case ToolId.claudePlugin:
            plugin()
        default:
            .missing
        }
    }

    // MARK: - Исполняемые файлы

    private func executable(named name: String) async -> Installation {
        guard let path = Self.locate(executable: name) else {
            return .missing
        }

        return Installation.of(path: path, version: await Self.version(of: path))
    }

    /// Каталоги, где живут глобально поставленные CLI. Порядок — от пользовательских
    /// установок к системным: если инструмент стоит дважды, показываем тот, что раньше
    /// найдёт и сам шелл.
    private static func locate(executable name: String) -> String? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.path
        let directories =
            [
                "\(home)/.local/bin",
                "\(home)/.claude/local",
                "\(home)/.npm-global/bin",
                "\(home)/.bun/bin",
                "/opt/homebrew/bin",
                "/usr/local/bin",
                "/usr/bin",
            ] + inheritedPathDirectories()

        return directories
            .lazy
            .map { directory in "\(directory)/\(name)" }
            .first { path in fileManager.isExecutableFile(atPath: path) }
    }

    private static func inheritedPathDirectories() -> [String] {
        (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
    }

    private static func version(of path: String) async -> String? {
        let output = try? await run(
            .path(FilePath(path)),
            arguments: ["--version"],
            output: .string(limit: Limit.versionOutputBytes),
            error: .discarded
        ).standardOutput

        return output.flatMap { text in versionNumber(in: text) }
    }

    /// Первое слово вывода, похожее на номер версии: начинается с цифры и содержит точку.
    /// Так одинаково разбираются и «2.1.4 (Claude Code)», и «codex-cli 0.9.2».
    private static func versionNumber(in output: String) -> String? {
        output
            .split(whereSeparator: \.isWhitespace)
            .map { token in token.trimmingCharacters(in: CharacterSet(charactersIn: "v()")) }
            .first { token in token.first?.isNumber == true && token.contains(".") }
    }

    // MARK: - Плагин агента

    /// Плагин — не бинарь, а каталог в хозяйстве агента. Путь зафиксируем окончательно,
    /// когда плагин выйдет своим репозиторием; сегодня проверяем место, куда его кладёт
    /// сам Claude Code.
    private func plugin() -> Installation {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = "\(home)/.claude/plugins/foundry"
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)

        return exists && isDirectory.boolValue ? Installation.of(path: path) : .missing
    }

    private enum Limit {
        /// Вывод `--version` — одна строка; потолок только чтобы не читать бесконечность.
        static let versionOutputBytes = 4096
    }
}
