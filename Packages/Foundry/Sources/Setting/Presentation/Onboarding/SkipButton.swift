import SwiftUI

/// «Skip for now» — при наведении цвет третичный → вторичный (макет
/// `.ob-skip:hover`), увеличенная мишень по Фитсу за счёт паддинга.
struct SkipButton: View {
    let action: () -> Void
    @State private var isHovering = false
    var body: some View {
        Button(action: action) {
            Text("Skip for now")
                .font(.system(size: 11))
                .foregroundStyle(isHovering ? OB.Text.secondary : OB.Text.tertiary)
                .padding(.vertical, 6).padding(.horizontal, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickCursor()
        .animation(OB.hoverAnim(isHovering), value: isHovering)
        .onHover { hovering in isHovering = hovering }
    }
}
