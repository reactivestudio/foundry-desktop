import Core

/**
 Аватар профиля — VO-ссылка на сохранённое изображение, а НЕ сами байты. Картинку
 хранит и грузит Infrastructure (файл рядом с настройками), агрегат держит лишь
 стабильную ссылку. Инвариант — непустая ссылка — защищён фабрикой: `of` бросает
 `emptyAvatarReference`, и указывающий в никуда аватар просто не собрать.
 */
public struct Avatar: ValueObject {
    public let reference: String

    private init(reference: String) {
        self.reference = reference
    }

    public static func of(reference: String) throws -> Avatar {
        try require(correct: !reference.trimmed().isEmpty, orThrow: EmptyAvatarReferenceError())

        return Avatar(reference: reference)
    }
}
