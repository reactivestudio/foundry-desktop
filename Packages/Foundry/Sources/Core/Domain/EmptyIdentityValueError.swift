/**
 Значение идентификатора пусто или состоит из одних пробелов. Правило принадлежит роли
 `Identity`, поэтому ошибка общая, в Core, а не в конкретном контексте. Контекста нет —
 подставлять нечего (значение пустое). Один тип — один файл.
 */
public struct EmptyIdentityValueError: DomainError {
    public init() {}

    public var message: String {
        "Identity value is empty or blank."
    }
}
