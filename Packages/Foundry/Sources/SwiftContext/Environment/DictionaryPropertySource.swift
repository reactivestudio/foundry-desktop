/// Источник свойств из словаря — дефолты по коду или тестовые переопределения (аналог
/// `MapPropertySource` Spring). Ключ ищется как есть.
public struct DictionaryPropertySource: PropertySource {
    private let values: [String: String]

    public init(values: [String: String]) {
        self.values = values
    }

    public func getProperty(name: String) -> String? {
        values[name]
    }
}
