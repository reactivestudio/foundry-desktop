import SwiftUI

/// Заголовок экрана — единственное место кегля 34 (type.hero). Тёмный ореол
/// цветом фона возвращает контраст над плотной серединой орба.
struct OBTitle: View {
    let text: String
    var isStandalone = false
    var body: some View {
        Text(text)
            .font(.system(size: 34, weight: .bold))
            .tracking(-0.02 * 34)
            .foregroundStyle(OB.Text.primary)
            .shadow(color: OB.bg.opacity(0.85), radius: 6)
            .padding(.bottom, isStandalone ? 24 : 8)
    }
}
