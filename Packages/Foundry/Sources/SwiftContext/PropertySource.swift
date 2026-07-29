/// Источник свойств конфигурации (аналог `PropertySource` Spring): даёт строковое значение
/// по ключу или `nil`, если ключа у него нет. `Environment` опрашивает источники по приоритету
/// и отдаёт первое не-`nil`. Sendable — источник иммутабелен и ходит по DI-замыканиям.
public protocol PropertySource: Sendable {
    func property(for key: String) -> String?
}
