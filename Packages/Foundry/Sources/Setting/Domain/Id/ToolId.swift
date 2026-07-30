import Core

/**
 Идентичность инструмента — конкретный id поверх базового `Identity<String>`. Значения
 осмысленны и стабильны: они уезжают в хранилище (выбранный агент в `Preference`), потому
 переименование значения — это миграция, а не правка строки.

 Пять инструментов, о которых приложение знает сегодня: три агентских CLI на выбор и две
 свои части — плагин агента и `foundry` CLI. Произвольный id собирается фабрикой `of`
 (пустое значение — доменная ошибка).
 */
public final class ToolId: Identity<String>, @unchecked Sendable {
    public static let claudeCode = ToolId(value: "claude")
    public static let codexCli = ToolId(value: "codex")
    public static let geminiCli = ToolId(value: "gemini")
    public static let claudePlugin = ToolId(value: "plugin")
    public static let foundryCli = ToolId(value: "cli")

    public static func of(value: String) throws -> ToolId {
        let cleanValue = value.trimmed()
        try require(correct: !cleanValue.isEmpty, orThrow: EmptyIdentityValueError())

        return ToolId(value: cleanValue)
    }
}
