import SwiftUI

struct AgentCard: View {
    let card: InstallCardModel
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Верхний ряд: чип вендора слева, знак справа — оба к верхней кромке.
                // Снизу увеличенный зазор до имени (внешнее > внутреннего).
                HStack(alignment: .top, spacing: 8) {
                    vendorChip
                    Spacer(minLength: 8)
                    glyphView
                }
                .padding(.bottom, 4)
                Text(card.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OB.Text.primary)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                // Строка-требование одна на оба состояния: у установленного она
                // остаётся верной («что нужно, чтобы этим пользоваться»), а факт
                // установки говорит нижний ряд.
                factLine(card.requirement)
                Spacer(minLength: 0)
                if card.isInstalled { installedRow } else { installButton }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
            .background(cardFill)
            .clipShape(OB.squircle(OB.cardRadius))
            .overlay(selectionOverlay)
            .edgeRelief(OB.cardRadius)
            // тень рисует не карточка: регистрируем рамку, FloatShadowLayer кладёт
            // тень единым слоем под ВЕСЬ контент экрана (заголовок, лид, соседние
            // карточки — всё выше), чтобы тень ничьё тело не перекрывала
            .castsFloatShadow(OB.cardRadius)
        }
        .buttonStyle(.plain)
        .frame(width: 184, height: 184)
        .clickCursor()
        .onHover { isHovering = $0 }
        .animation(OB.easeReal(0.15), value: isSelected)
    }

    // Знак однотонный белый, БЕЗ подложки. Стоит в ПРАВОМ верхнем углу карточки
    // (паддинг 16 = отступ); чип вендора — в левом. Марка симметрична в своём
    // viewBox — гасим её ПРАВОЕ поле положительным сдвигом, чтобы знак был флеш с
    // правым краем карточки, а не утоплен влево.
    @ViewBuilder private var glyphView: some View {
        switch card.glyph {
        case .claude: ClaudeGlyph(size: 16).offset(x: 2)
        case .openai: OpenAIGlyph(size: 16).offset(x: 2.5)
        case .gemini: GeminiGlyph(size: 16).offset(x: 1)
        case .plugin: PluginGlyph(size: 14).offset(x: 3.5)
        case .cli: CLIGlyph(size: 14).offset(x: 3)
        }
    }

    // Чип вендора: ЗАГЛАВНЫЕ мельче имени, широкая разрядка, третичный, обведён
    // тонкой рамкой плотно по тексту (радиус 2.5). Правый паддинг чуть меньше —
    // разрядка добавляет пустоту после последней литеры, компенсируем.
    private var vendorChip: some View {
        Text(card.vendor)
            .font(.system(size: 7.5, weight: .semibold))
            .tracking(1.1)
            .textCase(.uppercase)
            .foregroundStyle(OB.Text.tertiary)
            // Верх/низ не симметричны: заглавные без нижних выносов сидят выше
            // em-бокса → нижний паддинг на 1px меньше. Разрядка отодвигает текст
            // вправо → leading меньше trailing, текст стоит на 1px левее.
            .padding(.top, 3)
            .padding(.bottom, 2)
            .padding(.leading, 5)
            .padding(.trailing, 4)
            .overlay(
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
    }

    private func factLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(OB.Text.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var installedRow: some View {
        HStack(spacing: 4) {
            CheckTick(size: 11)
            Text(card.installedLabel)
        }
        .font(.system(size: 10))
        .foregroundStyle(OB.success)
    }

    /// Кнопка ведёт к инструкции вендора, а не ставит инструмент, — поэтому у неё нет
    /// состояния ожидания: клик открывает страницу, окно уходит на задний план, и по
    /// возвращении экран уже спросит систему заново.
    private var installButton: some View {
        Text("Install")
            // кнопка целиком меньше при исходных пропорциях контейнера (h/кегль=2,
            // отступ/кегль=10/12): кегль 12→11, высота 24→22, отступ 10→9; радиус 7.
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .frame(height: 22)
            .padding(.horizontal, 9)
            .background(OB.squircle(7).fill(isHovering ? OB.ultraHover : OB.ultramarine))
            .animation(OB.hoverAnim(isHovering), value: isHovering)
    }

    // нейтральная плашка (0.07→0.03); у выбранной добавлена синяя подкраска 0.06.
    // База — непрозрачный bg: плашка полупрозрачная, а тень-подложку ряда рисует
    // CardShadowRow отдельным слоем, так что своё непрозрачное дно нужно здесь.
    private var cardFill: some View {
        ZStack {
            OB.bg
            LinearGradient(
                colors: [OB.cardFillTop, OB.cardFillBottom],
                startPoint: .top, endPoint: .bottom)
            if isSelected { OB.ultramarine.opacity(0.06) }
        }
    }

    @ViewBuilder private var selectionOverlay: some View {
        if isSelected {
            OB.squircle(OB.cardRadius).strokeBorder(OB.ultramarine.opacity(0.75), lineWidth: 2)
        }
    }
}
