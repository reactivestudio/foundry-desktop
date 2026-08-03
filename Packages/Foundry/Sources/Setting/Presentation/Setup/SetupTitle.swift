import SwiftUI

/// Заголовок экрана — единственное место кегля 34 (type.hero). Тёмный ореол
/// цветом фона возвращает контраст над плотной серединой орба.
struct SetupTitle: View {
    let text: String
    var isStandalone = false
    var body: some View {
        Text(text)
            .font(.system(size: 34, weight: .bold))
            .tracking(-0.02 * 34)
            .foregroundStyle(SetupStyle.Text.primary)
            .shadow(color: SetupStyle.bg.opacity(0.85), radius: 6)
            .padding(.bottom, isStandalone ? 24 : 8)
    }
}
