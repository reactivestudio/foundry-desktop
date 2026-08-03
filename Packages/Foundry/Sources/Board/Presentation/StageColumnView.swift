import Core
import SwiftUI

/**
 Колонка доски: шапка со стадией и числом, стопка карточек, свёртка корзины.

 Счётчик стоит ПОД подписью, а не рядом с ней: рядом девять счётчиков вставали
 лесенкой по длине подписей, и сравнить их взглядом было нельзя — хотя
 сравнивать их и есть работа шапки. Под словом выполняются оба закона: числа
 стоят на одной левой вертикали и на одной горизонтали.

 Внутри колонки один флаг: шапка и кромки карточек стоят на кромке колонки,
 заголовок и чип отступают ровно на поле карточки. Это вложенность, а не
 третья вертикаль.
 */
struct StageColumnView: View {
    let column: StageColumn
    /// Первая стадия пайплайна: там ожидание значит «агент спросил».
    let isFirstStage: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: BoardMetrics.cardGap) {
            header
            ForEach(column.cards) { card in
                ChangeCardView(card: card, isFirstStage: isFirstStage, isAccepted: column.isBin)
            }
            if column.foldedCount > 0 {
                Text("Ещё \(column.foldedCount) принятых")
                    .typography(Token.Typography.caption)
                    .foregroundStyle(Token.Text.tertiary)
                    .padding(.top, BoardMetrics.foldNoteGap - BoardMetrics.cardGap)
            }
        }
        .frame(width: BoardMetrics.laneWidth, alignment: .topLeading)
    }

    /// Подпись стадии набрана строчными и без разрядки: ряд шапок капсом
    /// смешивал алфавиты в одной строке — QUESTIONS … ГОТОВО.
    private var header: some View {
        VStack(alignment: .leading, spacing: BoardMetrics.columnHeadGap) {
            Text(column.name)
                .typography(BoardType.columnName)
                .foregroundStyle(Token.Text.tertiary)
            Text(countText)
                .typography(Token.Typography.bodyEm)
                .monospacedDigit()
                .foregroundStyle(Token.Text.secondary)
        }
        .lineLimit(1)
        .padding(.bottom, BoardMetrics.columnHeadPaddingBottom)
    }

    /// Под срезом шапка обязана называть обе величины: одно число вместо двух
    /// заставило бы читателя решить, что колонка опустела.
    private var countText: String {
        guard let outOf = column.outOf else { return String(column.headerCount) }
        return "\(column.headerCount) из \(outOf)"
    }
}
