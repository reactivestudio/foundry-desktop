import Core
import SwiftUI

/// primary large — 44/32, squircle r18, плоский ультрамарин, hover/pressed вглубь.
/// Тайминг ховера асимметричен по общему закону AppMotion.hover (быстро на входе,
/// медленнее на выходе); тело не двигается.
struct SetupPrimaryButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovering = false
    @State private var isPressed = false

    private var fill: Color {
        isPressed ? SetupStyle.ultraPressed : (isHovering ? SetupStyle.ultraHover : SetupStyle.ultramarine)
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(height: 44)
                .padding(.horizontal, 32)
                // Тени — НА ФОРМЕ внутри .background, не на всей кнопке. У CSS box-shadow
                // тень отбрасывает только коробка; SwiftUI же `.shadow` на всём лейбле
                // кладёт гало и под текст (тёмный ореол по буквам). Кладём тень на
                // squircle-подложку, текст рисуется поверх без тени.
                .background {
                    SetupStyle.squircle(18).fill(fill)
                        // микрорельеф кромок: свет сверху, подрезка снизу
                        .overlay(
                            SetupStyle.squircle(18).strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.22), .clear, .black.opacity(0.44)],
                                    startPoint: .top, endPoint: .bottom), lineWidth: 1)
                        )
                        // как в макете: --shadow-soft (4 плотных контактных слоя) + широкий
                        // мягкий 0 6/18. Радиус SwiftUI ≈ CSS-блюр/2. Кнопка «садится» на
                        // поверхность, а не парит.
                        .shadow(color: .black.opacity(0.48), radius: 1, y: 1)
                        .shadow(color: .black.opacity(0.40), radius: 2.5, y: 2)
                        .shadow(color: .black.opacity(0.32), radius: 6, y: 6)
                        .shadow(color: .black.opacity(0.24), radius: 12, y: 12)
                        .shadow(color: .black.opacity(0.45), radius: 9, y: 6)
                }
        }
        .buttonStyle(.plain)
        .clickCursor()
        .animation(SetupStyle.hoverAnim(isHovering), value: isHovering)
        .animation(SetupStyle.easeReal(0.12), value: isPressed)
        .onHover { isHovering = $0 }
        .onLongPressGesture(minimumDuration: 0, pressing: { isPressed = $0 }, perform: {})
    }
}
