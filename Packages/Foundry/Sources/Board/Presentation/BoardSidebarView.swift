import Core
import SwiftUI

/**
 Сайдбар — вторая плита окна. Он же пульт фильтров: содержимое меняется
 вместе с разделом рейла, а не раскрывается из него.

 Заголовка «Канбан» здесь нет: раздел назван в рейле, и слово стояло
 на экране трижды — в рейле, тут и в заголовке окна.

 Значков у строк нет: значок проекта дублировал имя и ничего не различал,
 а без него все строки панели встали на один флаг.
 */
struct BoardSidebarView: View {
    let sliceRows: [SidebarRow]
    let projectRows: [SidebarRow]
    @Binding var selectedSlice: String
    @Binding var selectedProject: String

    var body: some View {
        VStack(alignment: .leading, spacing: BoardMetrics.sidebarSectionGap) {
            section("Срез", rows: sliceRows, selection: $selectedSlice)
            section("Проект", rows: projectRows, selection: $selectedProject)
            Spacer(minLength: 0)
        }
        .padding(.vertical, BoardMetrics.sidebarPaddingVertical)
        .padding(.horizontal, BoardMetrics.sidebarPaddingHorizontal)
        // Ширина — ВСЕЙ плиты, а не её содержимого: поставленная до полей,
        // она давала плиту на два поля шире, и канвас уезжал вправо.
        .frame(width: BoardMetrics.sidebarWidth, alignment: .topLeading)
        .background(BoardPalette.plate)
        .clipShape(RoundedRectangle(cornerRadius: Token.Radius.extraLarge, style: .continuous))
    }

    /// Подпись секции — капсом с разрядкой: латиницы в ней нет, и смешать
    /// алфавиты в одной строке нечем.
    private func section(
        _ caption: String, rows: [SidebarRow],
        selection: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: BoardMetrics.sidebarRowGap) {
            Text(caption)
                .typography(Token.Typography.label)
                .foregroundStyle(Token.Text.tertiary)
                .padding(.horizontal, BoardMetrics.sidebarPaddingHorizontal)
                .padding(.bottom, BoardMetrics.sidebarCaptionGap)
            ForEach(rows) { row in
                SidebarRowView(row: row, isSelected: selection.wrappedValue == row.title) {
                    selection.wrappedValue = row.title
                }
            }
        }
    }
}

/// Строка пульта. Своё состояние наведения — свой тип.
private struct SidebarRowView: View {
    let row: SidebarRow
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        HStack(spacing: Token.Space.step2) {
            Text(row.title)
                .typography(Token.Typography.body)
                .foregroundStyle(isSelected ? Token.Text.primary : Token.Text.secondary)
                .lineLimit(1)
            Spacer(minLength: Token.Space.step2)
            // Счётчик цветом не красится: цвет на этом экране кодирует
            // состояние одного change'а, а не размер набора.
            if let countText = row.countText {
                Text(countText)
                    .typography(Token.Typography.body)
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Token.Text.primary : Token.Text.tertiary)
            }
        }
        .padding(.horizontal, Token.Space.step2)
        .frame(height: Token.Row.compact)
        .background(fill)
        // Форма принадлежит объекту, а не состоянию: скругление стоит здесь,
        // а не в ветке «выбран», — иначе наведение красит острый прямоугольник.
        .clipShape(RoundedRectangle(cornerRadius: Token.Radius.medium, style: .continuous))
        .contentShape(Rectangle())
        .animation(AppMotion.hover(isHovered), value: isHovered)
        .onHover { isHovered = $0 }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { value in
                    isPressed = false
                    let inside =
                        abs(value.translation.width) < 10
                        && abs(value.translation.height) < 10
                    if inside { onTap() }
                }
        )
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var fill: Color {
        if isPressed { return BoardPalette.flatPressed }
        if isSelected { return BoardPalette.flatSelected }
        return isHovered ? BoardPalette.flatHover : .clear
    }
}
