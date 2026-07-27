import Core

/**
 Идентичность агрегата `Preference` — конкретный id поверх базового `Identity<String>`
 (наследование, как договорились). Строковое значение осмысленно: разные наборы/версии
 настроек — разные id и разные файлы хранения (маппинг id→имя файла живёт в
 Infrastructure). `default` — id набора по умолчанию (единственный пока набор);
 произвольный id собирается фабрикой `of` (пустое значение — доменная ошибка, id
 всегда валиден). Имя `default` — ключевое слово Swift: в объявлении в бэктиках, на
 вызове без них (`PreferenceId.default`, как `NotificationCenter.default`).
 */
public final class PreferenceId: Identity<String>, @unchecked Sendable {
    /// Id набора настроек по умолчанию (единственный пока набор).
    public static let `default` = PreferenceId(value: "default")

    public static func of(value: String) throws -> PreferenceId {
        let cleanValue = value.trimmed()
        try require(correct: !cleanValue.isEmpty, orThrow: EmptyIdentityValueError())

        return PreferenceId(value: cleanValue)
    }
}
