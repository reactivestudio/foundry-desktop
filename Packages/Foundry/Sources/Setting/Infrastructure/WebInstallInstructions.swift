import AppKit
import SparkIoC

/**
 Продакшн-адаптер порта `InstallInstructionOpening`: открывает страницу с инструкцией по
 установке в браузере пользователя. Адрес страницы — деталь адаптера, как и deep link у
 `ClaudeDesktopLink`: сменится документация — сменится только этот файл.

 У чужих CLI это страницы вендоров, у своих частей (плагин, `foundry` CLI) — репозиторий
 проекта: отдельных страниц у них пока нет, они и сами ещё не вышли. Появятся свои
 репозитории — сюда приедут их адреса.
 */
@Component
public struct WebInstallInstructions: InstallInstructionOpening {
    public init() {}

    @MainActor
    public func openInstructions(for tool: ToolId) {
        guard let page = Self.page(for: tool) else {
            return
        }

        NSWorkspace.shared.open(page)
    }

    private static func page(for tool: ToolId) -> URL? {
        switch tool {
        case ToolId.claudeCode:
            URL(string: "https://docs.claude.com/en/docs/claude-code/setup")
        case ToolId.codexCli:
            URL(string: "https://github.com/openai/codex")
        case ToolId.geminiCli:
            URL(string: "https://github.com/google-gemini/gemini-cli")
        default:
            URL(string: "https://github.com/reactivestudio/foundry-desktop")
        }
    }
}
