import Core
import SwiftUI

/// Кнопка Allow → «✓ Granted» (зелёный факт, больше не кнопка).
struct GrantButton: View {
    let isGranted: Bool
    let action: () -> Void
    @State private var isHovering = false
    var body: some View {
        if isGranted {
            HStack(spacing: 4) {
                CheckTick(size: 13)
                Text("Granted")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(OB.success)
        } else {
            Button(action: action) {
                Text("Allow")
                    // тот же токен, что Install: кнопка целиком меньше, пропорции/радиус те же
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(height: 22).padding(.horizontal, 9)
                    .background(OB.squircle(7).fill(isHovering ? OB.ultraHover : OB.ultramarine))
            }
            .buttonStyle(.plain)
            .clickCursor()
            .animation(OB.hoverAnim(isHovering), value: isHovering)
            .onHover { isHovering = $0 }
        }
    }
}
