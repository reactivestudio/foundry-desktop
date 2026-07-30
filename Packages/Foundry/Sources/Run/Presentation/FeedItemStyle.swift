import Core
import SwiftUI

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
