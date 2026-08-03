import Core
import SwiftUI

/**
 Полоса вкладок пайплайнов над доской. Стоит на флаге канваса — той же левой
 вертикали, что первая колонка доски и кромки её карточек.

 Подложки у вкладки нет: вкладка это место в ряду, а не плашка. Выбранную
 называет вес и подпись с длиной пайплайна, а не заливка.
 */
struct PipelineBarView: View {
    let tabs: [PipelineTab]
    @Binding var selection: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: BoardMetrics.pipeBarGap) {
            ForEach(tabs) { tab in
                PipelineTabView(tab: tab, isSelected: tab.name == selection) {
                    selection = tab.name
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, BoardMetrics.pipeBarPaddingTop)
    }
}

/**
 Вкладка одной строкой: имя, счётчик-пилюля, длина пайплайна.

 «8 стадий» встаёт в ТУ ЖЕ строку: висячая вторая строка ломала ряд — соседние
 вкладки вставали по её верху, а не по общей базовой линии.

 Цвета вкладка не носит вовсе. Число на ней — размер набора, а цвет на этом
 экране кодирует состояние одного change'а; крашеная цветом худшего члена,
 вкладка заводила вторую шкалу теми же красками.
 */
private struct PipelineTabView: View {
    let tab: PipelineTab
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: BoardMetrics.pipeTabGap) {
            Text(tab.name)
                .typography(isSelected ? Token.Typography.bodyEm : BoardType.bodyMedium)
                .foregroundStyle(nameColor)
                .lineLimit(1)
            // Ноль не пишется: ноль — не величина, а её отсутствие.
            if let countText = tab.countText {
                Text(countText)
                    .typography(BoardType.pipeCount)
                    .monospacedDigit()
                    .foregroundStyle(Token.Text.secondary)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Color(white: 1, opacity: 0.08), in: Capsule())
            }
            if isSelected {
                Text(tab.stagesText)
                    .typography(Token.Typography.caption)
                    .foregroundStyle(Token.Text.tertiary)
                    .padding(.leading, BoardMetrics.pipeMetaGap - BoardMetrics.pipeTabGap)
            }
        }
        .contentShape(Rectangle())
        .animation(AppMotion.hover(isHovered), value: isHovered)
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onTap)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var nameColor: Color {
        if isSelected { return Token.Text.primary }
        return isHovered ? Token.Text.secondary : Token.Text.tertiary
    }
}
