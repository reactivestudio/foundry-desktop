import Core

/**
 Имя или фамилия длиннее допустимого — доменная ошибка BC `Setting`; бросает
 `Profile.of`. Несёт КОНТЕКСТ полями (`length`, `limit`): и подставляет их в текст
 (плейсхолдеры в `message`), и отдаёт структурно через `context` — для рендера/лога.
 Один тип — один файл.
 */
public struct NameTooLongError: DomainError {
    public let length: Int
    public let limit: Int

    public init(length: Int, limit: Int) {
        self.length = length
        self.limit = limit
    }

    public var message: String {
        "Name length \(length) exceeds the limit of \(limit)."
    }

    public var context: [String: String] {
        ["length": String(length), "limit": String(limit)]
    }
}
