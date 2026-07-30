import Foundation

/// Чтение свойств конфигурации по ключу (точное имя из Spring — `PropertyResolver`, интерфейс,
/// который расширяет `Environment`). Отделён от `Environment` затем же, зачем в Spring: кому нужно
/// лишь ПРОЧИТАТЬ настройку, не должен зависеть от того, из каких источников и в каком приоритете
/// она собрана.
///
/// В Spring типовая конвертация — `getProperty(key, Class<T>, T default)` через `ConversionService`;
/// в Swift рефлексии типов нет, поэтому конвертация выражена перегрузками по типу дефолта — тип
/// выводится из аргумента, а не передаётся метатипом.
public protocol PropertyResolver {
    /// Есть ли ключ хоть в одном источнике.
    func containsProperty(name: String) -> Bool

    /// Сырое значение или `nil`, если ключа нет ни в одном источнике.
    func getProperty(name: String) -> String?

    func getProperty(name: String, default fallback: String) -> String

    func getProperty(name: String, default fallback: Int) -> Int

    func getProperty(name: String, default fallback: Bool) -> Bool

    /// Путь-свойство → файловый URL (с раскрытием `~`); нет ключа — дефолт.
    func getProperty(name: String, default fallback: URL) -> URL

    /// Значение, без которого приложению не жить: нет ключа — ошибка, а не тихий дефолт
    /// (Spring: `getRequiredProperty`). Обязательная настройка обязана падать на старте.
    func getRequiredProperty(name: String) throws -> String
}
