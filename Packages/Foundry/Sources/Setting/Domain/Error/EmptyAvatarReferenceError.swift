import Core

/**
 Ссылка на аватар пуста или состоит из одних пробелов — доменная ошибка BC `Setting`;
 бросает `Avatar.of`, чтобы указывающий в никуда аватар не собрался. Контекста нет.
 Один тип — один файл.
 */
public struct EmptyAvatarReferenceError: DomainError {
    public init() {}

    public var message: String {
        "Avatar reference is empty or blank."
    }
}
