import Run
import Setting
import SparkIoC
import Testing

@testable import Bootstrap

/// Доказательство нового пути: РЕАЛЬНЫЙ граф приложения из ЕДИНОГО источника —
/// `BeanScan.definitions()` (скан подхватывает и `@Component`-адаптеры Run/Setting, и
/// `@Configuration`-фабрики `SettingConfiguration`) — собирается и резолвится через
/// `AnnotationConfigApplicationContext` (без Swinject). Сборку инкапсулирует сам контекст (окружение
/// + заливка определений + жадная преинстанциация в `refresh`), как в bootstrap. Так проверяем и
/// транзитивное замыкание типов, и supplier'ы с внедрением (`PreferencePlistRepository`,
/// `ToolService`), и цепочку через `@Bean`, подмешанную сканом.
@Suite("BeanScan → ApplicationContext (реальный граф приложения)")
struct BeanScanApplicationContextTests {
    private func assembledContext() throws -> AnnotationConfigApplicationContext {
        try AnnotationConfigApplicationContext(definitions: BeanScan.definitions())
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

    @Test(
        "@MainActor-бины RunService/RunStore резолвятся контейнером на главном акторе (ленивый + assumeIsolated)"
    )
    @MainActor
    func resolvesMainActorBeans() throws {
        let context = try assembledContext()

        _ = try context.getBean(ofType: RunService.self)
        let store = try context.getBean(ofType: RunStore.self)
        // Singleton: повторный резолв — тот же инстанс.
        #expect(try store === context.getBean(ofType: RunStore.self))
    }
}
