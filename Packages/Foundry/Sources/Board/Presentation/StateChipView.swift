import Core
import SwiftUI

/**
 Чип состояния — единственный носитель цвета на карточке.

 Цвет приходит СПЛОШНОЙ заливкой малой площади со словом внутри. Полупрозрачная
 цветная заливка на большой площади поверх почти чёрного даёт грязь — янтарь
 11 % на базе читается оливой, — а сплошной чип в 88 px её не даёт и вдобавок
 несёт слово. Полоса стадии рядом с чипом снята: средство на задачу одно.

 «Идёт» цвета не несёт вовсе: работа агента — норма, а не событие.
 */
struct StateChipView: View {
    let move: ChangeMove
    let text: String
    /// На первой стадии агент СПРАШИВАЕТ, дальше — показывает артефакт.
    let isAsking: Bool

    var body: some View {
        HStack(spacing: 5) {
            if move == .running {
                Circle()
                    .fill(move.chipInk)
                    .frame(width: 5, height: 5)
            } else if let glyph = move.chipGlyph(isAsking: isAsking) {
                Image(systemName: glyph)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(text)
                .typography(BoardType.chip)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(move.chipInk)
        .padding(.horizontal, Token.Space.step2)
        .padding(.vertical, 3)
        .background(move.chipFill, in: Capsule())
    }
}
