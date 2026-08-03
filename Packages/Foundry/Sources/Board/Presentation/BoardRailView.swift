import Core
import SwiftUI

/**
 Рейл разделов — левая плита окна.

 Знак и слово под ним. Пиктограмма без слова работает, когда значений два-три
 и они общеизвестны; здесь их восемь, и половина — сущности этого продукта
 («Навыки», «Ревью»), которые угадать нельзя.

 Наведение и выбор — те же значения, что у пункта сайдбара: правило одно
 на оба пульта. Нажатие уводит знак НИЖЕ плиты: в покое заливки у него нет,
 и гаснуть плоскому знаку нечем.
 */
struct BoardRailView: View {
    @Binding var selection: BoardSection

    var body: some View {
        VStack(spacing: BoardMetrics.railItemGap) {
            ForEach(BoardSection.workSections) { section in
                item(section)
            }
            Spacer(minLength: Token.Space.step4)
            item(.settings)
        }
        .frame(width: BoardMetrics.railWidth)
        .padding(.vertical, BoardMetrics.railPaddingVertical)
        .background(BoardPalette.plate)
        .clipShape(RoundedRectangle(cornerRadius: Token.Radius.extraLarge, style: .continuous))
    }

    private func item(_ section: BoardSection) -> some View {
        RailItemView(section: section, isSelected: selection == section) {
            selection = section
        }
    }
}

/// Пункт рейла отдельным видом: у него своё состояние наведения, а вид
/// с собственным состоянием внутри `ForEach` обязан быть своим типом —
/// иначе одно `@State` разделили бы все восемь.
private struct RailItemView: View {
    let section: BoardSection
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        VStack(spacing: BoardMetrics.railIconGap) {
            Image(systemName: section.symbol)
                .font(.system(size: 14))
                .frame(width: BoardMetrics.railIconSide, height: BoardMetrics.railIconSide)
                .foregroundStyle(isSelected ? Token.Text.primary : Token.Text.secondary)
            Text(section.title)
                .typography(BoardType.railLabel)
                .foregroundStyle(labelColor)
                .lineLimit(1)
                // Подложка пункта уже 60, а самое длинное слово ряда — ровно
                // 60 с долями. Слово не режем и не жмём: подложка ему не
                // клетка, а подсветка, и лишние доли пункта она стерпит.
                .fixedSize()
        }
        .frame(width: BoardMetrics.railItemWidth)
        .padding(.top, BoardMetrics.railItemPaddingTop)
        .padding(.bottom, BoardMetrics.railItemPaddingBottom)
        .background(fill)
        .clipShape(RoundedRectangle(cornerRadius: BoardMetrics.railItemRadius, style: .continuous))
        .contentShape(Rectangle())
        .animation(AppMotion.hover(isHovered), value: isHovered)
        .onHover { isHovered = $0 }
        // Нажатие — состояние, а не событие: пока палец на кнопке, подложка
        // уходит ниже плиты. `onTapGesture` его не даёт вовсе, поэтому жест
        // с нулевым порогом: он же и щёлкает, когда отпустили внутри.
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

    private var labelColor: Color {
        if isSelected { return Token.Text.primary }
        return isHovered ? Token.Text.secondary : Token.Text.tertiary
    }

    private var fill: Color {
        if isPressed { return BoardPalette.flatPressed }
        if isSelected { return BoardPalette.flatSelected }
        return isHovered ? BoardPalette.flatHover : .clear
    }
}
