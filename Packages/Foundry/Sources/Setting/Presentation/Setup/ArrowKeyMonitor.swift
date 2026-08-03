import AppKit
import SwiftUI

/// Ловит ← / → на уровне окна (локальный NSEvent-монитор) и ведёт пагинацию
/// независимо от того, какой контрол держит фокус. Монитор снимается вместе с
/// мастером (dismantle).
struct ArrowKeyMonitor: NSViewRepresentable {
    // Аппаратные keyCode стрелок (независимы от раскладки).
    private static let leftArrowKeyCode: UInt16 = 123
    private static let rightArrowKeyCode: UInt16 = 124

    let onLeft: () -> Void
    let onRight: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let containerView = NSView()
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case Self.leftArrowKeyCode:
                onLeft()
                return nil
            case Self.rightArrowKeyCode:
                onRight()
                return nil
            default: return event
            }
        }
        return containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
        coordinator.monitor = nil
    }

    final class Coordinator { var monitor: Any? }
}
