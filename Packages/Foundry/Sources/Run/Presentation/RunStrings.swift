import Core
import SwiftUI

/// Пользовательские строки рана — единственное место, где рождается UI-текст:
/// именованные, тестируемые, готовые к локализации. Стор их не чеканит, а зовёт.
enum RunStrings {
    /// Строка ленты о старте сессии: «Сессия <id> · <model>».
    static func sessionStarted(id: String, model: String) -> String {
        "Сессия \(id) · \(model)"
    }

    /// Строка ленты о неизвестном типе события.
    static func unknownEvent(type: String) -> String {
        "Неизвестное событие: \(type)"
    }

    /// Плейсхолдер результата тула, когда тот вернул пусто.
    static let emptyToolResult = "✓"

    // Причины перехода в `.failed` — тоже пользовательский текст. Символ
    // нейтрален; копия называет реальный инструмент рана.
    static let agentReturnedError = "claude вернул ошибку"
    static let streamEndedWithoutResult = "Ран завершился без result-события"
    static let stopped = "Остановлено"

    /// Команда продолжения сессии в терминале — она же попадает в буфер обмена по
    /// кнопке. Формат жёсткий: `claude --resume <id>`, менять нельзя.
    static func resumeCommand(sessionID: String) -> String {
        "claude --resume \(sessionID)"
    }
}
