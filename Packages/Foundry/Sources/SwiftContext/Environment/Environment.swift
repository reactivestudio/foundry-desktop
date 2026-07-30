import Foundation

/// Окружение конфигурации (аналог `Environment` Spring): держит источники свойств по приоритету
/// и отдаёт значение по ключу с типовой конвертацией и дефолтом. Первый источник в списке —
/// высший приоритет (env перекрывает дефолты). Резолвится как бин и внедряется в `@Bean`-методы
/// и `@Component`-адаптеры (как `Environment`/`@Value` в Spring), а не читается из глобали.
///
/// Само чтение по ключу — контракт [`PropertyResolver`], который `Environment` и реализует (в Spring
/// `Environment extends PropertyResolver` ровно так же): кому нужна одна настройка, тот зависит от
/// чтения, а не от устройства приоритетов.
public struct Environment: PropertyResolver, Sendable {
    private let sources: [any PropertySource]

    public init(sources: [any PropertySource]) {
        self.sources = sources
    }

    /// Стандартное окружение приложения: переопределения из env процесса поверх дефолтов кода.
    public static func standard(defaults: [String: String] = [:]) -> Environment {
        Environment(sources: [
            EnvironmentVariablesPropertySource(),
            DictionaryPropertySource(values: defaults),
        ])
    }

    public func containsProperty(name: String) -> Bool {
        getProperty(name: name) != nil
    }

    /// Сырое значение по ключу — первое не-`nil` по приоритету источников.
    public func getProperty(name: String) -> String? {
        for source in sources {
            if let value = source.getProperty(name: name) {
                return value
            }
        }

        return nil
    }

    public func getProperty(name: String, default fallback: String) -> String {
        getProperty(name: name) ?? fallback
    }

    public func getProperty(name: String, default fallback: Int) -> Int {
        getProperty(name: name).flatMap(Int.init) ?? fallback
    }

    public func getProperty(name: String, default fallback: Bool) -> Bool {
        guard let raw = getProperty(name: name)?.lowercased() else {
            return fallback
        }

        return ["1", "true", "yes", "on"].contains(raw)
    }

    /// Путь-свойство → файловый URL (с раскрытием `~`); нет ключа — дефолт.
    public func getProperty(name: String, default fallback: URL) -> URL {
        guard let raw = getProperty(name: name) else {
            return fallback
        }

        return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
    }

    public func getRequiredProperty(name: String) throws -> String {
        guard let value = getProperty(name: name) else {
            throw BeansException.requiredPropertyMissing(name: name)
        }

        return value
    }
}
