import SwiftUI

/// Статусный орб — визуальный центр направления «чёрный/синий/пурпур».
/// Пульсирует, пока идёт ран; тонируется исходом после завершения.
struct OrbView: View {
    let phase: RunStore.Phase

    @State private var pulsing = false

    private var colors: [Color] {
        switch phase {
        case .idle: return [.init(white: 0.35), .init(white: 0.15)]
        case .running: return [.cyan, .blue, .purple]
        case .finished: return [.blue, .purple]
        case .failed: return [.pink, .purple]
        }
    }

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: colors,
                    center: .init(x: 0.35, y: 0.3),
                    startRadius: 1,
                    endRadius: 16
                )
            )
            .frame(width: 22, height: 22)
            .shadow(
                color: phase.isRunning ? .purple.opacity(0.8) : .clear,
                radius: pulsing ? 12 : 4
            )
            .scaleEffect(phase.isRunning && pulsing ? 1.12 : 1.0)
            .animation(
                phase.isRunning
                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                    : .default,
                value: pulsing
            )
            .onChange(of: phase.isRunning, initial: true) { _, isRunning in
                pulsing = isRunning
            }
            .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        switch phase {
        case .idle: "Готов"
        case .running: "Claude работает"
        case .finished: "Завершено"
        case .failed: "Ошибка"
        }
    }
}
