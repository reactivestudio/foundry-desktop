import Core
import SwiftUI

/**
 Канвас — третья плита окна: вкладки пайплайнов, строка среза и доска.

 Поле доски держит ПЛИТА, а не доска: доска отдала своё горизонтальное поле
 наверх, и потому вкладки, строка среза, первая колонка и кромки её карточек
 стоят на одной левой вертикали — флаге канваса.

 «Готово» отделено швом шире, чем зазор между стадиями: change туда не
 переходит, а выбывает, и внутреннее обязано быть меньше внешнего.
 */
struct BoardCanvasView: View {
    let tabs: [PipelineTab]
    let columns: [StageColumn]
    /// Строка о применённом срезе. nil — срез снят.
    let sliceNote: SliceNote?
    @Binding var selectedPipeline: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PipelineBarView(tabs: tabs, selection: $selectedPipeline)
            if let note = sliceNote {
                noteView(note)
            }
            board
        }
        .padding(.horizontal, BoardMetrics.platePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(BoardPalette.plate)
        .clipShape(RoundedRectangle(cornerRadius: Token.Radius.extraLarge, style: .continuous))
    }

    /// Фильтр, который прячет данные, обязан вслух сказать, что прячет.
    /// Знаменатель назван словом «в работе»: сумма шапок колонок даёт другое
    /// число, потому что в неё входит корзина, а срез считает работу.
    /// Выхода строка не даёт вовсе — он один и лежит в пульте: два одинаково
    /// названных выхода заставляли бы выбирать вместо того, чтобы выйти.
    private func noteView(_ note: SliceNote) -> some View {
        (Text("Срез ") + Text(note.name).bold().foregroundColor(Token.Text.secondary)
            + Text(": показаны \(note.shown) из \(note.total) change в работе, остальные скрыты. ")
            + Text("Снять срез — строкой «Всё в работе» в пульте слева."))
            .typography(Token.Typography.body)
            .foregroundStyle(Token.Text.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Token.Space.step5)
    }

    private var board: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: BoardMetrics.laneGap) {
                ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                    if column.isBin {
                        // Пустая дорожка шва: он сделан ОТДЕЛЬНОЙ колонкой, а не
                        // отступом внутри «Готово», — отступ съедал бы ширину
                        // карточки, и та же карточка стала бы уже соседних.
                        Color.clear.frame(width: BoardMetrics.seamLane)
                    }
                    StageColumnView(column: column, isFirstStage: index == 0)
                }
            }
            .padding(
                .top,
                sliceNote == nil
                    ? BoardMetrics.boardPaddingTop : BoardMetrics.boardPaddingUnderNote
            )
            .padding(.bottom, BoardMetrics.boardPaddingBottom)
        }
    }
}

/// Строка о применённом срезе.
struct SliceNote: Sendable {
    let name: String
    let shown: Int
    let total: Int
}
