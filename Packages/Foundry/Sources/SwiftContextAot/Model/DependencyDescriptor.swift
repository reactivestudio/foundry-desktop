/// Одна зависимость конструктора `@Component`-бина: как её резолвить из контейнера (точное имя из
/// Spring — `DependencyDescriptor` описывает точку внедрения). `label` — метка параметра (`nil` для
/// `_`, тогда вызов позиционный); `type` — тип для `getBean(ofType:)`; `isCollection` — параметр вида
/// `[Port]`, тогда собираем все реализации через `getBeans(ofType:)`. Аналог того, что Spring выводит
/// рефлексией из сигнатуры init'а — у нас это читает сканер на компиляции.
public struct DependencyDescriptor: Equatable, Sendable {
    public let label: String?
    public let type: String
    public let isCollection: Bool

    public init(label: String?, type: String, isCollection: Bool = false) {
        self.label = label
        self.type = type
        self.isCollection = isCollection
    }
}
