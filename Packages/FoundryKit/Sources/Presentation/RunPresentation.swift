import Domain
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

/// Оформление одной карточки ленты по её виду. Один switch вместо шести,
/// разбросанных по вью (было: title/icon/titleColor/bodyFont/bodyColor/cardBackground).
struct FeedItemStyle: Equatable {
    let title: String
    let icon: String
    let titleColor: Color
    let bodyFont: Font
    let bodyColor: Color
    let cardBackground: Color

    init(kind: TranscriptItem.Kind) {
        switch kind {
        case .info:
            title = "Система"
            icon = "info.circle"
            titleColor = .secondary
            bodyFont = .system(.callout)
            bodyColor = RunPalette.bodyDefault
            cardBackground = RunPalette.cardDefault
        case .thinking:
            title = "Мышление"
            icon = "brain"
            titleColor = .purple
            bodyFont = .system(.callout).italic()
            bodyColor = RunPalette.bodyThinking
            cardBackground = RunPalette.cardThinking
        case .text:
            title = "Ответ"
            icon = "text.bubble"
            titleColor = .cyan
            bodyFont = .system(.callout)
            bodyColor = RunPalette.bodyDefault
            cardBackground = RunPalette.cardDefault
        case .tool(let name):
            title = name
            icon = "wrench.and.screwdriver"
            titleColor = .blue
            bodyFont = .system(.caption, design: .monospaced)
            bodyColor = RunPalette.bodyDefault
            cardBackground = RunPalette.cardTool
        }
    }
}

/// Оформление финальной карточки результата по исходу рана. Тот же Humble
/// Object, что `FeedItemStyle`: один переключатель `isError` вместо тех же
/// ветвлений, размазанных по телу `ResultCardView` (заголовок, знак, цвет,
/// градиент фона).
struct ResultCardStyle: Equatable {
    let title: String
    let icon: String
    let titleColor: Color
    /// Точки диагонального градиента фона (верх-лево → низ-право).
    let background: [Color]

    init(isError: Bool) {
        if isError {
            title = "Завершено с ошибкой"
            icon = "xmark.octagon.fill"
            titleColor = .pink
            background = [RunPalette.cardFailure, RunPalette.cardFailureDeep]
        } else {
            title = "Готово"
            icon = "checkmark.seal.fill"
            titleColor = .cyan
            background = [RunPalette.cardDone, RunPalette.cardDoneDeep]
        }
    }
}

/// Оформление статусного орба по фазе рана.
struct OrbPhaseStyle: Equatable {
    let colors: [Color]
    let accessibilityLabel: String

    init(phase: RunStore.Phase) {
        switch phase {
        case .idle:
            colors = RunPalette.orbIdle
            accessibilityLabel = "Готов"
        case .running:
            colors = RunPalette.orbRunning
            accessibilityLabel = "Claude работает"
        case .finished:
            colors = RunPalette.orbFinished
            accessibilityLabel = "Завершено"
        case .failed:
            colors = RunPalette.orbFailed
            accessibilityLabel = "Ошибка"
        }
    }
}

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

/// Форматирование метрик результата. Чистые функции — тестируются по граничным
/// значениям (переход на минуты ровно на 60 с).
enum RunFormat {
    /// Длительность рана: до минуты — десятые доли секунды, дальше — «м мин сс с».
    static func duration(milliseconds: Int) -> String {
        let seconds = Double(milliseconds) / 1000
        return seconds < 60
            ? String(format: "%.1f с", seconds)
            : String(format: "%d мин %02d с", Int(seconds) / 60, Int(seconds) % 60)
    }

    /// Стоимость рана в долларах — четыре знака после точки.
    static func cost(usd: Double) -> String {
        String(format: "$%.4f", usd)
    }

    /// Число ходов диалога: «N ходов». Форма родительного падежа не склоняется
    /// по числу намеренно (как в принятом макете), чтобы метрика не «прыгала».
    static func turns(_ count: Int) -> String {
        "\(count) ходов"
    }
}
