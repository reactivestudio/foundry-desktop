@testable import Setting
import Testing

/// Агрегат `Tool` — реконституируемый: своего сохранённого состояния у него нет, он
/// принимает ответ системы. Проверяем состав связки и единственную команду.
@Suite("Агрегат Tool")
struct ToolTests {

    @Test("Состав связки: три агентских CLI и две свои части")
    func knownToolsCoverTheBundle() {
        let tools = Tool.known()

        #expect(tools.map(\.id) == [.claudeCode, .codexCli, .geminiCli, .claudePlugin, .foundryCli])
        #expect(tools.filter { $0.kind == .agentCli }.count == 3)
        #expect(tools.first { $0.id == .claudePlugin }?.kind == .agentPlugin)
        #expect(tools.first { $0.id == .foundryCli }?.kind == .foundryCli)
    }

    @Test("Фабрика отдаёт свежие инстансы, а не общий на всех")
    func knownToolsAreFreshInstances() {
        let first = Tool.known()[0]
        first.change(installation: Installation.of(path: "/usr/local/bin/claude"))

        #expect(Tool.known()[0].isInstalled == false)
    }

    @Test("Новый инструмент не установлен, ответ системы меняет состояние")
    func installationComesFromSystem() {
        let tool = Tool.of(id: .claudeCode, kind: .agentCli)
        #expect(tool.isInstalled == false)
        #expect(tool.installation.version == nil)

        tool.change(installation: Installation.of(path: "/usr/local/bin/claude", version: "2.1.4"))
        #expect(tool.isInstalled)
        #expect(tool.installation.version == "2.1.4")

        // Инструмент снесли мимо приложения — состояние честно откатывается.
        tool.change(installation: .missing)
        #expect(tool.isInstalled == false)
    }

    @Test("Найден без версии — всё равно установлен")
    func versionIsOptional() {
        let installation = Installation.of(path: "/opt/homebrew/bin/codex")

        #expect(installation.isInstalled)
        #expect(installation.version == nil)
    }
}
