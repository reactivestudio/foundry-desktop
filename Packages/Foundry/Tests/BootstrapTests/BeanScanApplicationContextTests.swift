import Run
import Setting
import SwiftContext
import Testing

@testable import Bootstrap

/// Доказательство нового пути: РЕАЛЬНЫЙ граф приложения — сгенерированные `BeanScan.definitions()`
/// (`@Component`-адаптеры Run/Setting) плюс `SettingConfiguration().definitions()` (`@Bean`-фабрики)
/// — собирается и резолвится через `AnnotationConfigApplicationContext` (без Swinject). Сборку
/// инкапсулирует сам контекст (окружение + заливка определений + жадная преинстанциация в `refresh`),
/// как в bootstrap; тест лишь отдаёт ему источники определений. Так проверяем и транзитивное
/// замыкание типов, и supplier'ы с внедрением (`PreferencePlistRepository`, `ToolService`), и
/// цепочку через `@Bean`.
@Suite("BeanScan → ApplicationContext (реальный граф приложения)")
struct BeanScanApplicationContextTests {
    private func assembledContext() throws -> AnnotationConfigApplicationContext {
        try AnnotationConfigApplicationContext(
            definitions: BeanScan.definitions() + SettingConfiguration().definitions())
    }

    @Test("Контекст поднимает весь реальный граф без ошибок")
    func assemblesRealGraph() throws {
        #expect(throws: Never.self) {
            _ = try assembledContext()
        }
    }

    @Test("Порты приложения резолвятся по типу через контекст")
    func resolvesApplicationPorts() throws {
        let context = try assembledContext()

        #expect(try context.getBean(ofType: AgentRunner.self) is ClaudeRunner)
        #expect(try context.getBean(ofType: AgentSessionOpening.self) is ClaudeDesktopSessionOpener)
        _ = try context.getBean(ofType: ToolService.self)
        _ = try context.getBean(ofType: PreferencePlistRepository.self)
    }
}
