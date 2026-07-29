import Foundation

/// Каталог файлового хранилища настроек — типизированный бин (обёртка над `URL`, не голый
/// `URL`, иначе любой другой URL-бин с ним столкнулся бы). Значение приходит из `Environment`
/// (`@Bean` в `SettingConfiguration`): дефолт — `~/Library/Application Support/Foundry`,
/// переопределяется ключом `foundry.storage.dir` (env). Так «где лежат снимки» стало
/// конфигурацией, а не печёной в адаптер константой.
public struct StorageLocation: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }
}
