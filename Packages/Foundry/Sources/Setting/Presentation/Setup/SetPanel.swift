import Core
import SwiftUI

/// Плашка `.setpanel` — та же нейтральная поверхность и угол 22, что у карточек;
/// внутри строки без разделительных линеек. Один компонент на Settings,
/// Permissions и резюме Ready.
struct SetPanel<Content: View>: View {
    var maxWidth: CGFloat = 340
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: maxWidth)
            // полупрозрачная плашка (свет сверху) поверх непрозрачной bg-базы, чтобы
            // рой не просвечивал; тень уходит в FloatShadowLayer — своё дно нужно тут
            .background(
                LinearGradient(
                    colors: [SetupStyle.cardFillTop, SetupStyle.cardFillBottom],
                    startPoint: .top, endPoint: .bottom)
            )
            .background(SetupStyle.bg)
            .clipShape(SetupStyle.squircle(SetupStyle.cardRadius))
            .edgeRelief(SetupStyle.cardRadius)
            // тень рисует не панель: регистрируем рамку, слой кладёт тень под весь контент
            .castsFloatShadow(SetupStyle.cardRadius)
    }
}
