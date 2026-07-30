import Core
import SwiftUI

/// Презентеры run-консоли (Humble Object): весь маппинг домен→оформление
/// (`FeedItemStyle`, `ResultCardStyle`, `OrbPhaseStyle`), форматирование метрик
/// (`RunFormat`) и чеканка пользовательских строк (`RunStrings`) собраны здесь
/// одним местом и проверяются юнит-тестами без SwiftUI. Значения перенесены
/// пиксель-в-пиксель из вью; вью маппинг и форматирование не считают — только
/// читают готовое и раскладывают.
///
/// Цвета консоли — своя тёмная шкала, не из `DesignTokens` намеренно (лента и орб
/// живут на общем с роем холсте). Значения зафиксированы здесь как именованные
/// константы, а не магические тройки в теле вью.
enum RunPalette {
    static let cardThinking = Color(red: 0.10, green: 0.07, blue: 0.16)
    static let cardTool = Color(red: 0.06, green: 0.09, blue: 0.16)
    static let cardDefault = Color(white: 0.09)
    /// Базовый «аварийный» тон карточки ошибки — общий для плашки провала рана и
    /// верхней точки диагонального градиента карточки результата-ошибки.
    static let cardFailure = Color(red: 0.16, green: 0.05, blue: 0.10)
    /// Нижняя точка градиента карточки результата-ошибки.
    static let cardFailureDeep = Color(red: 0.10, green: 0.04, blue: 0.12)
    /// Диагональный градиент карточки успешного результата (верх → низ).
    static let cardDone = Color(red: 0.05, green: 0.09, blue: 0.18)
    static let cardDoneDeep = Color(red: 0.09, green: 0.05, blue: 0.16)
    static let bodyThinking = Color(white: 0.65)
    static let bodyDefault = Color(white: 0.9)
    static let orbIdle = [Color(white: 0.35), Color(white: 0.15)]
    static let orbRunning: [Color] = [.cyan, .blue, .purple]
    static let orbFinished: [Color] = [.blue, .purple]
    static let orbFailed: [Color] = [.pink, .purple]
}
