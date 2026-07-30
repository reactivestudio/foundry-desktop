import Core
import SwiftUI

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
