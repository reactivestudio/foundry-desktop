import SwiftUI

/// Тюнер тени карточек/панелей. Модель «spread + blur»: залитый чёрный силуэт,
/// вынесенный за кромку на `spread` px во все стороны, с размытием края на `blur` px.
enum OBShadow {
    static let spread: CGFloat = 80  // вынос за кромку во все стороны, px
    static let blur: CGFloat = 80  // размытие края, px (0 = чёткая граница)
    static let opacity: Double = 0.8  // прозрачность ВСЕГО слоя (после уплощения)
    static let color = Color.black
}

/// Один блок, отбрасывающий парящую тень: его рамка (anchor в координатах слоя)
/// и радиус угла. Собираются через preference и рисуются единым слоем.
struct ShadowCaster {
    let anchor: Anchor<CGRect>
    let radius: CGFloat
}

struct ShadowCastersKey: PreferenceKey {
    static let defaultValue: [ShadowCaster] = []
    static func reduce(value: inout [ShadowCaster], nextValue: () -> [ShadowCaster]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    /// Пометить блок (карточку, панель) как отбрасыватель парящей тени: регистрирует
    /// его рамку в ближайшем `FloatShadowLayer`, а не рисует тень на месте. Так тень
    /// уходит в слой ПОД всем контентом экрана — см. FloatShadowLayer.
    func castsFloatShadow(_ radius: CGFloat) -> some View {
        anchorPreference(key: ShadowCastersKey.self, value: .bounds) {
            [ShadowCaster(anchor: $0, radius: radius)]
        }
    }
}

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
