import SwiftUI

/// Единый слой парящих теней экрана. Собирает рамки всех `castsFloatShadow`
/// блоков и рисует их тени ОДНИМ слоем ПОД всем содержимым (заголовки, тексты,
/// карточки, панели, кнопки — всё рисуется выше). Поэтому тень одной карточки не
/// может лечь ни на соседнюю, ни на заголовок/лид/кнопку: тени на слое n, тела на
/// n+10. Тень нельзя вешать `.background`-ом ряда: разрастаясь вверх, она перекроет
/// заголовок и лид (они рисуются в VStack раньше ряда).
struct FloatShadowLayer<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.backgroundPreferenceValue(ShadowCastersKey.self) { casters in
            GeometryReader { proxy in
                // Залитые НЕПРОЗРАЧНЫЕ силуэты на (size+2·spread) → compositingGroup
                // (уплощает перекрытия в единое чёрное, без тёмных швов) → блюр края →
                // прозрачность на ВЕСЬ уплощённый слой (равномерно, не по прямоугольнику).
                ZStack {
                    ForEach(casters.indices, id: \.self) { i in
                        let rect = proxy[casters[i].anchor]
                        RoundedRectangle(cornerRadius: casters[i].radius, style: .continuous)
                            .fill(OBShadow.color)
                            .frame(
                                width: rect.width + 2 * OBShadow.spread,
                                height: rect.height + 2 * OBShadow.spread
                            )
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
                .compositingGroup()
                .blur(radius: OBShadow.blur)
                .opacity(OBShadow.opacity)
            }
        }
    }
}
