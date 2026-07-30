import Core

/**
 Профиль пользователя — VO агрегата `Preference`: имя, фамилия, аватар. Инварианты
 гарантирует фабрика `of` (а не вызывающий): имя/фамилия нормализованы (без ведущих/
 хвостовых пробелов) и не длиннее `maxNameLength`, иначе — доменная ошибка (невалидный
 профиль не рождается). Поведение вместо голых полей: полное имя и инициалы считает сам.
 */
public struct Profile: ValueObject {
    /// Предельная длина имени или фамилии (после нормализации).
    public static let maxNameLength = 100

    public let firstName: String
    public let lastName: String
    public let avatar: Avatar?

    private init(firstName: String, lastName: String, avatar: Avatar?) {
        self.firstName = firstName
        self.lastName = lastName
        self.avatar = avatar
    }

    /// Пустой профиль по умолчанию — известно-валиден (пустые имя и фамилия).
    public static let empty = Profile(firstName: "", lastName: "", avatar: nil)

    public static func of(
        firstName: String = "",
        lastName: String = "",
        avatar: Avatar? = nil
    ) throws -> Profile {
        let cleanFirstName = firstName.trimmed()
        let cleanLastName = lastName.trimmed()
        let longest = max(cleanFirstName.count, cleanLastName.count)
        try require(
            correct: longest <= maxNameLength,
            orThrow: NameTooLongError(length: longest, limit: maxNameLength))

        return Profile(firstName: cleanFirstName, lastName: cleanLastName, avatar: avatar)
    }

    /// Переименовать — новый валидный VO (имя/фамилия проверяются); аватар сохраняется.
    public func rename(firstName: String, lastName: String) throws -> Profile {
        try Profile.of(firstName: firstName, lastName: lastName, avatar: avatar)
    }

    /**
     Сменить аватар (или снять, передав `nil`) — новый VO. Имя/фамилия уже валидны,
     повторной проверки не требуют, поэтому без `throws`.
     */
    public func change(avatar: Avatar?) -> Profile {
        Profile(firstName: firstName, lastName: lastName, avatar: avatar)
    }

    /**
     Полное имя «Имя Фамилия»; пустые части не дают лишних пробелов. Без промежуточных
     коллекций — только результат-строка.
     */
    public var fullName: String {
        switch (firstName.isEmpty, lastName.isEmpty) {
        case (false, false): "\(firstName) \(lastName)"
        case (false, true): firstName
        case (true, false): lastName
        case (true, true): ""
        }
    }

    /**
     Инициалы для заглушки аватара (до двух букв, в верхнем регистре). Дописываем в
     один буфер, без промежуточных массива/среза/`[String]`.
     */
    public var initials: String {
        var result = ""
        if let firstInitial = firstName.first {
            result.append(contentsOf: firstInitial.uppercased())
        }
        if let lastInitial = lastName.first {
            result.append(contentsOf: lastInitial.uppercased())
        }

        return result
    }

    /// Есть ли заданный аватар.
    public var hasAvatar: Bool {
        avatar != nil
    }
}
