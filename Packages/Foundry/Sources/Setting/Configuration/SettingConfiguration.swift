import Foundation
import SwiftContext

/**
 `@Configuration` контекста Setting — методы-фабрики `@Bean` для бинов, которым не подходит
 скан `@Component` (ровно как `@Bean`-методы рядом с `@ComponentScan` в Spring). Макрос сам
 генерит `definitions() -> [BeanDefinitionHolder]`, а скан подмешивает их в общий `BeanScan` —
 ручных `register` нет вовсе. В возврате `@Bean` стоит ТОТ тип, по которому резолвим (контракт,
 а не реализация): замыкание супертипов для `@Bean` не считается, см. док `@Bean`.

 - xml-кодеры plist — типы Foundation, на чужой тип аннотацию не повесить, да и настройка
   (`.outputFormat = .xml`) ручная; это неустранимое ядро `@Configuration`;
 - `ToolRepository` ← `ToolUserDefaultsRepository`: в init'е `UserDefaults` — это КОНСТАНТА,
   а скан-автоваринг резолвил бы её как бин;
 - `StorageLocation` — каталог снимков из `Environment` (`@Value`-семантика): дефолт
   `~/Library/Application Support/Foundry`, переопределяется ключом `foundry.storage.dir`.

 `PreferenceRepository` и `ToolService` закрыты `@Component`-адаптерами (эти бины отсюда
 они и заберут). Порты запуска (`AgentRunner`, `AgentSessionOpening`) — тоже `@Component` Run.
 */
@Configuration
public struct SettingConfiguration {
    public init() {}

    @Bean
    public func plistEncoder() -> PropertyListEncoder {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml

        return encoder
    }

    @Bean
    public func plistDecoder() -> PropertyListDecoder {
        PropertyListDecoder()
    }

    @Bean
    public func toolRepository() -> ToolRepository {
        ToolUserDefaultsRepository()
    }

    @Bean
    public func storageLocation(environment: Environment) -> StorageLocation {
        StorageLocation(url: environment.getProperty(name: "foundry.storage.dir", default: Self.defaultDirectory))
    }

    /// `~/Library/Application Support/Foundry` — дефолт хранилища снимков (репозиторий создаёт
    /// каталог при первой записи). Не вычислился — временный каталог.
    private static var defaultDirectory: URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )) ?? FileManager.default.temporaryDirectory

        return base.appendingPathComponent("Foundry", isDirectory: true)
    }
}
