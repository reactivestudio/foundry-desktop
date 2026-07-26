import SwiftUI

/// Статусный орб — визуальный центр направления «чёрный/синий/пурпур».
/// Пульсирует, пока идёт ран; тонируется исходом после завершения.
struct OrbView: View {
    let phase: RunStore.Phase

    @State private var isPulsing = false

    private var style: OrbPhaseStyle { OrbPhaseStyle(phase: phase) }

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: style.colors,
                    center: .init(x: 0.35, y: 0.3),
                    startRadius: 1,
                    endRadius: 16
                )
            )
            .frame(width: 22, height: 22)
            .shadow(
                color: phase.isRunning ? .purple.opacity(0.8) : .clear,
                radius: isPulsing ? 12 : 4
            )
            .scaleEffect(phase.isRunning && isPulsing ? 1.12 : 1.0)
            .animation(
                phase.isRunning
                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .onChange(of: phase.isRunning, initial: true) { _, isRunning in
                isPulsing = isRunning
            }
            .accessibilityLabel(style.accessibilityLabel)
    }
}
