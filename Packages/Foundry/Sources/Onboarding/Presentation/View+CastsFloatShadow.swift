import SwiftUI

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
