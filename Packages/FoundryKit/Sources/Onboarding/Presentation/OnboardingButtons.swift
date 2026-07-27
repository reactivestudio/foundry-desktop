import Core
import SwiftUI

/// Обведённая галочка-кружок — единая форма факта на весь мастер (#ic-check):
/// кружок + галочка, монолиния, currentColor наследует цвет (везде sem-success).
struct CheckTick: View {
    var size: CGFloat = 13
    var color: Color = OB.success
    var body: some View {
        Canvas { context, canvasSize in
            let side = canvasSize.width
            let lineWidth = side * 1.75 / 24
            var circle = Path()
            circle.addEllipse(
                in: CGRect(
                    x: side * (12 - 9.2) / 24, y: side * (12 - 9.2) / 24,
                    width: side * 18.4 / 24, height: side * 18.4 / 24))
            context.stroke(circle, with: .color(color), style: StrokeStyle(lineWidth: lineWidth))
            var check = Path()
            check.move(to: CGPoint(x: side * 9 / 24, y: side * 12.3 / 24))
            check.addLine(to: CGPoint(x: side * 11 / 24, y: side * 14.3 / 24))
            check.addLine(to: CGPoint(x: side * 15.2 / 24, y: side * 9.6 / 24))
            context.stroke(
                check, with: .color(color),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Кнопки

/// primary large — 44/32, squircle r18, плоский ультрамарин, hover/pressed вглубь.
/// Тайминг ховера асимметричен по общему закону AppMotion.hover (быстро на входе,
/// медленнее на выходе); тело не двигается.
struct OBPrimaryButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovering = false
    @State private var isPressed = false

    private var fill: Color {
        isPressed ? OB.ultraPressed : (isHovering ? OB.ultraHover : OB.ultramarine)
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
                    OB.squircle(18).fill(fill)
                        // микрорельеф кромок: свет сверху, подрезка снизу
                        .overlay(
                            OB.squircle(18).strokeBorder(
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
        .animation(OB.hoverAnim(isHovering), value: isHovering)
        .animation(OB.easeReal(0.12), value: isPressed)
        .onHover { isHovering = $0 }
        .onLongPressGesture(minimumDuration: 0, pressing: { isPressed = $0 }, perform: {})
    }
}
