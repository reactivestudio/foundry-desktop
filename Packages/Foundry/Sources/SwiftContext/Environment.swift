import Foundation

/// Окружение конфигурации (аналог `Environment` Spring): держит источники свойств по приоритету
/// и отдаёт значение по ключу с типовой конвертацией и дефолтом. Первый источник в списке —
/// высший приоритет (env перекрывает дефолты). Резолвится как бин и внедряется в `@Bean`-методы
/// и `@Component`-адаптеры (как `Environment`/`@Value` в Spring), а не читается из глобали.
public struct Environment: Sendable {
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

    /// Сырое значение по ключу — первое не-`nil` по приоритету источников.
    public func property(for key: String) -> String? {
        for source in sources {
            if let value = source.property(for: key) {
                return value
            }
        }

        return nil
    }

    public func string(for key: String, default fallback: String) -> String {
        property(for: key) ?? fallback
    }

    public func int(for key: String, default fallback: Int) -> Int {
        property(for: key).flatMap(Int.init) ?? fallback
    }

    public func bool(for key: String, default fallback: Bool) -> Bool {
        guard let raw = property(for: key)?.lowercased() else {
            return fallback
        }

        return ["1", "true", "yes", "on"].contains(raw)
    }

    /// Путь-свойство → файловый URL (с раскрытием `~`); нет ключа — дефолт.
    public func url(for key: String, default fallback: URL) -> URL {
        guard let raw = property(for: key) else {
            return fallback
        }

        return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
    }
}
