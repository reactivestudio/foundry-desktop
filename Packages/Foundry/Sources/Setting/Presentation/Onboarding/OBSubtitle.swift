import SwiftUI

/// Лид экрана — две строки по формуле приветствия, центр, вторичный.
struct OBSubtitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .lineSpacing(4.5)
            .multilineTextAlignment(.center)
            .foregroundStyle(OB.Text.secondary)
            .shadow(color: OB.bg.opacity(0.85), radius: 6)
            .padding(.bottom, 24)
    }
}
