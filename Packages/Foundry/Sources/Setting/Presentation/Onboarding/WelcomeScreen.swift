import SwiftUI

struct WelcomeScreen: View {
    let onStart: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            FoundryWordmark(logoSize: 34)
                .padding(.bottom, 8)
            Text(
                "A delivery layer for changes: from task to\u{00a0}production\nAgents do routines, you review"
            )
            .font(.system(size: 12))
            .lineSpacing(4.5)
            .multilineTextAlignment(.center)
            .foregroundStyle(OB.Text.secondary)
            OBPrimaryButton(title: "Start setup", action: onStart)
                .padding(.top, 32)
        }
    }
}
