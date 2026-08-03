import SwiftUI

/**
 Чей ход. Единственный вопрос, на который отвечает доска, — и потому
 единственная шкала на карточке: один чип, один вопрос.

 Слов ровно четыре, и они одного строя: ждёт · идёт · встало · упало.
 Тем же словарём назван срез в сайдбаре — два словаря на одну тройку
 состояний заставляли глаз сопоставлять вместо того, чтобы узнавать.
 */
enum ChangeMove: Sendable {
    /// Ваш ход: агент спросил или показал артефакт и ждёт приёмки.
    case waiting
    /// Ход агента: работа идёт прямо сейчас.
    case running
    /// Ничей ход: change стоит.
    case stalled
    /// Ничей ход: change упал.
    case failed
    /// Принят. В корзине «Готово», где срок сменяется временем приёмки.
    case accepted

    /// Ничей ход — это и «встало», и «упало»: срез считает их одной строкой,
    /// потому что от читателя в обоих случаях требуется одно и то же.
    var isNobodysMove: Bool { self == .stalled || self == .failed }

    var chipFill: Color {
        switch self {
        case .waiting: BoardPalette.chipWait
        case .running: BoardPalette.chipLive
        case .stalled, .failed: BoardPalette.chipStop
        case .accepted: BoardPalette.chipMuted
        }
    }

    var chipInk: Color {
        switch self {
        case .waiting: BoardPalette.chipWaitInk
        case .running: BoardPalette.chipLiveInk
        case .stalled, .failed: BoardPalette.chipStopInk
        case .accepted: BoardPalette.chipMutedInk
        }
    }

    /// Знак в чипе различает, ЧЕГО от вас ждут: на первой стадии агент
    /// спрашивает, дальше — показывает артефакт. У «идёт» вместо знака точка,
    /// у «принят» знака нет вовсе: он съедал три знака подписи в дорожке 124.
    func chipGlyph(isAsking: Bool) -> String? {
        switch self {
        case .waiting: isAsking ? "ellipsis.bubble" : "text.magnifyingglass"
        case .running: nil
        case .stalled, .failed: "exclamationmark.triangle"
        case .accepted: nil
        }
    }
}
