import Testing

@testable import Setting

/// `ToolService` и `ToolStore` — путь от системы к экрану: служба реконституирует
/// известные инструменты ответами порта, стор отдаёт вью иммутабельные VO и умеет
/// показать инструкцию вместо установки.
@Suite("ToolStore")
@MainActor
struct ToolStoreTests {

    private func makeStore(
        gateway: StubToolGateway = StubToolGateway(),
        instructions: SpyInstallInstructions = SpyInstallInstructions()
    ) -> ToolStore {
        ToolStore(service: ToolService(gateway: gateway, instructions: instructions))
    }

    @Test("До первого опроса системы инструменты считаются неустановленными")
    func emptySnapshotIsNotInstalled() {
        let store = makeStore()

        #expect(store.installation(of: .claudeCode).isInstalled == false)
    }

    @Test("Служба спрашивает про каждый инструмент связки")
    func serviceInspectsEveryTool() async {
        let gateway = StubToolGateway()
        let service = ToolService(gateway: gateway, instructions: SpyInstallInstructions())

        let tools = await service.tools()

        // Спрашиваются все пять; порядок ответов не важен — он параллельный, а
        // доменный порядок держит `Tool.known()`.
        let known = Tool.known().map(\.id)
        #expect(Set(gateway.inspected) == Set(known))
        #expect(tools.map(\.id) == known)
    }

    @Test("refresh приносит путь и версию установленного инструмента")
    func refreshBringsInstallation() async {
        let gateway = StubToolGateway()
        gateway.installations[.claudeCode] = Installation.of(
            path: "/usr/local/bin/claude", version: "2.1.4")
        let store = makeStore(gateway: gateway)

        await store.refresh()

        #expect(store.installation(of: .claudeCode).version == "2.1.4")
        #expect(store.installation(of: .claudeCode).path == "/usr/local/bin/claude")
        #expect(store.installation(of: .codexCli).isInstalled == false)
    }

    @Test("Инструмент снесли между опросами — стор показывает это")
    func removedToolDisappears() async {
        let gateway = StubToolGateway()
        gateway.installations[.geminiCli] = Installation.of(path: "/opt/homebrew/bin/gemini")
        let store = makeStore(gateway: gateway)
        await store.refresh()
        #expect(store.installation(of: .geminiCli).isInstalled)

        gateway.installations[.geminiCli] = nil
        await store.refresh()

        #expect(store.installation(of: .geminiCli).isInstalled == false)
    }

    @Test("Установка не выполняется приложением — пользователя ведут к инструкции")
    func installationIsAnInstructionNotAnAction() {
        let instructions = SpyInstallInstructions()
        let store = makeStore(instructions: instructions)

        store.openInstructions(for: .codexCli)

        #expect(instructions.opened == [.codexCli])
        #expect(store.installation(of: .codexCli).isInstalled == false)  // ничего не «установилось»
    }
}
