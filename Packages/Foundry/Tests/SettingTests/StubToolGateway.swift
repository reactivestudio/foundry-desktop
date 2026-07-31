@testable import Setting

/// Заглушка порта связки: отдаёт заранее заданную установленность вместо похода на диск
/// и запуска чужих процессов. `@MainActor` — как и служба, которая её зовёт.
@MainActor
final class StubToolGateway: ToolGateway {
    /// Что отвечать про инструмент. Чего нет в словаре — не установлен.
    var installations: [ToolId: Installation] = [:]
    private(set) var inspected: [ToolId] = []

    func inspect(tool: ToolId) async -> Installation {
        inspected.append(tool)

        return installations[tool] ?? .missing
    }
}

/// Шпион порта инструкций: запоминает, к чему повели пользователя, вместо открытия
/// браузера.
@MainActor
final class SpyInstallInstructions: InstallInstructionOpening {
    private(set) var opened: [ToolId] = []

    func openInstructions(for tool: ToolId) {
        opened.append(tool)
    }
}
