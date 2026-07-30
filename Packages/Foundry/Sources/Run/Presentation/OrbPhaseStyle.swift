import Core
import SwiftUI

/// Оформление статусного орба по фазе рана.
struct OrbPhaseStyle: Equatable {
    let colors: [Color]
    let accessibilityLabel: String

    init(phase: RunStore.Phase) {
        switch phase {
        case .idle:
            colors = RunPalette.orbIdle
            accessibilityLabel = "Готов"
        case .running:
            colors = RunPalette.orbRunning
            accessibilityLabel = "Claude работает"
        case .finished:
            colors = RunPalette.orbFinished
            accessibilityLabel = "Завершено"
        case .failed:
            colors = RunPalette.orbFailed
            accessibilityLabel = "Ошибка"
        }
    }
}
