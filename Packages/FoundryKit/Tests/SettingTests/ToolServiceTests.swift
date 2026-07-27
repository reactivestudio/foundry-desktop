import Testing

@testable import Setting

/// In-memory фейк порта: тесты не трогают глобальный `UserDefaults.standard` —
/// сущность живёт только в этом поле.
private final class InMemoryToolRepository: ToolRepository {
    private var tool = Tool()
    func load() -> Tool { tool }
    func save(_ tool: Tool) { self.tool = tool }
}

/// `ToolService` — граница согласованности настроек инструментов (слой Application).
/// Проверяем, что дефолт приходит из домена, а переход read-modify-write сохраняется
/// целиком. Единственный контекст без тестов до сих пор — закрываем его срез.
@Suite("ToolService")
struct ToolServiceTests {

    @Test("current() отдаёт доменный дефолт, когда ничего не сохранено")
    func currentReturnsDomainDefault() {
        let service = ToolService(repository: InMemoryToolRepository())
        #expect(service.current().opensSessionInViewer == true)
    }

    @Test("setOpensSessionInViewer сохраняет переход целиком")
    func setPersistsTransition() {
        let service = ToolService(repository: InMemoryToolRepository())
        service.setOpensSessionInViewer(false)
        #expect(service.current().opensSessionInViewer == false)
        service.setOpensSessionInViewer(true)
        #expect(service.current().opensSessionInViewer == true)
    }
}
