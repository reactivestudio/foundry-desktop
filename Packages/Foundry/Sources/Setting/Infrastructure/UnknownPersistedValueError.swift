/**
 Снимок с диска содержит значение, которого домен не знает (неизвестное имя темы или
 вида уведомления) — ошибка слоя Infrastructure, не домена: доменные правила не нарушены,
 просто хранилище отдало мусор. Ловится репозиторием и трактуется как «валидного снимка
 нет». Несёт поле и значение — чтобы понять, что именно в хранилище испортилось.
 */
struct UnknownPersistedValueError: Error, CustomStringConvertible {
    let field: String
    let value: String

    var description: String {
        "Unknown persisted value \"\(value)\" for field \(field)."
    }
}
