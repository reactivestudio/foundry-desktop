import SwiftUI

/// Лид экрана — две строки по формуле приветствия, центр, вторичный.
struct SetupSubtitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .lineSpacing(4.5)
            .multilineTextAlignment(.center)
            .foregroundStyle(SetupStyle.Text.secondary)
            .shadow(color: SetupStyle.bg.opacity(0.85), radius: 6)
            .padding(.bottom, 24)
    }
}
