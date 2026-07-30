import Foundation
@testable import Setting
import SparkIoC
import Testing

@Suite("SettingConfiguration")
struct SettingConfigurationTests {
    private func assembledContext() throws -> AnnotationConfigApplicationContext {
        // Контекст сам регистрирует окружение и заливает определения `@Configuration`-фабрики —
        // ручной сборки в тесте нет, ровно тот путь, что в bootstrap.
        try AnnotationConfigApplicationContext(definitions: SettingConfiguration().definitions())
    }

    @Test("@Bean-метод даёт репозиторий настроек по возвращаемому типу-порту")
    func resolvesToolRepository() throws {
        let context = try assembledContext()

        #expect(throws: Never.self) {
            _ = try context.getBean(ofType: ToolRepository.self)
        }
    }

    @Test("Кодеры и каталог из Environment резолвятся и кормят @Component-репозиторий")
    func codecsFeedComponentRepository() throws {
        let context = try assembledContext()

        #expect(throws: Never.self) {
            _ = PreferencePlistRepository(
                location: try context.getBean(ofType: StorageLocation.self),
                encoder: try context.getBean(ofType: PropertyListEncoder.self),
                decoder: try context.getBean(ofType: PropertyListDecoder.self)
            )
        }
    }
}
